<?php
// =============================================================================
// launch_tp.php — Lanceur de VM de TP depuis une page Moodle
// =============================================================================
// Appelé via une activité "URL" dans Moodle :
//   https://moodle.ofppt-academy.ma/local/devtestlab/launch_tp.php?tp=CC101-TP1
//
// Flux :
//   1. Vérification de la session Moodle (l'étudiant doit être connecté)
//   2. Génération du nom de VM unique (stagiaire + TP)
//   3. Création de la VM dans Azure DevTest Labs si elle n'existe pas
//   4. Affichage d'une page d'attente avec polling AJAX
//   5. Redirection vers ttyd (SSH web) une fois la VM prête
// =============================================================================

declare(strict_types=1);
error_reporting(E_ALL);
ini_set('display_errors', '0');

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/azure_dtl_api.php';

// ── Bootstrap Moodle ──────────────────────────────────────────────────────────
// Initialise la session Moodle pour accéder à $USER et $COURSE
define('MOODLE_INTERNAL', true);
if (file_exists(MOODLE_ROOT . '/config.php')) {
    require_once MOODLE_ROOT . '/config.php';
    require_once MOODLE_ROOT . '/lib/moodlelib.php';
    require_once MOODLE_ROOT . '/lib/weblib.php';
    require_login(); // Redirige vers la page de login si non connecté
    $moodleUsername = $USER->username;
    $moodleFullname = fullname($USER);
    $moodleEmail    = $USER->email;
    $isLoggedIn     = isloggedin() && !isguestuser();
} else {
    // Mode standalone (test sans Moodle)
    session_start();
    $moodleUsername = $_SESSION['username'] ?? 'test-user';
    $moodleFullname = $_SESSION['fullname'] ?? 'Stagiaire Test';
    $moodleEmail    = $_SESSION['email']    ?? 'test@ofppt.ma';
    $isLoggedIn     = true;
}

if (!$isLoggedIn) {
    http_response_code(403);
    die('Accès refusé. Veuillez vous connecter à Moodle.');
}

// ── Paramètres de la requête ──────────────────────────────────────────────────
$tpCode    = filter_input(INPUT_GET, 'tp',     FILTER_SANITIZE_SPECIAL_CHARS) ?? '';
$action    = filter_input(INPUT_GET, 'action', FILTER_SANITIZE_SPECIAL_CHARS) ?? 'launch';
$courseId  = filter_input(INPUT_GET, 'course', FILTER_SANITIZE_NUMBER_INT)    ?? 0;

// Validation du code TP
if (empty($tpCode) || !array_key_exists($tpCode, TP_CATALOG)) {
    http_response_code(400);
    die("Code TP invalide ou inconnu : " . htmlspecialchars($tpCode));
}

$tp     = TP_CATALOG[$tpCode];
$vmName = AzureDTLApi::buildVmName($moodleUsername, $tpCode);
$dtl    = new AzureDTLApi();

// ── Action : arrêter/supprimer la VM (bouton "Terminer le TP") ───────────────
if ($action === 'stop') {
    try {
        if ($dtl->vmExists($vmName)) {
            $dtl->deleteVm($vmName); // Éphémère : on supprime
        }
        dtl_log("VM '$vmName' supprimée par $moodleUsername");
    } catch (Exception $e) {
        dtl_log("Erreur suppression VM : " . $e->getMessage(), 'ERROR');
    }
    // Retour au cours Moodle
    $redirect = $courseId
        ? MOODLE_WWWROOT . "/course/view.php?id=$courseId"
        : MOODLE_WWWROOT;
    header("Location: $redirect");
    exit;
}

// ── Action : obtenir le statut (appelé en AJAX depuis status.php) ─────────────
if ($action === 'status') {
    require_once __DIR__ . '/status.php';
    exit;
}

// ── Lancement de la VM ────────────────────────────────────────────────────────
$error   = '';
$created = false;

try {
    if (!$dtl->vmExists($vmName)) {
        dtl_log("Nouvelle VM éphémère '$vmName' pour '$moodleUsername' (TP: $tpCode)");
        $dtl->createVm($vmName, $tpCode, $moodleUsername);
        $created = true;
    } else {
        // VM existe déjà → vérifier si arrêtée et la redémarrer
        $status = $dtl->getVmStatus($vmName);
        if ($status['powerState'] !== 'Running') {
            dtl_log("Redémarrage VM existante '$vmName'");
            $dtl->startVm($vmName);
        }
    }
} catch (Exception $e) {
    $error = $e->getMessage();
    dtl_log("Erreur lancement VM : $error", 'ERROR');
}

// ── Token signé pour le polling sécurisé ─────────────────────────────────────
$tokenPayload = base64_encode(json_encode([
    'vm'      => $vmName,
    'user'    => $moodleUsername,
    'tp'      => $tpCode,
    'expires' => time() + 3600,
]));
$tokenSig     = hash_hmac('sha256', $tokenPayload, TP_SECRET_KEY);
$pollToken    = $tokenPayload . '.' . $tokenSig;

// ── Couleurs par filière ──────────────────────────────────────────────────────
$filiereColors = [
    'cloud'  => ['bg' => '#0078D4', 'icon' => '☁️',  'label' => 'Cloud Computing'],
    'reseau' => ['bg' => '#107C10', 'icon' => '🌐', 'label' => 'Réseau & Infrastructure'],
    'cyber'  => ['bg' => '#C1272D', 'icon' => '🔐', 'label' => 'Cybersécurité'],
];
$filiereStyle = $filiereColors[$tp['filiere']] ?? ['bg' => '#009639', 'icon' => '💻', 'label' => 'Lab'];

// ── Rendu HTML ────────────────────────────────────────────────────────────────
$pageTitle  = htmlspecialchars("Démarrage TP — " . $tp['label']);
$tpLabel    = htmlspecialchars($tp['label']);
$tpCodeHtml = htmlspecialchars($tpCode);
$username   = htmlspecialchars($moodleFullname);
$statusUrl  = MOODLE_WWWROOT . "/local/devtestlab/status.php";
$stopUrl    = "?tp={$tpCodeHtml}&action=stop&course={$courseId}";
$ttydPort   = TTYD_PORT;

?><!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?= $pageTitle ?></title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: #f0f4f8;
            min-height: 100vh;
            display: flex;
            flex-direction: column;
        }

        /* ─ Header OFPPT ─ */
        .header {
            background: <?= $filiereStyle['bg'] ?>;
            color: white;
            padding: 16px 24px;
            display: flex;
            align-items: center;
            gap: 16px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.2);
        }
        .header-logo { font-size: 28px; }
        .header-info h1 { font-size: 18px; font-weight: 700; }
        .header-info p  { font-size: 13px; opacity: 0.85; }
        .header-badge {
            margin-left: auto;
            background: rgba(255,255,255,0.2);
            padding: 6px 14px;
            border-radius: 20px;
            font-size: 13px;
        }

        /* ─ Container principal ─ */
        .container {
            max-width: 860px;
            margin: 32px auto;
            padding: 0 16px;
            flex: 1;
        }

        /* ─ Card état ─ */
        .card {
            background: white;
            border-radius: 12px;
            box-shadow: 0 2px 16px rgba(0,0,0,0.08);
            overflow: hidden;
            margin-bottom: 20px;
        }
        .card-header {
            padding: 20px 24px;
            border-bottom: 1px solid #eef0f3;
            display: flex;
            align-items: center;
            gap: 12px;
        }
        .card-header h2 { font-size: 16px; font-weight: 600; color: #1a1a2e; }
        .card-body { padding: 24px; }

        /* ─ Statut VM ─ */
        .status-bar {
            display: flex;
            align-items: center;
            gap: 16px;
            padding: 20px;
            border-radius: 10px;
            margin-bottom: 20px;
            transition: background 0.3s;
        }
        .status-bar.booting  { background: #fff3cd; border: 1px solid #ffc107; }
        .status-bar.ready    { background: #d4edda; border: 1px solid #28a745; }
        .status-bar.error    { background: #f8d7da; border: 1px solid #dc3545; }

        .status-icon  { font-size: 36px; }
        .status-text  h3 { font-size: 16px; font-weight: 600; }
        .status-text  p  { font-size: 14px; color: #6c757d; margin-top: 4px; }

        /* ─ Spinner ─ */
        .spinner {
            width: 32px; height: 32px;
            border: 4px solid #dee2e6;
            border-top-color: <?= $filiereStyle['bg'] ?>;
            border-radius: 50%;
            animation: spin 1s linear infinite;
            flex-shrink: 0;
        }
        @keyframes spin { to { transform: rotate(360deg); } }

        /* ─ Progress bar ─ */
        .progress { background: #e9ecef; border-radius: 6px; height: 8px; overflow: hidden; margin: 12px 0; }
        .progress-bar {
            height: 100%;
            background: <?= $filiereStyle['bg'] ?>;
            border-radius: 6px;
            transition: width 1.5s ease;
            width: 5%;
        }
        .progress-label { font-size: 12px; color: #6c757d; text-align: right; }

        /* ─ Étapes ─ */
        .steps { display: flex; flex-direction: column; gap: 10px; margin: 16px 0; }
        .step {
            display: flex; align-items: center; gap: 12px;
            padding: 10px 14px;
            border-radius: 8px;
            background: #f8f9fa;
            font-size: 14px;
            transition: all 0.3s;
        }
        .step.done    { background: #d4edda; color: #155724; }
        .step.active  { background: #cce5ff; color: #004085; font-weight: 600; }
        .step.pending { color: #6c757d; }
        .step-icon { font-size: 18px; width: 24px; text-align: center; }

        /* ─ Infos VM ─ */
        .vm-info {
            background: #f8f9fa;
            border-radius: 8px;
            padding: 16px;
            font-family: 'Courier New', monospace;
            font-size: 13px;
        }
        .vm-info-row { display: flex; justify-content: space-between; padding: 4px 0; }
        .vm-info-label { color: #6c757d; }
        .vm-info-value { color: #1a1a2e; font-weight: 600; }

        /* ─ SSH Terminal iframe ─ */
        .terminal-wrapper {
            display: none;
            background: #1e1e2e;
            border-radius: 12px;
            overflow: hidden;
            box-shadow: 0 4px 24px rgba(0,0,0,0.3);
        }
        .terminal-toolbar {
            background: #2d2d44;
            padding: 10px 16px;
            display: flex;
            align-items: center;
            gap: 8px;
        }
        .terminal-toolbar .dot {
            width: 12px; height: 12px; border-radius: 50%;
        }
        .dot-red    { background: #ff5f56; }
        .dot-yellow { background: #ffbd2e; }
        .dot-green  { background: #27c93f; }
        .terminal-title {
            margin-left: 12px;
            color: #cdd6f4;
            font-size: 13px;
            font-family: monospace;
        }
        .terminal-iframe {
            width: 100%;
            height: 520px;
            border: none;
            background: #1e1e2e;
        }

        /* ─ Boutons ─ */
        .btn-row { display: flex; gap: 12px; margin-top: 20px; flex-wrap: wrap; }
        .btn {
            padding: 10px 20px;
            border-radius: 8px;
            font-size: 14px;
            font-weight: 600;
            cursor: pointer;
            border: none;
            transition: all 0.2s;
            text-decoration: none;
            display: inline-flex;
            align-items: center;
            gap: 8px;
        }
        .btn-primary {
            background: <?= $filiereStyle['bg'] ?>;
            color: white;
        }
        .btn-primary:hover { opacity: 0.88; transform: translateY(-1px); }
        .btn-danger  { background: #dc3545; color: white; }
        .btn-danger:hover  { opacity: 0.88; }
        .btn-secondary { background: #e9ecef; color: #495057; }
        .btn-secondary:hover { background: #dee2e6; }

        /* ─ Timer ─ */
        .timer-bar {
            background: white;
            border-radius: 10px;
            padding: 14px 20px;
            display: flex;
            align-items: center;
            justify-content: space-between;
            font-size: 14px;
            box-shadow: 0 1px 6px rgba(0,0,0,0.07);
        }
        .timer-value { font-size: 20px; font-weight: 700; font-family: monospace; color: <?= $filiereStyle['bg'] ?>; }
    </style>
</head>
<body>

<!-- ─ Header ─ -->
<div class="header">
    <div class="header-logo"><?= $filiereStyle['icon'] ?></div>
    <div class="header-info">
        <h1>OFPPT Academy — Lab TP</h1>
        <p><?= $filiereStyle['label'] ?> &nbsp;›&nbsp; <?= $tpLabel ?></p>
    </div>
    <div class="header-badge">👤 <?= $username ?></div>
</div>

<div class="container">

    <?php if ($error): ?>
    <!-- ─ Erreur ─ -->
    <div class="card">
        <div class="card-body">
            <div class="status-bar error">
                <div class="status-icon">❌</div>
                <div class="status-text">
                    <h3>Erreur lors du lancement du TP</h3>
                    <p><?= htmlspecialchars($error) ?></p>
                </div>
            </div>
            <div class="btn-row">
                <a href="?" class="btn btn-primary">🔄 Réessayer</a>
                <a href="<?= MOODLE_WWWROOT ?>/course/view.php?id=<?= $courseId ?>" class="btn btn-secondary">← Retour au cours</a>
            </div>
        </div>
    </div>
    <?php else: ?>

    <!-- ─ Carte état VM ─ -->
    <div class="card" id="status-card">
        <div class="card-header">
            <span style="font-size:20px"><?= $filiereStyle['icon'] ?></span>
            <h2>Votre environnement de TP — <?= $tpCodeHtml ?></h2>
        </div>
        <div class="card-body">

            <!-- Status bar -->
            <div class="status-bar booting" id="status-bar">
                <div class="spinner" id="spinner"></div>
                <div class="status-text">
                    <h3 id="status-title">Démarrage de votre VM en cours…</h3>
                    <p id="status-desc">
                        <?= $created ? 'Création de la VM depuis la formule ' . htmlspecialchars(DTL_FORMULAS[$tp['filiere']] ?? '') . '…' : 'Redémarrage de votre VM…' ?>
                    </p>
                </div>
            </div>

            <!-- Progress -->
            <div class="progress">
                <div class="progress-bar" id="progress-bar"></div>
            </div>
            <div class="progress-label" id="progress-label">Initialisation…</div>

            <!-- Étapes -->
            <div class="steps" id="steps">
                <div class="step done"    id="step-1"><span class="step-icon">✅</span> Authentification Azure confirmée</div>
                <div class="step <?= $created ? 'active' : 'done' ?>" id="step-2"><span class="step-icon"><?= $created ? '⚙️' : '✅' ?></span>
                    <?= $created ? 'Provisionnement de la VM…' : 'VM récupérée dans le lab' ?>
                </div>
                <div class="step pending" id="step-3"><span class="step-icon">🔌</span> Démarrage des services SSH</div>
                <div class="step pending" id="step-4"><span class="step-icon">🖥️</span> Ouverture du terminal SSH</div>
            </div>

            <!-- Infos VM -->
            <div class="vm-info" style="margin-top:16px">
                <div class="vm-info-row">
                    <span class="vm-info-label">VM :</span>
                    <span class="vm-info-value" id="info-vm"><?= htmlspecialchars($vmName) ?></span>
                </div>
                <div class="vm-info-row">
                    <span class="vm-info-label">Filière :</span>
                    <span class="vm-info-value"><?= $filiereStyle['label'] ?></span>
                </div>
                <div class="vm-info-row">
                    <span class="vm-info-label">IP :</span>
                    <span class="vm-info-value" id="info-ip">—</span>
                </div>
                <div class="vm-info-row">
                    <span class="vm-info-label">Durée max :</span>
                    <span class="vm-info-value">4 heures</span>
                </div>
            </div>

            <div class="btn-row">
                <a href="<?= $stopUrl ?>" class="btn btn-danger" onclick="return confirm('Terminer et supprimer votre VM de TP ?')">
                    ⏹ Terminer le TP
                </a>
                <a href="<?= MOODLE_WWWROOT ?>/course/view.php?id=<?= $courseId ?>" class="btn btn-secondary">
                    ← Retour au cours
                </a>
            </div>
        </div>
    </div>

    <!-- ─ Terminal SSH (affiché quand VM prête) ─ -->
    <div class="terminal-wrapper" id="terminal-wrapper">
        <div class="terminal-toolbar">
            <div class="dot dot-red"></div>
            <div class="dot dot-yellow"></div>
            <div class="dot dot-green"></div>
            <span class="terminal-title">SSH — <?= htmlspecialchars($vmName) ?> — <?= $tpLabel ?></span>
        </div>
        <iframe id="terminal-iframe" class="terminal-iframe" src="about:blank" title="Terminal SSH"></iframe>
    </div>

    <!-- ─ Timer durée restante ─ -->
    <div class="timer-bar" id="timer-bar" style="display:none">
        <span>⏱️ Temps restant avant arrêt automatique :</span>
        <span class="timer-value" id="timer-value">4:00:00</span>
    </div>

    <?php endif; ?>
</div><!-- /container -->

<!-- ─ Script de polling ─ -->
<script>
const VM_NAME    = '<?= $vmName ?>';
const POLL_TOKEN = '<?= htmlspecialchars($pollToken) ?>';
const STATUS_URL = '<?= $statusUrl ?>';
const TTYD_PORT  = <?= $ttydPort ?>;
const MAX_WAIT   = <?= VM_BOOT_TIMEOUT ?>;

let pollInterval = null;
let startTime    = Date.now();
let bootDuration = 0;
let timerStart   = null;

const steps    = { 2: 15, 3: 55, 4: 85 }; // % de progression par étape
const $prog    = document.getElementById('progress-bar');
const $label   = document.getElementById('progress-label');
const $bar     = document.getElementById('status-bar');
const $title   = document.getElementById('status-title');
const $desc    = document.getElementById('status-desc');
const $spinner = document.getElementById('spinner');
const $ip      = document.getElementById('info-ip');
const $term    = document.getElementById('terminal-wrapper');
const $iframe  = document.getElementById('terminal-iframe');
const $timerBar = document.getElementById('timer-bar');
const $timerVal = document.getElementById('timer-value');

function setStep(n, label) {
    for (let i = 2; i <= 4; i++) {
        const el = document.getElementById('step-' + i);
        if (i < n)  { el.className = 'step done';    el.querySelector('.step-icon').textContent = '✅'; }
        if (i === n){ el.className = 'step active'; }
        if (i > n)  { el.className = 'step pending'; }
    }
    $prog.style.width = (steps[n] || 95) + '%';
    $label.textContent = label;
}

function setReady(ip) {
    $bar.className = 'status-bar ready';
    $spinner.style.display = 'none';
    $title.textContent = '✅ Votre VM est prête !';
    $desc.textContent  = 'Connexion SSH en cours d\'ouverture…';
    $prog.style.width  = '100%';
    $label.textContent = 'Prête';
    document.getElementById('step-4').className = 'step done';
    document.getElementById('step-4').querySelector('.step-icon').textContent = '✅';
    $ip.textContent = ip;

    // Ouvrir le terminal SSH (ttyd)
    const ttydUrl = `http://${ip}:${TTYD_PORT}`;
    $iframe.src   = ttydUrl;
    $term.style.display = 'block';

    // Afficher le timer
    timerStart = Date.now();
    $timerBar.style.display = 'flex';
    updateTimer();
    setInterval(updateTimer, 1000);

    clearInterval(pollInterval);
}

function setError(msg) {
    $bar.className = 'status-bar error';
    $spinner.style.display = 'none';
    $title.textContent = '❌ Erreur de démarrage';
    $desc.textContent  = msg;
    clearInterval(pollInterval);
}

function updateTimer() {
    if (!timerStart) return;
    const elapsed   = Math.floor((Date.now() - timerStart) / 1000);
    const remaining = Math.max(0, 4 * 3600 - elapsed);
    const h = Math.floor(remaining / 3600);
    const m = Math.floor((remaining % 3600) / 60);
    const s = remaining % 60;
    $timerVal.textContent = `${h}:${String(m).padStart(2,'0')}:${String(s).padStart(2,'0')}`;
    if (remaining === 0) {
        $timerVal.style.color = '#dc3545';
        $timerVal.textContent = 'VM arrêtée';
    }
}

async function pollStatus() {
    const elapsed = (Date.now() - startTime) / 1000;
    if (elapsed > MAX_WAIT) {
        setError(`Timeout : la VM n'a pas démarré dans les ${MAX_WAIT / 60} minutes. Veuillez réessayer.`);
        return;
    }

    // Mise à jour de la progression visuelle
    const pct = Math.min(85, Math.floor((elapsed / MAX_WAIT) * 85));
    $prog.style.width = pct + '%';

    if (elapsed < 30)       setStep(2, 'Provisionnement Azure…');
    else if (elapsed < 120) setStep(3, 'Démarrage des services…');
    else                    setStep(3, 'Initialisation ttyd (SSH web)…');

    try {
        const res  = await fetch(`${STATUS_URL}?vm=${encodeURIComponent(VM_NAME)}&token=${encodeURIComponent(POLL_TOKEN)}`);
        const data = await res.json();

        $ip.textContent = data.ip || '—';

        if (data.ready && data.ip) {
            setReady(data.ip);
        } else if (data.error) {
            setError(data.error);
        }
    } catch (e) {
        console.warn('Polling error:', e);
        // On continue de poller malgré l'erreur réseau
    }
}

// Démarrer le polling toutes les 10 secondes
<?php if (!$error): ?>
setStep(2, 'Provisionnement Azure en cours…');
pollInterval = setInterval(pollStatus, 10000);
pollStatus(); // Premier appel immédiat
<?php endif; ?>
</script>

</body>
</html>
