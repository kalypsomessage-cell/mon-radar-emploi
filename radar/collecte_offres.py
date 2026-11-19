
import json
from datetime import datetime
from zoneinfo import ZoneInfo
from pathlib import Path

# Mon Radar Emploi - V1.9.5
# Sources prevues : France Travail, Indeed, Hellowork

FICHIER = Path("radar_mouries.json")

def collecter_france_travail():
    # En attente de l'autorisation API
    return None

def collecter_indeed():
    # En attente d'une source autorisee
    return None

def collecter_hellowork():
    # En attente d'une source autorisee
    return None

def main():
    date_du_jour = datetime.now(
        ZoneInfo("Europe/Paris")
    ).strftime("%Y-%m-%d")

    sources = {
        "france_travail": collecter_france_travail(),
        "indeed": collecter_indeed(),
        "hellowork": collecter_hellowork(),
    }

    print("Mon Radar Emploi V1.9.5")
    print("Date :", date_du_jour)

    for nom, resultat in sources.items():
        if resultat is None:
            print(nom, ": source non disponible")

    # Ne pas publier un faux bilan vide.
    # Conserver le dernier bilan existant.
    if FICHIER.exists():
        bilan = json.loads(
            FICHIER.read_text(encoding="utf-8")
        )
        print("Dernier bilan conserve :", bilan.get("date"))
    else:
        print("Aucun bilan existant.")

    print("Aucune modification des candidatures.")

if __name__ == "__main__":
    main()
