import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'pdf_download_stub.dart' if (dart.library.html) 'pdf_download_web.dart' as browser_download;

// Corrige les anciennes notes contenant un retour à la ligne écrit littéralement.
String readableNotes(String value) => value.replaceAll(r'\n', '\n');

void main() => runApp(const RadarApp());

class RadarApp extends StatelessWidget {
  const RadarApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Mon Radar Emploi',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFF1F5FA),
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF246BB3), primary: const Color(0xFF173B6D)),
          appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFF1F5FA), foregroundColor: Color(0xFF173B6D)),
          cardTheme: CardThemeData(color: Colors.white, elevation: 0, margin: const EdgeInsets.symmetric(vertical: 6), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
          filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)))),
          inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(13))),
        ),
        home: const RadarHome(),
      );
}

class JobReview {
  final String title;
  final String content;
  final int score;
  final List<String> reasons;
  final bool excluded;
  String status;
  String company;
  String url;
  String notes;
  String letterDraft;
  String createdAt;
  String intermediary;
  String lastContactAt;
  String nextFollowUpAt;
  String applicationSentAt;
  bool followUpDismissed;
  bool hadInterview;
  Map<String, dynamic> toJson() => {'title': title, 'content': content, 'score': score, 'reasons': reasons, 'excluded': excluded, 'status': status, 'company': company, 'url': url, 'notes': notes, 'letterDraft': letterDraft, 'createdAt': createdAt, 'intermediary': intermediary, 'lastContactAt': lastContactAt, 'nextFollowUpAt': nextFollowUpAt, 'applicationSentAt': applicationSentAt, 'followUpDismissed': followUpDismissed, 'hadInterview': hadInterview};
  factory JobReview.fromJson(Map<String, dynamic> data) => JobReview(
    data['title'] as String, data['content'] as String, data['score'] as int,
    List<String>.from(data['reasons'] as List), data['excluded'] as bool,
    status: data['status'] as String? ?? 'À examiner', company: data['company'] as String? ?? '', url: data['url'] as String? ?? '', notes: data['notes'] as String? ?? '', letterDraft: data['letterDraft'] as String? ?? '', createdAt: data['createdAt'] as String? ?? '', intermediary: data['intermediary'] as String? ?? '', lastContactAt: data['lastContactAt'] as String? ?? '', nextFollowUpAt: data['nextFollowUpAt'] as String? ?? '', applicationSentAt: data['applicationSentAt'] as String? ?? '', followUpDismissed: data['followUpDismissed'] == true, hadInterview: data['hadInterview'] == true || _legacyInterview(data));
  JobReview(this.title, this.content, this.score, this.reasons, this.excluded,
      {this.status = 'À examiner', this.company = '', this.url = '', this.notes = '', this.letterDraft = '', this.intermediary = '', this.lastContactAt = '', this.nextFollowUpAt = '', this.applicationSentAt = '', this.followUpDismissed = false, this.hadInterview = false, String? createdAt}) : createdAt = createdAt ?? DateTime.now().toIso8601String();
}

// Migration des trois candidatures historiques confirmees par l'utilisateur.
// Une fois sauvegarde, le drapeau persiste independamment du statut.
bool _legacyInterview(Map<String, dynamic> data) {
  final name = normalizeOfferText('${data['company'] ?? ''} ${data['title'] ?? ''}');
  return name.contains('lecasud') || name.contains('bconnex') ||
      name.contains('marie blachere');
}

// V1.5 : correspondances locales et explicables, sans IA ni ajout de qualifications.
const radarStatuses = <String>[
  'À examiner', 'À postuler', 'Candidature envoyée',
  'Entretien réalisé', 'Attente réponse entretien', 'En attente retour client', 'Refus / Clôture',
  'Entretien', 'Refus', 'Offre reçue',
];

String radarCategory(String status) {
  switch (status) {
    case 'À examiner':
    case 'À postuler':
    case 'Offre reçue':
      return 'À postuler';
    case 'Candidature envoyée':
      return 'En attente de réponse';
    case 'Entretien réalisé':
      return 'Entretien réalisé';
    case 'Entretien':
    case 'Attente réponse entretien':
    case 'En attente retour client':
      return 'Attente réponse entretien';
    default:
      return 'Refus / Clôture';
  }
}

class OfferCriterion {
  final String label;
  final RegExp pattern;
  final List<String> evidence;
  OfferCriterion(this.label, String regex, this.evidence)
      : pattern = RegExp(regex, caseSensitive: false);
}

final offerCriteria = <OfferCriterion>[
  OfferCriterion('Management d’équipe', r'management|encadrement|manager|pilotage d.equipe|chef d.equipe', ['management', 'équipe', 'collaborateurs', 'techniciens']),
  OfferCriterion('Recrutement', r'recrutement|recruter|sourcing|selection des candidats', ['recrutement', 'sélection des profils', 'choix des candidats']),
  OfferCriterion('Entretiens de recrutement', r'entretiens? d.embauche|conduite d.entretiens|entretiens? de recrutement', ['entretiens', 'candidats']),
  OfferCriterion('Intégration et tutorat', r'integration|onboarding|tutorat|accueil des nouveaux', ['intégration', 'tutorat', 'accompagnement']),
  OfferCriterion('Relation client et satisfaction', r'relation client|satisfaction client|service clients|experience client', ['relation utilisateurs', 'qualité de service', 'support', 'clients']),
  OfferCriterion('Qualité de service', r'qualite de service|qualite|sla|engagements de service', ['qualité de service', 'amélioration continue', 'support']),
  OfferCriterion('Amélioration continue', r'amelioration continue|lean|optimisation des processus', ['amélioration continue', 'backlog', 'lean']),
  OfferCriterion('Coordination', r'coordination|planification|organisation des interventions', ['coordination', 'planning', 'interventions']),
  OfferCriterion('Gestion des incidents', r'incidents|escalades|resolution de problemes', ['incidents', 'escalades', 'situations complexes']),
  OfferCriterion('Indicateurs et reporting', r'kpi|reporting|indicateurs|tableaux de bord', ['kpi', 'reporting', 'indicateurs']),
  OfferCriterion('Gestion budgétaire', r'budget|achats|contrats fournisseurs', ['budget', 'fournisseurs', 'contrats']),
  OfferCriterion('Support informatique', r'support informatique|helpdesk|service desk|support n1|support n2', ['support', 'glpi', 'itsm']),
  OfferCriterion('GLPI / ITSM', r'glpi|itsm|outil de ticketing', ['glpi', 'itsm']),
  OfferCriterion('Microsoft 365', r'microsoft 365|office 365', ['microsoft 365', 'office 365']),
  OfferCriterion('Anglais', r'anglais|english', ['anglais']),
  // Ces exigences sont détectées, mais jamais ajoutées au CV sans preuve.
  OfferCriterion('SAP', r'\bsap\b', ['sap']),
  OfferCriterion('Paie', r'gestion de la paie|bulletins de paie|logiciel de paie', ['paie']),
  OfferCriterion('Gestion des réclamations commerciales', r'reclamations clients|gestion des reclamations', ['réclamations commerciales']),
];

String normalizeOfferText(String input) => input.toLowerCase()
    .replaceAll(RegExp('[àâä]'), 'a').replaceAll(RegExp('[éèêë]'), 'e')
    .replaceAll(RegExp('[îï]'), 'i').replaceAll(RegExp('[ôö]'), 'o')
    .replaceAll(RegExp('[ùûü]'), 'u').replaceAll('ç', 'c')
    .replaceAll('’', "'");

class RadarHome extends StatefulWidget {
  const RadarHome({super.key});
  @override
  State<RadarHome> createState() => _RadarHomeState();
}

class _RadarHomeState extends State<RadarHome> {
  int tab = 0;
  final title = TextEditingController();
  final description = TextEditingController();
  final company = TextEditingController();
  final link = TextEditingController();
  final search = TextEditingController();
  String statusFilter = 'Toutes';
  final distance = TextEditingController(text: '40');
  final jobs = <JobReview>[];
  final candidateName = TextEditingController();
  final candidateContact = TextEditingController();
  final candidateHeadline = TextEditingController();
  final candidateExperience = TextEditingController();
  final candidateSkills = TextEditingController();
  final candidateEducation = TextEditingController();
  final GlobalKey _analysisResultKey = GlobalKey();
  JobReview? last;
  bool excludeTravel = true;
  bool excludeTechnical = true;
  bool excludeHospital = true;
  bool excludeDevelopment = true;

  @override
  void initState() {
    super.initState();
    loadSaved();
  }

  Future<void> loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      distance.text = prefs.getString('distance') ?? '40';
      candidateName.text = prefs.getString('candidateName') ?? '';
      candidateContact.text = prefs.getString('candidateContact') ?? '';
      candidateHeadline.text = prefs.getString('candidateHeadline') ?? '';
      candidateExperience.text = prefs.getString('candidateExperience') ?? '';
      candidateSkills.text = prefs.getString('candidateSkills') ?? '';
      candidateEducation.text = prefs.getString('candidateEducation') ?? '';
      excludeTravel = prefs.getBool('travel') ?? true;
      excludeTechnical = prefs.getBool('technical') ?? true;
      excludeHospital = prefs.getBool('hospital') ?? true;
      excludeDevelopment = prefs.getBool('development') ?? true;
      try {
        final saved = jsonDecode(prefs.getString('jobs') ?? '[]') as List;
        jobs.addAll(saved.map((e) => JobReview.fromJson(Map<String, dynamic>.from(e as Map))));
        for (final job in jobs) {
          if (job.status == 'Entretien réalisé' || job.status == 'Entretien' ||
              job.status == 'Attente réponse entretien' ||
              job.status == 'En attente retour client') {
            job.hadInterview = true;
          }
        }
      } catch (_) { /* A damaged local database must not crash the UI. */ }
    });
  }

  Map<String, dynamic> backupData() => {
    'format': 'mon_radar_emploi_backup',
    'version': 1,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'profile': {
      'distance': distance.text,
      'travel': excludeTravel,
      'technical': excludeTechnical,
      'hospital': excludeHospital,
      'development': excludeDevelopment,
      'candidateName': candidateName.text,
      'candidateContact': candidateContact.text,
      'candidateHeadline': candidateHeadline.text,
      'candidateExperience': candidateExperience.text,
      'candidateSkills': candidateSkills.text,
      'candidateEducation': candidateEducation.text,
    },
    'jobs': jobs.map((e) => e.toJson()).toList(),
  };

  // Un nom daté évite d'écraser une sauvegarde précédente dans OneDrive.
  String backupFileName() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'mon_radar_emploi_${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}.json';
  }

  Future<void> showOneDriveHelp() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sauvegarder avec OneDrive'),
        content: const SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Sur ton iPhone :', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('1. Appuie sur « Exporter ma sauvegarde ». ' 
                  'Si la feuille de partage apparaît, choisis OneDrive ou « Enregistrer dans Fichiers » puis OneDrive.'),
              SizedBox(height: 8),
              Text('2. Si un fichier est téléchargé au lieu d’être partagé, ' 
                  'ouvre-le dans Fichiers / Téléchargements, puis déplace-le vers OneDrive.'),
              SizedBox(height: 8),
              Text('3. Vérifie que le fichier JSON est bien visible dans OneDrive.'),
              SizedBox(height: 14),
              Text('Pour restaurer :', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Appuie sur « Restaurer depuis un fichier JSON », ' 
                  'sélectionne le fichier dans Fichiers / OneDrive, puis confirme.'),
              SizedBox(height: 12),
              Text('Important : les modifications restent locales jusqu’à un nouvel export. ' 
                  'La restauration remplace les données actuelles, elle ne les fusionne pas.'),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx),
          child: const Text('Compris'))],
      ),
    );
  }

  Future<void> exportBackup() async {
    try {
      final bytes = Uint8List.fromList(utf8.encode(
        const JsonEncoder.withIndent('  ').convert(backupData()),
      ));
      if (kIsWeb) {
        // share_plus Web downloads files when the Web Share API is unavailable.
        // Unlike FilePicker.saveFile, this route is implemented by share_plus.
        await Share.shareXFiles(
          [XFile.fromData(bytes,
              name: backupFileName(),
              mimeType: 'application/json')],
          subject: 'Sauvegarde Mon Radar Emploi',
          text: 'Sauvegarde à conserver en lieu sûr.',
        );
        if (mounted) {
          showMessage('Vérifie le téléchargement ou le partage de la sauvegarde.');
        }
        return;
      }
      await Share.shareXFiles(
        [XFile.fromData(bytes,
          name: backupFileName(),
          mimeType: 'application/json')],
        text: 'Sauvegarde Mon Radar Emploi — à conserver dans un emplacement sûr.',
      );
    } catch (e) {
      if (mounted) showMessage('Export impossible : $e');
    }
  }

  // V1.7 : import d'un lot de résultats des radars, sans accès direct à ChatGPT.
  Future<void> importRadarOffers() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['json'], withData: true);
      if (picked == null) return;
      final selected = picked.files.single;
      final bytes = selected.bytes;
      if (bytes == null || bytes.length > 2 * 1024 * 1024) {
        if (mounted) showMessage('Fichier absent ou trop volumineux (2 Mo maximum).');
        return;
      }
      final raw = jsonDecode(utf8.decode(bytes));
      if (raw is! Map || raw['format'] != 'mon_radar_emploi_offres' ||
          raw['version'] != 1 || raw['offres'] is! List) {
        if (mounted) showMessage('Format incorrect : utilise un export d’annonces V1.6.');
        return;
      }
      final entries = raw['offres'] as List;
      if (entries.length > 200) {
        if (mounted) showMessage('Maximum 200 annonces par fichier.');
        return;
      }
      final imported = <JobReview>[];
      var ignored = 0;
      String norm(String v) => normalizeOfferText(v.trim()).replaceAll(RegExp(r'\s+'), ' ');
      String key(String t, String c, String u) => u.trim().isNotEmpty
          ? 'url:${u.trim().toLowerCase().replaceAll(RegExp(r"/#.*$"), "")}'
          : 'poste:${norm(t)}|${norm(c)}';
      final known = <String>{
        for (final j in jobs) ...[
          key(j.title, j.company, j.url),
          'poste:${norm(j.title)}|${norm(j.company)}',
        ],
      };
      for (final entry in entries) {
        if (entry is! Map) { ignored++; continue; }
        String field(String k) => entry[k] is String ? (entry[k] as String).trim() : '';
        final t = field('titre');
        final c = field('entreprise');
        final u = field('url');
        final body = field('description');
        final place = field('lieu');
        if (t.isEmpty || (u.isEmpty && body.isEmpty)) { ignored++; continue; }
        final id = key(t, c, u);
        final titleKey = 'poste:${norm(t)}|${norm(c)}';
        if (known.contains(id) || known.contains(titleKey)) { ignored++; continue; }
        known.addAll([id, titleKey]);
        final content = [if (place.isNotEmpty) 'Lieu : $place', body,
          if (u.isNotEmpty) 'Lien : $u'].where((x) => x.isNotEmpty).join('\n');
        final assessed = evaluate(t, content);
        imported.add(JobReview(t, content, assessed.score, assessed.reasons,
          assessed.excluded, company: c, url: u, status: 'À postuler'));
      }
      if (!mounted) return;
      if (imported.isEmpty) {
        showMessage('Aucune nouvelle annonce : $ignored ignorée(s) ou déjà présente(s).');
        return;
      }
      setState(() { jobs.addAll(imported); tab = 3; });
      await saveAll();
      if (mounted) showMessage('${imported.length} annonce(s) importée(s), $ignored ignorée(s).');
    } catch (_) {
      if (mounted) showMessage('Import impossible : fichier JSON invalide.');
    }
  }

  Future<void> importBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: ['json'], withData: true);
      if (result == null) return;
      final selected = result.files.single;
      final bytes = selected.bytes;
      if (bytes == null || bytes.length > 5 * 1024 * 1024) {
        showMessage('Fichier absent ou trop volumineux (maximum 5 Mo).');
        return;
      }
      final data = jsonDecode(utf8.decode(bytes));
      if (data is! Map || data['format'] != 'mon_radar_emploi_backup' || data['version'] != 1 || data['profile'] is! Map || data['jobs'] is! List) {
        showMessage('Ce fichier n’est pas une sauvegarde compatible.');
        return;
      }
      final profile = Map<String, dynamic>.from(data['profile'] as Map);
      if ((data['jobs'] as List).length > 10000) { showMessage('Sauvegarde trop volumineuse.'); return; }
      final restored = (data['jobs'] as List).map((e) => JobReview.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      if (!mounted) return;
      final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Restaurer la sauvegarde ?'),
        content: Text('Cette opération remplacera le profil et les ${jobs.length} offres actuelles par ${restored.length} offres sauvegardées.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restaurer'))],
      ));
      if (confirm != true || !mounted) return;
      setState(() {
        distance.text = (profile['distance'] ?? '40').toString();
        excludeTravel = profile['travel'] == true;
        excludeTechnical = profile['technical'] == true;
        excludeHospital = profile['hospital'] == true;
        excludeDevelopment = profile['development'] == true;
        candidateName.text = (profile['candidateName'] ?? '').toString();
        candidateContact.text = (profile['candidateContact'] ?? '').toString();
        candidateHeadline.text = (profile['candidateHeadline'] ?? '').toString();
        candidateExperience.text = (profile['candidateExperience'] ?? '').toString();
        candidateSkills.text = (profile['candidateSkills'] ?? '').toString();
        candidateEducation.text = (profile['candidateEducation'] ?? '').toString();
        jobs..clear()..addAll(restored);
        last = null;
      });
      await saveAll();
      if (mounted) showMessage('Sauvegarde restaurée : ${restored.length} offres.');
    } catch (e) {
      if (mounted) showMessage('Import impossible : fichier invalide ou illisible.');
    }
  }

  void showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> saveAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('distance', distance.text);
    await prefs.setString('candidateName', candidateName.text);
    await prefs.setString('candidateContact', candidateContact.text);
    await prefs.setString('candidateHeadline', candidateHeadline.text);
    await prefs.setString('candidateExperience', candidateExperience.text);
    await prefs.setString('candidateSkills', candidateSkills.text);
    await prefs.setString('candidateEducation', candidateEducation.text);
    await prefs.setBool('travel', excludeTravel);
    await prefs.setBool('technical', excludeTechnical);
    await prefs.setBool('hospital', excludeHospital);
    await prefs.setBool('development', excludeDevelopment);
    await prefs.setString('jobs', jsonEncode(jobs.map((e) => e.toJson()).toList()));
  }

  void updatePreference(VoidCallback change) { setState(change); saveAll(); }


  @override
  void dispose() {
    company.dispose();
    link.dispose();
    search.dispose();
    title.dispose();
    description.dispose();
    distance.dispose();
    candidateName.dispose();
    candidateContact.dispose();
    candidateHeadline.dispose();
    candidateExperience.dispose();
    candidateSkills.dispose();
    candidateEducation.dispose();
    super.dispose();
  }

  JobReview evaluate(String name, String body) {
    final s = '$name $body'.toLowerCase();
    var score = 35;
    final reasons = <String>[];
    var excluded = false;
    void positive(String pattern, String message, int points) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(s)) {
        score += points;
        reasons.add('✓ $message');
      }
    }
    void negative(String pattern, String message, {bool blocking = false}) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(s)) {
        score -= blocking ? 35 : 12;
        excluded = excluded || blocking;
        reasons.add('! $message');
      }
    }
    positive(r'responsable support|service desk|helpdesk|coordinateur support|support informatique',
        'Métier proche du support informatique', 25);
    positive(r'management|manager|encadrement|pilotage d.équipe|team leader',
        'Responsabilités de management', 15);
    positive(r'service client|satisfaction client|relation client|customer success|responsable sav',
        'Dimension relation client', 15);
    positive(r'\bcdi\b', 'Contrat CDI', 10);
    positive(r'chargé.e? de recrutement|chargé de recrutement|talent acquisition|recrutement et intégration', 'Métier du recrutement', 20);
    negative(r'déplacements fréquents|mobilité nationale|déplacements nationaux|déplacements réguliers',
        'Déplacements professionnels fréquents', blocking: excludeTravel);
    negative(r'cybersécurité|administrateur système|administrateur réseau|expert réseau|ingénieur infrastructure',
        'Poste principalement technique infrastructure/réseaux', blocking: excludeTechnical);
    negative(r'hôpital|hospitalier|centre hospitalier|clinique',
        'Environnement hospitalier', blocking: excludeHospital);
    negative(r'développeur|développement logiciel|programmation applicative',
        'Développement logiciel', blocking: excludeDevelopment);
    negative(r'\bcdd\b', 'Contrat CDD');
    // A number of kilometres in an advert may describe travel, not commuting.
    // Never infer home-to-work distance from arbitrary text.
    final km = RegExp(r'(?:distance depuis domicile|trajet domicile.travail)\s*[:=]\s*(\d{1,3})\s?km\b', caseSensitive: false).firstMatch(s);
    if (km != null) {
      final found = int.tryParse(km.group(1)!);
      final max = int.tryParse(distance.text) ?? 40;
      if (found != null && found > max) {
        excluded = true;
        score -= 30;
        reasons.add('! Distance mentionnée : $found km, limite $max km');
      }
    } else {
      reasons.add('À vérifier : distance réelle domicile-travail');
    }
    final salary = RegExp(r'(?:salaire|rémunération|package)[^\n]{0,75}', caseSensitive: false).firstMatch(body);
    if (salary == null) {
      reasons.add('À vérifier : rémunération non identifiée');
    } else {
      reasons.add('Rémunération mentionnée : à comparer au salaire souhaité');
    }
    reasons.add('À vérifier : missions exactes et fréquence des déplacements');
    // An incomplete offer cannot obtain a perfect score.
    final unknownDistance = km == null;
    final unknownSalary = salary == null;
    final maximum = (unknownDistance || unknownSalary) ? 79 : 95;
    if (excluded) score = score.clamp(0, 39);
    return JobReview(name, body, score.clamp(0, maximum).toInt(), reasons, excluded, company: company.text.trim(), url: link.text.trim());
  }

  // Simple, reviewable extraction from the pasted advertisement; no network or AI.
  void extractOfferFields() {
    final raw = description.text.trim();
    if (raw.isEmpty) { showMessage('Colle d’abord le texte de l’annonce.'); return; }
    final lines = raw.split(RegExp(r'\r?\n')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    String? field(RegExp pattern) {
      for (final line in lines.take(30)) {
        final match = pattern.firstMatch(line);
        if (match != null) return match.group(1)?.trim();
      }
      return null;
    }
    final foundTitle = field(RegExp(r'^(?:poste|intitulé|emploi|offre)\s*[:\-]\s*(.+)$', caseSensitive: false));
    final foundCompany = field(RegExp(r'^(?:entreprise|société|employeur)\s*[:\-]\s*(.+)$', caseSensitive: false));
    final foundUrl = RegExp(r'https?://[^\s<>]+').firstMatch(raw)?.group(0);
    setState(() {
      if (title.text.trim().isEmpty && foundTitle != null) title.text = foundTitle;
      if (company.text.trim().isEmpty && foundCompany != null) company.text = foundCompany;
      if (link.text.trim().isEmpty && foundUrl != null) link.text = foundUrl;
    });
    showMessage('Champs reconnus renseignés si vides. Vérifie-les avant l’analyse.');
  }

  void analyze() {
    if (title.text.trim().isEmpty || description.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saisis un intitulé et le texte de l’annonce.')));
      return;
    }
    setState(() => last = evaluate(title.text.trim(), description.text.trim()));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final resultContext = _analysisResultKey.currentContext;
      if (mounted && resultContext != null) {
        Scrollable.ensureVisible(resultContext,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeInOut, alignment: 0.05);
      }
    });
  }

  Future<void> editNotes(JobReview job) async {
    final controller = TextEditingController(text: readableNotes(job.notes));
    final result = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: Text('Notes : ${job.title}'),
      content: TextField(controller: controller, maxLines: 6,
        decoration: const InputDecoration(hintText: 'Contact, date d’entretien, prochaines actions…', border: OutlineInputBorder())),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Enregistrer'))],
    ));
    controller.dispose();
    if (result == null || !mounted) return;
    setState(() => job.notes = result);
    await saveAll();
  }

  Future<void> deleteJob(JobReview job) async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Supprimer cette offre ?'),
      content: Text('« ${job.title} » sera retirée du suivi. Cette action est irréversible sans sauvegarde.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer'))],
    ));
    if (confirmed != true || !mounted) return;
    setState(() => jobs.remove(job));
    await saveAll();
  }

  Future<void> sendToChatGpt(JobReview job) async {
    final message = '''Analyse cette offre d’emploi par rapport à mon profil de management support informatique, relation client et recrutement. Signale les critères éliminatoires et les informations manquantes. N’invente rien.

Intitulé : ${job.title}
Entreprise : ${job.company}
Lien : ${job.url}
Annonce :
${job.content}''';
    await Share.share(message, subject: 'Analyse de candidature : ${job.title}');
  }


  // V0.7: a reviewed draft is stored with its offer and included in JSON backups.
  Future<void> prepareApplication(JobReview job) async {
    if (candidateName.text.trim().isEmpty || candidateExperience.text.trim().isEmpty) {
      showMessage('Complète ton nom et tes expériences dans Mon profil.');
      setState(() => tab = 1);
      return;
    }
    final companyLabel = job.company.trim().isEmpty ? 'votre entreprise' : job.company.trim();
    final offerText = '${job.title} ${job.content}'.toLowerCase();
    final normalizedOffer = normalizeOfferText(job.content);
    final criteriaFound = offerCriteria.where((c) => c.pattern.hasMatch(normalizedOffer)).toList();
    // Les preuves viennent exclusivement du profil enregistré et des réalisations vérifiées.
    final referenceEvidence = normalizeOfferText('${candidateExperience.text} ${candidateSkills.text} ${candidateEducation.text}');
    final matchingCriteria = criteriaFound.where((c) => c.evidence.any((e) => referenceEvidence.contains(normalizeOfferText(e)))).toList();
    final missingCriteria = criteriaFound.where((c) => !matchingCriteria.contains(c)).toList();
    final clientRole = RegExp(r'client|sav|customer|relation').hasMatch(job.title.toLowerCase());
    final recruitingRole = RegExp(r'recrut|talent|ressources humaines').hasMatch(job.title.toLowerCase());
    final roleIntro = recruitingRole
        ? 'Après plusieurs années à accompagner des équipes et à gérer de bout en bout le recrutement de mes collaborateurs, je souhaite mettre cette expérience humaine au service de votre activité.'
        : clientRole
            ? 'Mon parcours m’a convaincu que la qualité de la relation client repose sur l’écoute, la coordination des équipes et la recherche de solutions durables.'
            : 'Après plusieurs années consacrées au pilotage d’équipes de support informatique, je souhaite rejoindre une entreprise attentive à la qualité de son assistance et à la satisfaction de ses utilisateurs.';
    final roleApproach = recruitingRole
        ? 'J’apprécie particulièrement l’identification des compétences, l’accompagnement des personnes et la construction d’équipes durables.'
        : clientRole
            ? 'J’aime structurer les échanges, fluidifier la résolution des difficultés et faire progresser la qualité de service avec les collaborateurs.'
            : 'Pour moi, un support performant ne repose pas uniquement sur la technique : il exige une organisation claire, une communication efficace et une équipe impliquée.';
    final relevantTopic = offerText.contains('amélioration continue') || offerText.contains('qualité')
        ? 'L’attention portée à la qualité et à l’amélioration continue dans votre annonce rejoint particulièrement ma manière de travailler.'
        : offerText.contains('équipe') || offerText.contains('management')
            ? 'La dimension collective du poste retient particulièrement mon attention : accompagner les équipes et développer leur autonomie sont des missions auxquelles je tiens.'
            : 'Les missions décrites dans votre annonce m’intéressent et je serais heureux d’en découvrir les priorités avec vous.';
    final suggested = '''Objet : Candidature au poste de ${job.title}

Madame, Monsieur,

$roleIntro

$roleApproach $relevantTopic

Au cours de mon parcours, j’ai appris à conjuguer sens du service, organisation et accompagnement des collaborateurs. Je souhaite aujourd’hui mettre cette approche au service de ${job.company.trim().isEmpty ? 'votre entreprise' : companyLabel}, en m’adaptant à ses besoins et à ses méthodes.

Je serais heureux de pouvoir échanger avec vous sur les enjeux du poste et la contribution que je pourrais apporter à votre équipe.

Je vous prie d’agréer, Madame, Monsieur, mes salutations distinguées.

${candidateName.text.trim()}''';
    final draft = TextEditingController(text: job.letterDraft.isEmpty ? suggested : job.letterDraft);
    if (!mounted) { draft.dispose(); return; }
    final action = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: Text('Atelier candidature : ${job.title}'),
      content: SizedBox(width: 650, child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Entreprise : $companyLabel'),
        const SizedBox(height: 10),
        const Text('V1.5 - Correspondances détectées dans l’annonce (analyse locale indicative)',
            style: TextStyle(fontWeight: FontWeight.bold)),
        Text(matchingCriteria.isEmpty
            ? 'Aucune correspondance certaine détectée.'
            : 'Présentes dans ton profil : ${matchingCriteria.map((c) => c.label).join(', ')}.'),
        if (missingCriteria.isNotEmpty) Text(
            'À vérifier, non ajoutées au CV : ${missingCriteria.map((c) => c.label).join(', ')}.',
            style: const TextStyle(color: Color(0xFF8A4A17))),
        const Text('Détection par mots-clés : elle ne prouve pas la maîtrise d’une compétence.',
            style: TextStyle(fontSize: 12)),
        if (job.letterDraft.isNotEmpty) const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Un ancien brouillon est enregistré. Utilise « Nouvelle proposition » pour obtenir la nouvelle rédaction.')),
        TextButton.icon(
          onPressed: () => draft.text = suggested,
          icon: const Icon(Icons.auto_awesome_outlined),
          label: const Text('Nouvelle proposition')),
        const SizedBox(height: 8),
        const Text('Brouillon local sans IA. Vérifie chaque affirmation avant utilisation. Le CV utilise les informations de ton profil.'),
        const SizedBox(height: 12),
        TextField(controller: draft, minLines: 12, maxLines: 20,
          decoration: const InputDecoration(labelText: 'Lettre modifiable', border: OutlineInputBorder())),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        TextButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Enregistrer le brouillon')),
        FilledButton(onPressed: () => Navigator.pop(ctx, 'cv'), child: const Text('Télécharger le CV')),
        FilledButton(onPressed: () => Navigator.pop(ctx, 'letter'), child: const Text('Télécharger la lettre')),
      ],
    ));
    final letter = draft.text.trim();
    draft.dispose();
    if (action == null || !mounted) return;
    setState(() => job.letterDraft = letter);
    await saveAll();
    if (action == 'save') { if (mounted) showMessage('Brouillon enregistré avec cette offre.'); return; }
    if (action == 'letter' && letter.isEmpty) { if (mounted) showMessage('La lettre est vide.'); return; }
    try {
      // PDF built-in fonts do not cover every typographic Unicode character.
      // Replace unsupported glyphs to avoid empty squares in generated PDFs.
      String clean(String value) => value
          .replaceAll('•', '  |  ')
          .replaceAll('—', ' - ')
          .replaceAll('–', '-')
          .replaceAll('’', "'")
          .replaceAll('‘', "'")
          .replaceAll('“', '"')
          .replaceAll('”', '"')
          .replaceAll('…', '...')
          .replaceAll('œ', 'oe')
          .replaceAll('Œ', 'OE')
          .replaceAll('€', 'EUR')
          .replaceAll(RegExp(r'[^\x09\x0A\x0D\x20-\x7E\xA0-\xFF]'), '');

      final navy = PdfColor.fromHex('173B6D');
      final muted = PdfColor.fromHex('59677A');
      final pale = PdfColor.fromHex('DDE7F2');
      final regular = pw.Font.helvetica();
      final bold = pw.Font.helveticaBold();
      pw.Widget heading(String label) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 13, bottom: 7),
        padding: const pw.EdgeInsets.only(bottom: 6),
        decoration: pw.BoxDecoration(border: pw.Border(
          bottom: pw.BorderSide(color: pale, width: 1.5))),
        child: pw.Text(label.toUpperCase(),
          style: pw.TextStyle(font: bold, fontSize: 11.5, color: navy)),
      );
      pw.Widget identity() => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(clean(candidateName.text.trim().toUpperCase()),
            style: pw.TextStyle(font: bold, fontSize: 22, color: navy)),
          pw.SizedBox(height: 7),
          pw.Text(clean(candidateContact.text.trim()),
            style: pw.TextStyle(font: regular, fontSize: 9.4, color: muted)),
          pw.SizedBox(height: 12),
          pw.Container(height: 3, color: navy),
        ],
      );
      // V1.1 : presentation lisible, et priorites selon le poste vise.
      final experienceLines = candidateExperience.text.trim().split('\n')
          .where((line) => line.trim().isNotEmpty).toList();
      final firstExperience = experienceLines.isEmpty ? '' : experienceLines.first;
      final firstParts = firstExperience.split(RegExp(r'\s+:\s+'));
      final firstTitle = firstParts.first.trim();
      final firstDetails = firstParts.length > 1
          ? firstParts.sublist(1).join(' : ').split(';')
              .map((item) => item.trim()).where((item) => item.isNotEmpty).toList()
          : <String>[];
      int priority(String item) {
        final t = item.toLowerCase();
        if (recruitingRole) {
          if (t.contains('management') || t.contains('collaborateur')) return 0;
          if (t.contains('coordination') || t.contains('équipe')) return 1;
        } else if (clientRole) {
          if (t.contains('utilisateur') || t.contains('support')) return 0;
          if (t.contains('management') || t.contains('collaborateur')) return 1;
          if (t.contains('kpi') || t.contains('reporting')) return 2;
        } else {
          if (t.contains('management') || t.contains('collaborateur')) return 0;
          if (t.contains('utilisateur') || t.contains('support')) return 1;
          if (t.contains('backlog') || t.contains('ticket')) return 2;
        }
        return 5;
      }
      // V1.4 : réalisations confirmées par le candidat, spécifiques au métier.
      // Le libellé officiel du poste reste inchangé.
      final isReferenceDistrimag = firstTitle.toLowerCase().contains('distrimag') &&
          firstTitle.toLowerCase().contains('responsable support informatique');
      final highlightedDetails = recruitingRole && isReferenceDistrimag
          ? <String>[
              'Recrutement de mes collaborateurs de A à Z : rédaction des annonces, tri des CV et sélection des profils',
              'Conduite personnelle des entretiens et choix final des candidats',
              'Intégration, accompagnement et développement des compétences des nouveaux collaborateurs',
              'Management d’une équipe allant jusqu’à 5 techniciens',
              'Coordination des activités et suivi de la qualité de service',
            ]
          : clientRole && isReferenceDistrimag
              ? <String>[
                  'Management d’une équipe allant jusqu’à 5 collaborateurs',
                  'Pilotage de la qualité de service pour environ 800 utilisateurs sur plusieurs sites',
                  'Coordination des interventions, gestion des situations complexes et des escalades',
                  'Amélioration continue : réduction d’un backlog initial d’environ 600 tickets',
                  'Suivi des indicateurs, reporting, fournisseurs, contrats et budgets',
                ]
              : (firstDetails.toList()
                  ..sort((a, b) => priority(a).compareTo(priority(b))));
      // V1.3 : classer les competences existantes, sans en inventer.
      final skills = candidateSkills.text.split(';')
          .map((item) => item.trim().replaceAll(RegExp(r'\.$'), ''))
          .where((item) => item.isNotEmpty).toList();
      int skillPriority(String item) {
        final s = item.toLowerCase();
        if (recruitingRole) {
          if (s.contains('management') || s.contains('équipe')) return 0;
          if (s.contains('qualité') || s.contains('amélioration')) return 1;
          if (s.contains('fournisseur') || s.contains('budget')) return 2;
        } else if (clientRole) {
          if (s.contains('qualité') || s.contains('amélioration')) return 0;
          if (s.contains('management') || s.contains('équipe')) return 1;
          if (s.contains('incident') || s.contains('escalade')) return 2;
          if (s.contains('kpi') || s.contains('reporting')) return 3;
        } else {
          if (s.contains('management') || s.contains('équipe')) return 0;
          if (s.contains('support') || s.contains('glpi') || s.contains('itsm')) return 1;
          if (s.contains('incident') || s.contains('escalade')) return 2;
          if (s.contains('kpi') || s.contains('reporting')) return 3;
        }
        return 5;
      }
      // Conserver les compétences du profil IT à l'identique.
      // Les autres profils présentent une sélection métier fondée sur
      // les responsabilités décrites dans le CV et confirmées par l'utilisateur.
      final orderedSkills = recruitingRole && isReferenceDistrimag
          ? <String>[
              'Recrutement de A à Z', 'Rédaction d’annonces', 'Tri et sélection des CV',
              'Conduite d’entretiens', 'Choix des candidats', 'Intégration',
              'Management d’équipe', 'Accompagnement et tutorat', 'Coordination',
            ]
          : clientRole && isReferenceDistrimag
              ? <String>[
                  'Management d’équipe', 'Qualité de service', 'Relation utilisateurs',
                  'Coordination d’équipe', 'Gestion des situations complexes',
                  'Amélioration continue', 'KPI / reporting', 'Fournisseurs et budget',
                ]
              : (skills.toList()
                  ..sort((a, b) => skillPriority(a).compareTo(skillPriority(b))));
      // Prioriser uniquement les éléments déjà validés dans la V1.4.
      // Le tri est stable en cas d'égalité ; aucun contenu n'est créé.
      int relevance(String value) {
        final normalized = normalizeOfferText(value);
        var points = 0;
        for (final criterion in matchingCriteria) {
          if (criterion.evidence.any((word) => normalized.contains(normalizeOfferText(word)))) {
            points += 2;
          }
        }
        return points;
      }
      List<String> rankForOffer(List<String> items) {
        final indexed = items.asMap().entries.toList();
        indexed.sort((a, b) {
          final difference = relevance(b.value).compareTo(relevance(a.value));
          return difference != 0 ? difference : a.key.compareTo(b.key);
        });
        return indexed.map((entry) => entry.value).toList();
      }
      final tailoredDetails = rankForOffer(highlightedDetails);
      final tailoredSkills = rankForOffer(orderedSkills);
      // Un titre cible n'est utilise que pour une famille de postes reconnue.
      // Pour le recrutement, ne pas se presenter comme recruteur experimente.
      final roleTitle = recruitingRole
          ? 'Chargé de recrutement | Management et intégration'
          : clientRole
              ? 'Management d’équipe - Relation client et qualité de service'
              : (candidateHeadline.text.trim().isEmpty
                  ? job.title : candidateHeadline.text.trim());
      final summary = recruitingRole && isReferenceDistrimag
          ? 'Manager expérimenté ayant assuré le recrutement complet de ses collaborateurs : annonces, sélection, entretiens, décision et intégration. Évolution vers un poste dédié au recrutement.'
          : clientRole && isReferenceDistrimag
              ? 'Manager orienté satisfaction des utilisateurs, coordination d’équipes et qualité de service. Pilotage multisite, gestion des situations complexes et amélioration continue.'
              : recruitingRole || clientRole
                  ? 'Expérience en management, coordination et qualité de service ; compétences à mettre en perspective avec le poste visé.'
                  : 'Responsable support informatique : pilotage multisite, management d’équipe et amélioration de la qualité de service pour environ 800 utilisateurs.';
      pw.Widget experienceEntry(String line, {bool prominent = false}) {
        final parts = line.split(RegExp(r'\s+:\s+'));
        final label = parts.first.trim();
        final details = parts.length > 1 ? parts.sublist(1).join(' : ').trim() : '';
        return pw.Padding(
          padding: pw.EdgeInsets.only(bottom: prominent ? 9 : 7),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(clean(label), style: pw.TextStyle(font: bold,
                fontSize: prominent ? 11.3 : 10.6, color: navy)),
              if (details.isNotEmpty) ...[
                pw.SizedBox(height: 3),
                pw.Text(clean(details), style: pw.TextStyle(
                  font: regular, fontSize: 10.2, lineSpacing: 3)),
              ],
            ]),
        );
      }
      final cv = pw.Document();
      cv.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(45, 32, 45, 30),
        build: (_) => [
          identity(),
          pw.SizedBox(height: 16),
          pw.Text(clean(roleTitle), style: pw.TextStyle(
              font: bold, fontSize: 17, color: navy)),
          pw.SizedBox(height: 8),
          pw.Text(clean(summary), style: pw.TextStyle(
              font: regular, fontSize: 10.8, lineSpacing: 3.5, color: muted)),
          heading('Expérience professionnelle'),
          if (firstExperience.isNotEmpty) ...[
            pw.Text(clean(firstTitle), style: pw.TextStyle(
                font: bold, fontSize: 11.5, color: navy)),
            pw.SizedBox(height: 6),
            ...tailoredDetails.map((detail) => pw.Padding(
              padding: const pw.EdgeInsets.only(left: 9, bottom: 4),
              child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(margin: const pw.EdgeInsets.only(top: 5),
                      width: 3, height: 3, color: navy),
                  pw.SizedBox(width: 8),
                  pw.Expanded(child: pw.Text(clean(detail),
                    style: pw.TextStyle(font: regular, fontSize: 10.4,
                      lineSpacing: 3.2))),
                ]),
            )),
            pw.SizedBox(height: 8),
          ],
          ...experienceLines.skip(1).map((line) => experienceEntry(line)),
          heading('Compétences clés'),
          pw.Wrap(spacing: 6, runSpacing: 6,
            children: tailoredSkills.map((skill) => pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: pw.BoxDecoration(color: PdfColor.fromHex('EDF3F9'),
                  borderRadius: pw.BorderRadius.circular(4)),
              child: pw.Text(clean(skill), style: pw.TextStyle(
                  font: regular, fontSize: 9.7, color: navy)),
            )).toList()),
          heading('Formation et certifications'),
          ...candidateEducation.text.trim().split('\n')
              .where((line) => line.trim().isNotEmpty)
              .map((line) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Text(clean(line.trim()), style: pw.TextStyle(
                    font: regular, fontSize: 10.1, lineSpacing: 3)))),
        ],
      ));
      final lm = pw.Document();
      lm.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(50, 47, 50, 47),
        build: (_) => [
          identity(),
          pw.SizedBox(height: 33),
          ...letter.split(RegExp(r'\n\s*\n'))
            .where((paragraph) => paragraph.trim().isNotEmpty)
            .map((paragraph) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 15),
              child: pw.Text(clean(paragraph.trim()),
                style: pw.TextStyle(font: regular,
                  fontSize: 10.5, lineSpacing: 5)))),
        ],
      ));
      final safe = job.title.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final cvBytes = await cv.save();
      final letterBytes = await lm.save();
      if (!mounted) return;
      final isCv = action == 'cv';
      final fileName = isCv ? 'CV_$safe.pdf' : 'Lettre_$safe.pdf';
      final bytes = Uint8List.fromList(isCv ? cvBytes : letterBytes);
      if (kIsWeb) {
        browser_download.downloadPdf(bytes, fileName);
        if (mounted) showMessage('Téléchargement demandé : $fileName. Vérifie Téléchargements.');
      } else {
        await Share.shareXFiles(
          [XFile.fromData(bytes, name: fileName, mimeType: 'application/pdf')],
          subject: 'Candidature — ${job.title}',
        );
        if (mounted) showMessage('Fichier préparé pour partage : $fileName');
      }
    } catch (e) {
      if (mounted) showMessage('Création ou téléchargement du PDF impossible : $e');
    }
  }

  Widget metric(String label, int count, IconData icon, Color tint) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: tint), const SizedBox(height: 10),
        Text('$count', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF173B6D))),
        Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
      ]),
    ),
  );

  int countCategory(String category) =>
      jobs.where((j) => radarCategory(j.status) == category).length;

  // Une date d'importation n'est pas une date de candidature.
  int? daysSinceApplication(JobReview job) {
    final sent = DateTime.tryParse(job.applicationSentAt);
    if (sent == null) return null;
    final today = DateTime.now();
    final days = DateTime(today.year, today.month, today.day)
        .difference(DateTime(sent.year, sent.month, sent.day)).inDays;
    return days >= 0 ? days : null;
  }

  bool hasFollowUpSuggestion(JobReview job) {
    if (job.followUpDismissed || radarCategory(job.status) != 'En attente de réponse') return false;
    if (job.nextFollowUpAt.isNotEmpty) return false;
    final days = daysSinceApplication(job);
    if (days == null || days < 7) return false;
    final last = DateTime.tryParse(job.lastContactAt);
    if (last != null && DateTime.now().difference(last).inDays < 7) return false;
    return true;
  }

  bool isInFollowUps(JobReview job) =>
      needsFollowUp(job) || hasFollowUpSuggestion(job);

  String followUpHint(JobReview job) {
    final days = daysSinceApplication(job) ?? 0;
    if (days >= 21) return 'J+$days · Faire un dernier point';
    if (days >= 14) return 'J+$days · Relance conseillée';
    return 'J+$days · Relance possible';
  }

  bool needsFollowUp(JobReview job) {
    if (job.followUpDismissed) return false;
    final category = radarCategory(job.status);
    if (category != 'En attente de réponse' &&
        category != 'Attente réponse entretien') { return false; }
    // Ne jamais utiliser la date de création/import comme date de relance.
    // La date est explicitement fixée par l'utilisateur.
    final due = DateTime.tryParse(job.nextFollowUpAt);
    if (due == null) return false;
    final today = DateTime.now();
    return !DateTime(today.year, today.month, today.day).isBefore(
      DateTime(due.year, due.month, due.day));
  }

  Future<void> editFollowUp(JobReview job) async {
    final intermediary = TextEditingController(text: job.intermediary);
    final lastContact = TextEditingController(text: job.lastContactAt);
    final nextDate = TextEditingController(text: job.nextFollowUpAt);
    final sentDate = TextEditingController(text: job.applicationSentAt);
    final result = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Suivi et relance'),
      content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: intermediary, decoration: const InputDecoration(
            labelText: 'Cabinet / intermédiaire (facultatif)')),
          const SizedBox(height: 12),
          TextField(controller: sentDate, readOnly: true,
            decoration: InputDecoration(labelText: 'Date réelle de candidature',
              hintText: 'À renseigner pour les suggestions',
              suffixIcon: IconButton(tooltip: 'Effacer la date',
                onPressed: () => sentDate.clear(), icon: const Icon(Icons.clear))),
            onTap: () async {
              final picked = await showDatePicker(context: ctx,
                initialDate: DateTime.tryParse(sentDate.text) ?? DateTime.now(),
                firstDate: DateTime(2020), lastDate: DateTime(2100));
              if (picked != null) sentDate.text = picked.toIso8601String().substring(0, 10);
            }),
          const SizedBox(height: 12),
          TextField(controller: lastContact, readOnly: true,
            decoration: const InputDecoration(labelText: 'Dernier échange',
              hintText: 'Aucune date renseignée'),
            onTap: () async {
              final picked = await showDatePicker(context: ctx,
                initialDate: DateTime.tryParse(lastContact.text) ?? DateTime.now(),
                firstDate: DateTime(2020), lastDate: DateTime(2100));
              if (picked != null) lastContact.text = picked.toIso8601String().substring(0, 10);
            }),
          const SizedBox(height: 12),
          TextField(controller: nextDate, readOnly: true,
            decoration: InputDecoration(labelText: 'Prochaine relance (facultatif)',
              suffixIcon: IconButton(tooltip: 'Effacer la relance',
                onPressed: () => nextDate.clear(), icon: const Icon(Icons.clear))),
            onTap: () async {
              final picked = await showDatePicker(context: ctx,
                initialDate: DateTime.tryParse(nextDate.text) ?? DateTime.now(),
                firstDate: DateTime(2020), lastDate: DateTime(2100));
              if (picked != null) nextDate.text = picked.toIso8601String().substring(0, 10);
            }),
          const SizedBox(height: 8),
          const Text('Aucune relance automatique sans date choisie.',
            style: TextStyle(fontSize: 12)),
        ],
      ))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
      ],
    ));
    if (result == true && mounted) {
      setState(() {
        job.intermediary = intermediary.text.trim();
        job.lastContactAt = lastContact.text;
        job.nextFollowUpAt = nextDate.text;
        job.applicationSentAt = sentDate.text;
      });
      await saveAll();
    }
    intermediary.dispose(); lastContact.dispose(); nextDate.dispose(); sentDate.dispose();
  }

  Future<void> dismissFollowUp(JobReview job) async {
    final confirmed = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retirer des relances ?'),
        content: Text('« ${job.title} » ne figurera plus dans « À relancer ». '
          'La candidature restera dans « Suivi » avec son statut, '
          'ses notes et ses dates. Tu pourras réactiver ses relances '
          'depuis sa fiche.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Retirer des relances')),
        ],
      ));
    if (confirmed != true || !mounted) return;
    setState(() => job.followUpDismissed = true);
    await saveAll();
  }

  void showCategory(String category) {
    setState(() {
      statusFilter = category;
      search.clear();
      tab = 3;
    });
  }

  Widget compactMetric(String title, int count, IconData icon, Color color,
      VoidCallback onTap) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(children: [
            Icon(icon, color: color, size: 21),
            const SizedBox(width: 8),
            Expanded(child: Text(title, maxLines: 2,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
            Text('$count', style: const TextStyle(fontSize: 23,
              fontWeight: FontWeight.bold, color: Color(0xFF173B6D))),
          ]),
        ),
      ),
    );
  }

  Widget dashboard() {
    final toApply = countCategory('À postuler');
    final waiting = countCategory('En attente de réponse');
    final interviewed = jobs.where((j) => j.hadInterview ||
        j.status == 'Entretien réalisé' || j.status == 'Entretien' ||
        j.status == 'Attente réponse entretien' ||
        j.status == 'En attente retour client').length;
    final postInterview = countCategory('Attente réponse entretien');
    final closed = countCategory('Refus / Clôture');
    // Les indicateurs se recoupent : compter les candidatures uniques.
    final total = jobs.length;
    final due = jobs.where(needsFollowUp).toList();
    final suggested = jobs.where(hasFollowUpSuggestion).toList()
      ..sort((a, b) => (daysSinceApplication(b) ?? 0)
          .compareTo(daysSinceApplication(a) ?? 0));
    final followUpCount = jobs.where(isInFollowUps).length;
    final toReview = jobs.where((j) =>
        radarCategory(j.status) == 'À postuler' && !j.excluded).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    Widget metricCell(String label, int count, IconData icon, Color color,
        VoidCallback onTap) => compactMetric(label, count, icon, color, onTap);

    Widget action(JobReview job, String subtitle, IconData icon) => Card(
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: const Color(0xFF173B6D)),
        title: Text(job.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text([
          if (job.company.isNotEmpty) job.company,
          subtitle,
        ].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showJobInTracking(job),
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
      children: [
        const Text('Mon tableau de bord', style: TextStyle(
          fontSize: 20, fontWeight: FontWeight.bold,
          color: Color(0xFF173B6D))),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF173B6D),
            borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            const Expanded(child: Text('Total candidatures',
              style: TextStyle(color: Colors.white, fontSize: 16,
                fontWeight: FontWeight.w600))),
            Text('$total', style: const TextStyle(
              color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold)),
          ]),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: metricCell('À postuler', toApply, Icons.work_outline,
            const Color(0xFF2563EB), () => showCategory('À postuler'))),
          const SizedBox(width: 8),
          Expanded(child: metricCell('En attente', waiting, Icons.schedule,
            const Color(0xFFB87917), () => showCategory('En attente de réponse'))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: metricCell('Entretien réalisé', interviewed,
            Icons.people_outline, const Color(0xFF0D9488),
            () => showCategory('Entretien réalisé'))),
          const SizedBox(width: 8),
          Expanded(child: metricCell('Retour entretien', postInterview,
            Icons.event_available, const Color(0xFF7C3AED),
            () => showCategory('Attente réponse entretien'))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: metricCell('Refus / Clôture', closed,
            Icons.archive_outlined, const Color(0xFF64748B),
            () => showCategory('Refus / Clôture'))),
          const SizedBox(width: 8),
          Expanded(child: metricCell('À relancer', followUpCount,
            Icons.notifications_outlined, const Color(0xFFCE6D32),
            () => showCategory('À relancer'))),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          const Expanded(child: Text('Mes prochaines actions',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold,
              color: Color(0xFF173B6D)))),
          TextButton(onPressed: () => showCategory('Toutes'),
            child: const Text('Tout voir')),
        ]),
        if (due.isNotEmpty) ...[
          const Padding(padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('Relances programmées',
              style: TextStyle(fontWeight: FontWeight.w600))),
          ...due.take(3).map((j) => action(j, 'Date de relance atteinte',
            Icons.notifications_active_outlined)),
        ],
        if (suggested.isNotEmpty) ...[
          const Padding(padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('Suggestions de relance',
              style: TextStyle(fontWeight: FontWeight.w600))),
          ...suggested.take(3).map((j) => action(j,
            followUpHint(j), Icons.tips_and_updates_outlined)),
        ],
        if (toReview.isNotEmpty) ...[
          const Padding(padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('Offres à étudier',
              style: TextStyle(fontWeight: FontWeight.w600))),
          ...toReview.take(2).map((j) => action(j,
            'À examiner', Icons.work_outline)),
        ],
        if (due.isEmpty && suggested.isEmpty && toReview.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Aucune action prioritaire pour le moment. '
              'Les suggestions apparaissent lorsque la date réelle '
              'de candidature est renseignée dans Suivi / relance.')),
        const SizedBox(height: 10),
        const Text('Les relances sont uniquement suggérées : '
          'aucun message n’est envoyé automatiquement.',
          style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
      ],
    );
  }

  void showJobInTracking(JobReview job) {
    setState(() {
      statusFilter = 'Toutes';
      search.text = job.title;
      tab = 3;
    });
  }

  Future<void> changeStatus(JobReview job, String newStatus) async {
    if (newStatus == 'Candidature envoyée' && job.status != newStatus) {
      final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Envoi réellement effectué ?'),
        content: const Text('Le partage de PDF ne prouve pas que la candidature a été envoyée. Confirmez uniquement après l’envoi réel.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Oui, candidature envoyée'))],
      ));
      if (confirmed != true || !mounted) return;
    }
    if (!mounted) return;
    setState(() {
      if (job.status != newStatus) {
        final date = DateTime.now().toLocal().toIso8601String().substring(0, 10);
        job.notes = '${readableNotes(job.notes)}${job.notes.isEmpty ? '' : '\n'}$date : statut → $newStatus';
        if (newStatus == 'Entretien réalisé' || newStatus == 'Entretien' ||
            newStatus == 'Attente réponse entretien' ||
            newStatus == 'En attente retour client') {
          job.hadInterview = true;
        }
        job.status = newStatus;
        if (newStatus == 'Candidature envoyée' && job.applicationSentAt.isEmpty) {
          job.applicationSentAt = date;
        }
      }
    });
    await saveAll();
  }

  Widget profile() => ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Mon profil', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        const Text('Profil de départ personnalisable : support informatique, management et relation client.'),
        const SizedBox(height: 18),
        TextField(controller: distance, keyboardType: TextInputType.number, onChanged: (_) => saveAll(),
            decoration: const InputDecoration(labelText: 'Distance maximale (km)', border: OutlineInputBorder())),
        const SizedBox(height: 14),
        SwitchListTile(title: const Text('Exclure les déplacements fréquents'), value: excludeTravel,
            onChanged: (v) => updatePreference(() => excludeTravel = v)),
        SwitchListTile(title: const Text('Exclure les postes techniques infra/réseaux'), value: excludeTechnical,
            onChanged: (v) => updatePreference(() => excludeTechnical = v)),
        SwitchListTile(title: const Text('Exclure les établissements hospitaliers'), value: excludeHospital,
            onChanged: (v) => updatePreference(() => excludeHospital = v)),
        SwitchListTile(title: const Text('Exclure le développement logiciel'), value: excludeDevelopment,
            onChanged: (v) => updatePreference(() => excludeDevelopment = v)),
        const SizedBox(height: 12),
        const Divider(height: 32),
        const Text('Mon CV de référence', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const Text('Renseigne uniquement des informations exactes. Elles serviront à créer les dossiers PDF.'),
        const SizedBox(height: 12),
        const Text('Renseigne ton profil ici ou restaure une sauvegarde JSON personnelle. Aucune coordonnée n’est préchargée dans l’application.', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 12),
        ...[('Nom complet', candidateName), ('Email, téléphone et ville', candidateContact), ('Titre professionnel', candidateHeadline), ('Expériences (une ligne par fait vérifié)', candidateExperience), ('Compétences', candidateSkills), ('Formation et diplômes', candidateEducation)].map((entry) => Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(controller: entry.$2, minLines: 1, maxLines: entry.$2 == candidateExperience ? 6 : 3, onChanged: (_) => saveAll(), decoration: InputDecoration(labelText: entry.$1, border: const OutlineInputBorder())))),
        const Text('Les critères sont enregistrés localement sur cet appareil.',
            style: TextStyle(fontSize: 12)),
      ]);

  Widget analyzePage() => ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Analyser une annonce', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Colle le texte de l’offre. Extraction indicative : elle reconnaît les champs libellés Poste, Entreprise et les liens. Vérifie les résultats.'),
        const SizedBox(height: 18),
        TextField(controller: title, decoration: const InputDecoration(
            labelText: 'Intitulé du poste', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: company, decoration: const InputDecoration(
            labelText: 'Entreprise (facultatif)', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: link, keyboardType: TextInputType.url, decoration: const InputDecoration(
            labelText: 'Lien de l’offre (facultatif)', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: description, maxLines: 8,
            decoration: const InputDecoration(labelText: 'Texte de l’annonce',
                alignLabelWithHint: true, border: OutlineInputBorder())),
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: extractOfferFields, icon: const Icon(Icons.auto_fix_high),
            label: const Text('Extraire les informations du texte')),
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: analyze, icon: const Icon(Icons.manage_search),
            label: const Text('Analyser cette offre')),
        if (last != null) ...[
          const SizedBox(height: 20),
          Card(key: _analysisResultKey, child: Padding(padding: const EdgeInsets.all(16), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(last!.title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('${last!.score}/100 · ${last!.excluded ? 'Critère éliminatoire détecté' : 'À examiner'}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                ...last!.reasons.map((r) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(r))),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(onPressed: () {
                  final duplicate = jobs.any((j) => j.title.toLowerCase() == last!.title.toLowerCase() &&
                    j.company.toLowerCase() == last!.company.toLowerCase());
                  if (duplicate) { showMessage('Cette offre existe déjà dans le suivi.'); return; }
                  setState(() { last!.status = 'À postuler'; jobs.add(last!); last = null; tab = 3; });
                  saveAll();
                }, icon: const Icon(Icons.bookmark_add_outlined), label: const Text('Enregistrer l’offre')),
              ]))),
        ],
      ]);

  Widget tracking() {
    final visible = jobs.where((j) => (statusFilter == 'Toutes' ||
        (statusFilter == 'À relancer' && isInFollowUps(j)) ||
        (statusFilter != 'À relancer' && radarCategory(j.status) == statusFilter)) &&
        ('${j.title} ${j.company} ${j.notes}'.toLowerCase().contains(search.text.toLowerCase()))).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return ListView(padding: const EdgeInsets.all(20), children: [
      const Text('Mes candidatures', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: importRadarOffers,
        icon: const Icon(Icons.file_upload_outlined),
        label: const Text('Importer les nouvelles annonces (JSON)')),
      const SizedBox(height: 6),
      const Text('Importe un fichier d’annonces créé dans ChatGPT. Les doublons sont ignorés et tes candidatures existantes sont conservées.',
        style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
      const SizedBox(height: 5),
      Text('${jobs.length} fiches enregistrées · ${jobs.where((j) => radarCategory(j.status) != 'À postuler').length} candidatures'),
      const SizedBox(height: 14),
      TextField(controller: search, onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Rechercher dans mes offres', border: OutlineInputBorder())),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(initialValue: statusFilter,
        decoration: const InputDecoration(labelText: 'Filtrer par statut', border: OutlineInputBorder()),
        items: ['Toutes', 'À postuler', 'En attente de réponse', 'Entretien réalisé', 'Attente réponse entretien', 'Refus / Clôture', 'À relancer']
          .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
        onChanged: (v) => setState(() => statusFilter = v ?? 'Toutes')),
      if (statusFilter == 'À relancer')
        const Padding(padding: EdgeInsets.symmetric(vertical: 10),
          child: Text('Pour retirer une annonce de cette liste, ouvre '
            'sa fiche puis choisis « Retirer des relances ». '
            'La candidature ne sera pas supprimée.',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)))),
      const SizedBox(height: 12),
      if (visible.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Aucune offre correspondant à ce filtre.')),
      ...visible.map((job) => Card(child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        title: Text(job.title, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        subtitle: Text([
          if (job.company.isNotEmpty) job.company,
          radarCategory(job.status),
          if (job.hadInterview) 'Entretien effectué',
          if (job.intermediary.isNotEmpty) 'Via ${job.intermediary}',
          if (job.nextFollowUpAt.isNotEmpty) 'Relance : ${job.nextFollowUpAt}',
        ].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12)),
        children: [
          Align(alignment: Alignment.centerLeft, child: Text(
            job.score == 0 && job.reasons.isEmpty ? 'Score : non évalué'
              : 'Score indicatif : ${job.score}/100${job.excluded ? ' · Critère éliminatoire détecté' : ''}',
            style: const TextStyle(fontSize: 12))),
          if (job.url.isNotEmpty) Align(alignment: Alignment.centerLeft,
            child: SelectableText(job.url, style: const TextStyle(fontSize: 12))),
          if (job.notes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8),
            child: Align(alignment: Alignment.centerLeft, child: Text(readableNotes(job.notes)))),
          const SizedBox(height: 6),
          DropdownButton<String>(value: radarStatuses.contains(job.status) ? job.status : 'Refus / Clôture',
            isExpanded: true,
            items: radarStatuses.map((v) => DropdownMenuItem(value: v,
              child: Text(v, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) { if (v != null) changeStatus(job, v); }),
          Wrap(spacing: 4, runSpacing: 0, children: [
            TextButton.icon(onPressed: () => editFollowUp(job),
              icon: const Icon(Icons.event_note), label: const Text('Suivi / relance')),
            if (job.followUpDismissed)
              TextButton.icon(onPressed: () async {
                setState(() => job.followUpDismissed = false);
                await saveAll();
              }, icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Réactiver les relances')),
            if (statusFilter == 'À relancer' && isInFollowUps(job))
              TextButton.icon(onPressed: () => dismissFollowUp(job),
                icon: const Icon(Icons.notifications_off_outlined),
                label: const Text('Retirer des relances')),
            TextButton.icon(onPressed: () => editNotes(job),
              icon: const Icon(Icons.edit_note), label: const Text('Notes')),
            TextButton.icon(onPressed: () => prepareApplication(job),
              icon: const Icon(Icons.description_outlined), label: const Text('CV + lettre')),
            TextButton.icon(onPressed: () => sendToChatGpt(job),
              icon: const Icon(Icons.share_outlined), label: const Text('ChatGPT')),
            TextButton.icon(onPressed: () => deleteJob(job),
              icon: const Icon(Icons.delete_outline), label: const Text('Supprimer')),
          ]),
        ],
      ))),
      const Divider(height: 30),
      const Text('Mes sauvegardes OneDrive', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('Gère tes sauvegardes depuis l’iPhone. Le fichier JSON contient le profil, les candidatures, les notes et les relances.'),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: exportBackup, icon: const Icon(Icons.ios_share),
        label: const Text('Exporter ma sauvegarde')),
      const SizedBox(height: 8),
      OutlinedButton.icon(onPressed: importBackup, icon: const Icon(Icons.restore),
        label: const Text('Restaurer depuis un fichier JSON')),
      const SizedBox(height: 8),
      TextButton.icon(onPressed: showOneDriveHelp, icon: const Icon(Icons.help_outline),
        label: const Text('Comment utiliser OneDrive sur iPhone ?')),
      const SizedBox(height: 8),
      const Text('OneDrive conserve une copie du fichier uniquement après ton partage ou ton enregistrement. '
        'Il n’y a pas de synchronisation automatique. Avant toute restauration, exporte la version actuelle : '
        'la restauration remplace les candidatures et le profil.',
        style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Mon Radar Emploi')),
        body: IndexedStack(index: tab, children: [dashboard(), profile(), analyzePage(), tracking()]),
        bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (v) => setState(() => tab = v),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Accueil'),
            NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profil'),
            NavigationDestination(icon: Icon(Icons.radar), label: 'Analyse'),
            NavigationDestination(icon: Icon(Icons.work_outline), label: 'Suivi'),
          ]),
      );
}
