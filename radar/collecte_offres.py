"""Mon Radar Emploi — collecteur prudent, sans scraping non autorisé.

Entrée facultative : RADAR_SOURCES_JSON, URL HTTPS d'un flux JSON autorisé.
Format du flux : liste d'objets ou {'offres': [...]}.
Champs : titre, entreprise, ville, url, date_publication, description, salaire, source.
Aucune donnée n'est publiée si aucune offre vérifiable n'est disponible.
"""
import json
import os
import re
import sys
from datetime import datetime, timedelta
from pathlib import Path
from urllib.parse import urlparse
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo

SORTIE = Path('radar_mouries.json')
DATE = datetime.now(ZoneInfo('Europe/Paris')).date()
VILLES = ('mouries', 'mouriès', 'saint-martin-de-crau', 'saint martin de crau',
          'arles', 'salon-de-provence', 'salon de provence', 'eyguieres', 'eyguières',
          'istres', 'miramas', 'saint-remy-de-provence', 'saint rémy de provence',
          'cavaillon', 'chateaurenard', 'châteaurenard', 'tarascon', 'graveson',
          'maussane', 'paradou', 'fontvieille')
CIBLES = ('responsable support', 'manager support', 'service desk', 'helpdesk',
          'responsable informatique', 'coordinateur support', 'delivery manager',
          'service delivery', 'customer success', 'responsable service client',
          'responsable relation client', 'responsable sav', 'chargé de recrutement',
          'charge de recrutement', 'responsable expérience client', 'formateur informatique')
EXCLUSIONS = ('hôpital', 'hopital', 'hospitalier', 'cybersécurité', 'cybersecurite',
              'développeur', 'developpeur', 'administrateur systèmes',
              'administrateur systemes', 'alternance', 'apprentissage', 'stage')


def texte(x):
    return str(x or '').strip()


def normaliser(s):
    import unicodedata
    return ''.join(c for c in unicodedata.normalize('NFKD', texte(s).lower())
                   if not unicodedata.combining(c))


def lire_flux(url):
    parsed = urlparse(url)
    if parsed.scheme != 'https' or not parsed.netloc:
        raise ValueError('Le flux doit être une URL HTTPS')
    req = Request(url, headers={'User-Agent': 'MonRadarEmploi/1.9.5',
                                'Accept': 'application/json'})
    with urlopen(req, timeout=20) as response:
        data = response.read(3_000_001)
    if len(data) > 3_000_000:
        raise ValueError('Flux trop volumineux')
    contenu = json.loads(data.decode('utf-8'))
    offres = contenu if isinstance(contenu, list) else contenu.get('offres', [])
    if not isinstance(offres, list):
        raise ValueError('Format du flux incorrect')
    return offres


def filtrer(offres):
    resultat, deja_vus = [], set()
    for brut in offres:
        if not isinstance(brut, dict):
            continue
        titre = texte(brut.get('titre') or brut.get('title'))
        entreprise = texte(brut.get('entreprise') or brut.get('company'))
        ville = texte(brut.get('ville') or brut.get('location'))
        url = texte(brut.get('url') or brut.get('lien'))
        description = texte(brut.get('description'))
        source = texte(brut.get('source') or 'Flux autorisé')
        if not (titre and entreprise and ville and url):
            continue
        if urlparse(url).scheme not in ('https', 'http'):
            continue
        lieu = normaliser(ville)
        if not any(normaliser(v) in lieu for v in VILLES):
            continue
        mots = normaliser(titre + ' ' + description)
        if any(normaliser(x) in mots for x in EXCLUSIONS):
            continue
        titre_n = normaliser(titre)
        if not any(normaliser(x) in titre_n for x in CIBLES):
            continue
        date_pub = texte(brut.get('date_publication'))[:10]
        if date_pub:
            try:
                d = datetime.strptime(date_pub, '%Y-%m-%d').date()
                if d > DATE or d < DATE - timedelta(days=30):
                    continue
            except ValueError:
                continue
        cle = (normaliser(titre), normaliser(entreprise), normaliser(ville))
        if cle in deja_vus:
            continue
        deja_vus.add(cle)
        prioritaire = any(x in titre_n for x in ('responsable', 'manager', 'delivery'))
        resultat.append({
            'titre': titre, 'entreprise': entreprise, 'ville': ville,
            'url': url, 'source': source, 'date_publication': date_pub,
            'salaire': texte(brut.get('salaire')),
            'classement': 'a_postuler' if prioritaire else 'a_etudier',
        })
    return resultat


def main():
    url = os.getenv('RADAR_SOURCES_JSON', '').strip()
    if not url:
        print('Aucun flux autorisé configuré : bilan précédent conservé.')
        return
    try:
        brutes = lire_flux(url)
        offres = filtrer(brutes)
    except Exception as exc:
        print(f'Collecte indisponible : {exc}. Bilan précédent conservé.', file=sys.stderr)
        return
    if not offres:
        print('Aucune offre validée : bilan précédent conservé (pas de faux zéro).')
        return
    bilan = {
        'format': 'mon_radar_emploi_radar', 'version': 1,
        'date': DATE.isoformat(),
        'compteurs': {
            'a_postuler': sum(o['classement'] == 'a_postuler' for o in offres),
            'a_etudier': sum(o['classement'] == 'a_etudier' for o in offres),
        },
        'offres': offres,
    }
    temporaire = SORTIE.with_suffix('.json.tmp')
    temporaire.write_text(json.dumps(bilan, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    temporaire.replace(SORTIE)
    print(f'{len(offres)} offres valides publiées pour {DATE}.')


if __name__ == '__main__':
    main()
