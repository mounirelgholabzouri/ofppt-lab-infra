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
        ['section' => 1, 'tp' => 'CC101-TP1', 'name' => '🚀 Lancer le TP1 — Docker'],
        ['section' => 2, 'tp' => 'CC101-TP2', 'name' => '🚀 Lancer le TP2 — Docker Compose'],
    ],
    'CC302' => [
        ['section' => 1, 'tp' => 'CC302-TP1', 'name' => '🚀 Lancer le TP1 — Kubernetes Pods'],
        ['section' => 2, 'tp' => 'CC302-TP2', 'name' => '🚀 Lancer le TP2 — Terraform IaC'],
    ],
    'NET101' => [
        ['section' => 1, 'tp' => 'NET101-TP1', 'name' => '🚀 Lancer le TP1 — Wireshark'],
        ['section' => 2, 'tp' => 'NET101-TP2', 'name' => '🚀 Lancer le TP2 — OSPF Routage'],
    ],
    'NET201' => [
        ['section' => 1, 'tp' => 'NET201-TP1', 'name' => '🚀 Lancer le TP1 — OpenVPN'],
    ],
    'NET301' => [
        ['section' => 1, 'tp' => 'NET301-TP1', 'name' => '🚀 Lancer le TP1 — WireGuard'],
    ],
    'CYB101' => [
        ['section' => 1, 'tp' => 'CYB101-TP1', 'name' => '🚀 Lancer le TP1 — Nmap Reconnaissance'],
        ['section' => 2, 'tp' => 'CYB101-TP2', 'name' => '🚀 Lancer le TP2 — Metasploit'],
    ],
    'CYB201' => [
        ['section' => 1, 'tp' => 'CYB201-TP1', 'name' => '🚀 Lancer le TP1 — Injection SQL DVWA'],
    ],
    'CYB301' => [
        ['section' => 1, 'tp' => 'CYB301-TP1', 'name' => '🚀 Lancer le TP1 — Forensique Volatility'],
    ],
];

$BASE_URL = MOODLE_WWWROOT . '/local/devtestlab/launch_tp.php';

// ── Traitement ────────────────────────────────────────────────────────────────
echo "\n=== OFPPT — Création des activités TP dans Moodle ===\n\n";
$created = 0; $skipped = 0; $errors = 0;

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
        $tpCode    = $tp['tp'];
        $sectionN  = $tp['section'];
        $actName   = $tp['name'];
        $launchUrl = $BASE_URL . '?tp=' . urlencode($tpCode) . '&course=' . $course->id;

        // Vérifier si l'activité existe déjà
        $existing = $DB->get_record_sql(
            "SELECT cm.id FROM {course_modules} cm
             JOIN {url} u ON u.id = cm.instance
             WHERE cm.course = ? AND u.externalurl LIKE ?",
            [$course->id, "%tp=$tpCode%"]
        );

        if ($existing) {
            echo "    [SKIP] Activité '$actName' existe déjà (cm: {$existing->id})\n";
            $skipped++;
            continue;
        }

        // Récupérer ou créer la section
        $section = $DB->get_record('course_sections', [
            'course'  => $course->id,
            'section' => $sectionN,
        ]);
        if (!$section) {
            $section = course_create_section($course->id, $sectionN);
        }

        // Créer le module URL
        try {
            $moduleinfo              = new stdClass();
            $moduleinfo->course      = $course->id;
            $moduleinfo->section     = $sectionN;
            $moduleinfo->modulename  = 'url';
            $moduleinfo->name        = $actName;
            $moduleinfo->externalurl = $launchUrl;
            $moduleinfo->display     = RESOURCELIB_DISPLAY_NEW; // Ouvrir dans un nouvel onglet
            $moduleinfo->visible     = 1;
            $moduleinfo->intro       = "<p>Cliquez pour démarrer votre VM de TP <strong>$tpCode</strong> sur Azure DevTest Labs.</p>"
                                     . "<p><em>⏱️ La VM s'arrêtera automatiquement après 4 heures.</em></p>";
            $moduleinfo->introformat = FORMAT_HTML;
            $moduleinfo->showdescription = 1;

            // Paramètres optionnels pour la popup
            $moduleinfo->popupwidth  = 1280;
            $moduleinfo->popupheight = 900;

            $result = add_moduleinfo($moduleinfo, $course);
            echo "    [OK] Activité '$actName' créée (cm: {$result->coursemodule}, section: $sectionN)\n";
            $created++;
        } catch (Exception $e) {
            echo "    [ERREUR] '$actName' : " . $e->getMessage() . "\n";
            $errors++;
        }
    }
    echo "\n";
}

// ── Résumé ────────────────────────────────────────────────────────────────────
echo "════════════════════════════════════════\n";
echo "  Activités créées  : $created\n";
echo "  Ignorées (exist.) : $skipped\n";
echo "  Erreurs           : $errors\n";
echo "════════════════════════════════════════\n";
echo "\n  ✅ Les stagiaires voient maintenant le bouton '🚀 Lancer le TP'\n";
echo "     dans chaque section de TP de leurs cours Moodle.\n\n";
echo "  URL modèle : $BASE_URL?tp=CC101-TP1&course=<id>\n\n";
