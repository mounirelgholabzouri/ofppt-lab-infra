<?php
// =============================================================================
// setup_moodle_activities.php — Création des activités "Lancer le TP" dans Moodle
// =============================================================================
// Exécuter une seule fois en CLI sur le serveur Moodle :
//   sudo -u www-data php setup_moodle_activities.php
//
// Ce script crée une activité "URL" dans chaque section de cours Moodle
// correspondant à un TP, pointant vers launch_tp.php avec les bons paramètres.
// =============================================================================

define('CLI_SCRIPT', true);
define('MOODLE_INTERNAL', true);

// Adapter ce chemin à votre installation Moodle
$moodleRoot = '/var/www/html/moodle';
if (!file_exists("$moodleRoot/config.php")) {
    die("ERREUR : Moodle introuvable dans $moodleRoot\n");
}

require_once "$moodleRoot/config.php";
require_once "$moodleRoot/lib/clilib.php";
require_once "$moodleRoot/lib/moodlelib.php";
require_once "$moodleRoot/lib/modinfolib.php";
require_once "$moodleRoot/course/lib.php";
require_once __DIR__ . '/config.php';

// ── Configuration des activités à créer ──────────────────────────────────────
// Format : 'shortname_cours' => [ [ 'section' => N, 'tp' => 'CODE-TP' ], ... ]
$ACTIVITIES = [
    'CC101' => [
        ['section' => 1, 'tp' => 'CC101-TP1', 'name' => 'Lancer le TP1 - Docker'],
        ['section' => 2, 'tp' => 'CC101-TP2', 'name' => 'Lancer le TP2 - Docker Compose'],
    ],
    'CC302' => [
        ['section' => 1, 'tp' => 'CC302-TP1', 'name' => 'Lancer le TP1 - Kubernetes Pods'],
        ['section' => 2, 'tp' => 'CC302-TP2', 'name' => 'Lancer le TP2 - Terraform IaC'],
    ],
    'NET101' => [
        ['section' => 1, 'tp' => 'NET101-TP1', 'name' => 'Lancer le TP1 - Wireshark'],
        ['section' => 2, 'tp' => 'NET101-TP2', 'name' => 'Lancer le TP2 - OSPF Routage'],
    ],
    'NET201' => [
        ['section' => 1, 'tp' => 'NET201-TP1', 'name' => 'Lancer le TP1 - OpenVPN'],
    ],
    'NET301' => [
        ['section' => 1, 'tp' => 'NET301-TP1', 'name' => 'Lancer le TP1 - WireGuard'],
    ],
    'CYB101' => [
        ['section' => 1, 'tp' => 'CYB101-TP1', 'name' => 'Lancer le TP1 - Nmap Reconnaissance'],
        ['section' => 2, 'tp' => 'CYB101-TP2', 'name' => 'Lancer le TP2 - Metasploit'],
    ],
    'CYB201' => [
        ['section' => 1, 'tp' => 'CYB201-TP1', 'name' => 'Lancer le TP1 - Injection SQL DVWA'],
    ],
    'CYB301' => [
        ['section' => 1, 'tp' => 'CYB301-TP1', 'name' => 'Lancer le TP1 - Forensique Volatility'],
    ],
];

$BASE_URL = 'http://40.115.121.107/moodle/local/devtestlab/launch_tp.php';

// ── Traitement ────────────────────────────────────────────────────────────────
echo "\n=== OFPPT — Creation des activites TP dans Moodle ===\n\n";
$created = 0; $skipped = 0; $errors = 0;

// Récupérer l'ID du module URL
$moduleRecord = $DB->get_record('modules', ['name' => 'url'], '*', MUST_EXIST);
$moduleId = $moduleRecord->id;

foreach ($ACTIVITIES as $courseShortname => $tps) {
    // Récupérer le cours Moodle par shortname
    $course = $DB->get_record('course', ['shortname' => $courseShortname]);
    if (!$course) {
        echo "  [SKIP] Cours '$courseShortname' introuvable dans Moodle\n";
        $skipped++;
        continue;
    }
    echo "  Cours : $courseShortname (ID: {$course->id}) — {$course->fullname}\n";

    foreach ($tps as $tp) {
        $tpCode   = $tp['tp'];
        $sectionN = $tp['section'];
        $actName  = $tp['name'];
        $launchUrl = $BASE_URL . '?tp=' . urlencode($tpCode) . '&course=' . $course->id;

        // Vérifier si l'activité existe déjà
        $existing = $DB->get_record_sql(
            "SELECT cm.id FROM {course_modules} cm
             JOIN {url} u ON u.id = cm.instance
             WHERE cm.course = ? AND u.externalurl LIKE ?",
            [$course->id, "%tp=$tpCode%"]
        );

        if ($existing) {
            echo "    [SKIP] Activite '$actName' existe deja (cm: {$existing->id})\n";
            $skipped++;
            continue;
        }

        try {
            // 1. Récupérer ou créer la section
            $section = $DB->get_record('course_sections', [
                'course'  => $course->id,
                'section' => $sectionN,
            ]);
            if (!$section) {
                $newSection = new stdClass();
                $newSection->course  = $course->id;
                $newSection->section = $sectionN;
                $newSection->name    = '';
                $newSection->summary = '';
                $newSection->summaryformat = FORMAT_HTML;
                $newSection->sequence = '';
                $newSection->visible  = 1;
                $newSection->timemodified = time();
                $sectionId = $DB->insert_record('course_sections', $newSection);
                $section = $DB->get_record('course_sections', ['id' => $sectionId]);
            }

            // 2. Insérer l'enregistrement URL
            $urlRecord = new stdClass();
            $urlRecord->course       = $course->id;
            $urlRecord->name         = $actName;
            $urlRecord->intro        = '<p>Cliquez pour demarrer votre VM de TP <strong>' . $tpCode . '</strong> sur Azure DevTest Labs.</p>'
                                     . '<p><em>La VM s\'arretera automatiquement apres 4 heures.</em></p>';
            $urlRecord->introformat  = FORMAT_HTML;
            $urlRecord->externalurl  = $launchUrl;
            $urlRecord->display      = 0; // RESOURCELIB_DISPLAY_AUTO (ouvre dans nouvelle page)
            $urlRecord->displayoptions = serialize(['printintro' => 1]);
            $urlRecord->parameters   = '';
            $urlRecord->timemodified = time();
            $urlId = $DB->insert_record('url', $urlRecord);

            // 3. Créer le course_module
            $cm = new stdClass();
            $cm->course    = $course->id;
            $cm->module    = $moduleId;
            $cm->instance  = $urlId;
            $cm->section   = $section->id;
            $cm->added     = time();
            $cm->visible   = 1;
            $cm->visibleoncoursepage = 1;
            $cm->visibleold = 1;
            $cm->showdescription = 1;
            $cm->groupmode = 0;
            $cm->groupingid = 0;
            $cm->completion = 0;
            $cm->completionview = 0;
            $cm->completionexpected = 0;
            $cm->completionpassgrade = 0;
            $cm->deletioninprogress = 0;
            $cmId = $DB->insert_record('course_modules', $cm);

            // 4. Ajouter le cm à la séquence de la section
            $sequence = $section->sequence ? $section->sequence . ',' . $cmId : (string)$cmId;
            $DB->set_field('course_sections', 'sequence', $sequence, ['id' => $section->id]);

            // 5. Invalider le cache du cours
            rebuild_course_cache($course->id, true);

            echo "    [OK] Activite '$actName' creee (cm: $cmId, section: $sectionN)\n";
            $created++;
        } catch (Exception $e) {
            echo "    [ERREUR] '$actName' : " . $e->getMessage() . "\n";
            $errors++;
        }
    }
    echo "\n";
}

// ── Résumé ────────────────────────────────────────────────────────────────────
echo "========================================\n";
echo "  Activites creees  : $created\n";
echo "  Ignorees (exist.) : $skipped\n";
echo "  Erreurs           : $errors\n";
echo "========================================\n";
echo "\n  Les stagiaires voient maintenant le bouton 'Lancer le TP'\n";
echo "     dans chaque section de TP de leurs cours Moodle.\n\n";
echo "  URL modele : $BASE_URL?tp=CC101-TP1&course=<id>\n\n";
