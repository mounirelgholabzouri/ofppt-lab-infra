<?php
// =============================================================================
// launch_tp.php — Lanceur de VM de TP depuis OFPPT Academy (Moodle)
// =============================================================================
// URL : /local/devtestlab/launch_tp.php?tp=CC101-TP1&course=<id>
// =============================================================================

declare(strict_types=1);
error_reporting(E_ALL);
ini_set('display_errors', '0');

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/azure_dtl_api.php';

// Bootstrap Moodle
define('MOODLE_INTERNAL', true);
if (file_exists(MOODLE_ROOT . '/config.php')) {
    require_once MOODLE_ROOT . '/config.php';
    require_once MOODLE_ROOT . '/lib/moodlelib.php';
    require_once MOODLE_ROOT . '/lib/weblib.php';
    require_login();
    $moodleUsername = $USER->username;
    $moodleFullname = fullname($USER);
    $isLoggedIn     = isloggedin() && !isguestuser();
} else {
    session_start();
    $moodleUsername = $_SESSION['username'] ?? 'stagiaire';
    $moodleFullname = $_SESSION['fullname'] ?? 'Stagiaire OFPPT';
    $isLoggedIn     = true;
}

if (!$isLoggedIn) {
    http_response_code(403);
    die('Acces refuse. Veuillez vous connecter a OFPPT Academy.');
}

$tpCode   = filter_input(INPUT_GET, 'tp',     FILTER_SANITIZE_SPECIAL_CHARS) ?? '';
$action   = filter_input(INPUT_GET, 'action', FILTER_SANITIZE_SPECIAL_CHARS) ?? 'launch';
$courseId = filter_input(INPUT_GET, 'course', FILTER_SANITIZE_NUMBER_INT)    ?? 0;

if (empty($tpCode) || !array_key_exists($tpCode, TP_CATALOG)) {
    http_response_code(400);
    die("Code TP invalide : " . htmlspecialchars($tpCode));
}

$tp     = TP_CATALOG[$tpCode];
$vmName = AzureDTLApi::buildVmName($moodleUsername, $tpCode);
$dtl    = new AzureDTLApi();

// Action stop
if ($action === 'stop') {
    try {
        if ($dtl->vmExists($vmName)) {
            $dtl->deleteVm($vmName);
        }
        dtl_log("VM '$vmName' terminee par $moodleUsername");
    } catch (Exception $e) {
        dtl_log("Erreur stop : " . $e->getMessage(), 'ERROR');
    }
    $redirect = $courseId ? MOODLE_WWWROOT . "/course/view.php?id=$courseId" : MOODLE_WWWROOT;
    header("Location: $redirect");
    exit;
}

// Lancement VM
$error   = '';
$created = false;

try {
    if (!$dtl->vmExists($vmName)) {
        $dtl->createVm($vmName, $tpCode, $moodleUsername);
        $created = true;
    } else {
        $status = $dtl->getVmStatus($vmName);
        if ($status['powerState'] !== 'Running') {
            $dtl->startVm($vmName);
        }
    }
} catch (Exception $e) {
    $error = $e->getMessage();
    dtl_log("Erreur lancement VM : $error", 'ERROR');
}

// Token HMAC polling
$tokenPayload = base64_encode(json_encode([
    'vm'      => $vmName,
    'user'    => $moodleUsername,
    'tp'      => $tpCode,
    'expires' => time() + 3600,
]));
$tokenSig  = hash_hmac('sha256', $tokenPayload, TP_SECRET_KEY);
$pollToken = $tokenPayload . '.' . $tokenSig;

// Donnees filiere
$filiereData = [
    'cloud'  => ['color' => '#0078D4', 'label' => 'Cloud Computing',        'icon' => 'cloud',   'desc' => 'Docker · Kubernetes · Terraform · Azure'],
    'reseau' => ['color' => '#009688', 'label' => 'Reseau & Infrastructure', 'icon' => 'network', 'desc' => 'Wireshark · FRRouting · OpenVPN · WireGuard'],
    'cyber'  => ['color' => '#C1272D', 'label' => 'Cybersecurite',          'icon' => 'shield',  'desc' => 'Metasploit · Nmap · sqlmap · DVWA'],
];
$fil        = $filiereData[$tp['filiere']] ?? $filiereData['cloud'];
$statusUrl  = MOODLE_WWWROOT . "/local/devtestlab/status.php";
$stopUrl    = "?tp=" . urlencode($tpCode) . "&action=stop&course=" . (int)$courseId;
$courseUrl  = $courseId ? MOODLE_WWWROOT . "/course/view.php?id=$courseId" : MOODLE_WWWROOT;
$initAvatar = strtoupper(substr($moodleFullname ?: 'S', 0, 1));

$svgIcons = [
    'cloud'   => '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="20" height="20"><path d="M3 15a4 4 0 004 4h9a5 5 0 10-.1-9.999 5.002 5.002 0 10-9.78 2.096A4.001 4.001 0 003 15z"/></svg>',
    'network' => '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="20" height="20"><circle cx="12" cy="12" r="10"/><line x1="2" y1="12" x2="22" y2="12"/><path d="M12 2a15.3 15.3 0 014 10 15.3 15.3 0 01-4 10 15.3 15.3 0 01-4-10 15.3 15.3 0 014-10z"/></svg>',
    'shield'  => '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="20" height="20"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>',
];
$svgIcon = $svgIcons[$fil['icon']] ?? $svgIcons['cloud'];
?>
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Lab TP — <?= htmlspecialchars($tp['label']) ?> | OFPPT Academy</title>
<style>
/* =========================================================
   OFPPT Academy — Theme officiel
   Palette : Teal #009688, Sombre #3a3a3a, Orange #F26522
   ========================================================= */
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

:root {
  --teal:    #009688;
  --teal-dk: #00796b;
  --teal-lt: #e0f5f3;
  --orange:  #F26522;
  --dark:    #3a3a3a;
  --gray-bg: #f5f5f5;
  --text:    #2c2c2c;
  --fil:     <?= $fil['color'] ?>;
  --r:       10px;
  --sh:      0 2px 10px rgba(0,0,0,.08);
}

body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #eef2f3;
       color: var(--text); min-height: 100vh; display: flex; flex-direction: column; }

/* ── TOPBAR ── */
.topbar { background: var(--dark); height: 38px; display: flex; align-items: center;
          justify-content: flex-end; padding: 0 32px; gap: 20px; }
.topbar a { color: #bbb; font-size: 11.5px; text-decoration: none; transition: color .2s; }
.topbar a:hover { color: #fff; }
.topbar .lang a { font-weight: 700; }
.topbar .lang a.active { color: #fff; }
.topbar .sep { width: 1px; height: 14px; background: #555; }

/* ── MAINBAR ── */
.mainbar { background: #fff; display: flex; align-items: center; padding: 0 32px;
           height: 70px; border-bottom: 1px solid #e5e5e5; box-shadow: var(--sh); position: relative; z-index: 10; }
.logo { display: flex; align-items: center; gap: 12px; text-decoration: none; flex-shrink: 0; }
.logo-circle { width: 54px; height: 54px; background: #fff; border-radius: 50%;
               border: 2px solid #e0e0e0; display: flex; align-items: center; justify-content: center; }
.logo-txt .brand   { font-size: 14px; font-weight: 900; color: var(--dark); letter-spacing: .4px; }
.logo-txt .tagline { font-size: 10px; color: var(--teal); }

.mainnav { display: flex; align-items: center; gap: 2px; margin-left: 36px; flex: 1; }
.mainnav a { padding: 8px 14px; font-size: 12.5px; font-weight: 700; text-decoration: none;
             letter-spacing: .3px; border-radius: 6px; transition: background .2s; white-space: nowrap; }
.mainnav a.or { color: var(--orange); }
.mainnav a.tl { color: var(--teal); }
.mainnav a:hover { background: var(--gray-bg); }
.mainnav .vsep { width: 1px; height: 18px; background: #e0e0e0; margin: 0 6px; flex-shrink: 0; }

.user-chip { margin-left: auto; display: flex; align-items: center; gap: 10px; flex-shrink: 0; }
.avatar { width: 34px; height: 34px; border-radius: 50%; background: var(--teal);
          color: #fff; font-size: 13px; font-weight: 700;
          display: flex; align-items: center; justify-content: center; }
.user-chip span { font-size: 13px; color: var(--dark); max-width: 150px;
                  overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

/* ── HERO ── */
.hero { background: linear-gradient(150deg, #aaddd9 0%, #c8ecea 45%, #dff5f3 100%);
        position: relative; overflow: hidden; padding: 32px 32px 0; }
.hero::after { content: ''; position: absolute; inset: 0; pointer-events: none;
  background: radial-gradient(circle at 80% 50%, rgba(0,150,136,.08) 0%, transparent 60%),
              radial-gradient(circle at 10% 30%, rgba(0,150,136,.06) 0%, transparent 50%); }

/* Icones flottantes */
.floats { position: absolute; inset: 0; pointer-events: none; z-index: 1; }
.fi { position: absolute; width: 50px; height: 50px; border-radius: 50%;
      background: var(--teal); display: flex; align-items: center; justify-content: center;
      color: #fff; box-shadow: 0 4px 14px rgba(0,150,136,.25);
      animation: flt 3.5s ease-in-out infinite; }
.fi svg { width: 22px; height: 22px; }
.fi-1 { top: 18px;  left: 55px;   animation-delay: 0s; }
.fi-2 { top: 12px;  right: 220px; animation-delay: .9s;  background: #00897b; }
.fi-3 { top: 38px;  right: 75px;  animation-delay: 1.8s; background: #1565c0; }
.fi-4 { bottom: 28px; left: 170px; animation-delay: .4s; background: #00695c; }
@keyframes flt { 0%,100%{transform:translateY(0)} 50%{transform:translateY(-7px)} }

.hero-band { position: relative; z-index: 2; background: var(--teal); color: #fff;
             padding: 14px 28px; border-radius: 8px 8px 0 0;
             display: flex; align-items: center; gap: 16px; }
.hero-band .hb-icon { width: 40px; height: 40px; border-radius: 50%; flex-shrink: 0;
                      background: rgba(255,255,255,.25); display: flex; align-items: center; justify-content: center; }
.hero-band h1 { font-size: 17px; font-weight: 800; }
.hero-band p  { font-size: 12.5px; opacity: .9; margin-top: 2px; }
.hero-badge   { margin-left: auto; background: rgba(255,255,255,.2); padding: 5px 14px;
                border-radius: 20px; font-size: 11.5px; font-weight: 700; white-space: nowrap; }

/* ── BREADCRUMB ── */
.bc { background: #fff; border-bottom: 1px solid #ebebeb; padding: 9px 32px;
      font-size: 12.5px; color: #999; display: flex; align-items: center; gap: 6px; }
.bc a { color: var(--teal); text-decoration: none; }
.bc a:hover { text-decoration: underline; }
.bc .cur { color: var(--fil); font-weight: 600; }

/* ── LAYOUT ── */
.body { max-width: 980px; margin: 24px auto; padding: 0 20px; flex: 1; width: 100%; }
.grid { display: grid; grid-template-columns: 1fr 272px; gap: 18px; }

/* ── CARD ── */
.card { background: #fff; border-radius: var(--r); box-shadow: var(--sh);
        border: 1px solid #e8e8e8; overflow: hidden; margin-bottom: 16px; }
.card-head { padding: 14px 20px; border-bottom: 2px solid var(--fil);
             background: #fafafa; display: flex; align-items: center; gap: 10px; }
.ch-icon { width: 34px; height: 34px; background: var(--fil); border-radius: 7px;
           display: flex; align-items: center; justify-content: center; color: #fff; flex-shrink: 0; }
.card-head h2 { font-size: 14px; font-weight: 700; color: var(--dark); }
.tp-badge { margin-left: auto; background: var(--fil); color: #fff;
            font-size: 11px; font-weight: 700; padding: 3px 11px; border-radius: 12px; }
.card-body { padding: 20px; }

/* ── STATUS ── */
.sb { display: flex; align-items: center; gap: 12px; padding: 16px 18px;
      border-radius: 7px; margin-bottom: 16px; transition: all .4s; }
.sb.boot { background: #e0f4f6; border-left: 4px solid #00acc1; }
.sb.ok   { background: #e8f5e9; border-left: 4px solid #43a047; }
.sb.err  { background: #fce8e8; border-left: 4px solid #e53935; }
.sb-icon { font-size: 28px; flex-shrink: 0; }
.sb h3 { font-size: 14px; font-weight: 700; }
.sb p  { font-size: 12.5px; color: #666; margin-top: 2px; }
.spin { width: 28px; height: 28px; flex-shrink: 0; border: 3px solid #cde9e7;
        border-top-color: var(--teal); border-radius: 50%; animation: sp 1s linear infinite; }
@keyframes sp { to { transform:rotate(360deg) } }

/* ── PROGRESS ── */
.prog-track { height: 5px; background: #e0e0e0; border-radius: 3px; overflow: hidden; margin-bottom: 4px; }
.prog-fill  { height: 100%; width: 5%; background: var(--teal); border-radius: 3px; transition: width 1.5s ease; }
.prog-lbl   { font-size: 11px; color: #9e9e9e; text-align: right; }

/* ── ETAPES ── */
.steps { display: flex; flex-direction: column; gap: 7px; margin: 14px 0; }
.step  { display: flex; align-items: center; gap: 10px; padding: 9px 12px; border-radius: 6px;
         font-size: 12.5px; border: 1px solid transparent; transition: all .3s; }
.step.done    { background: #e8f5e9; color: #2e7d32; border-color: #c8e6c9; }
.step.active  { background: #e3f2fd; color: #1565c0; border-color: #bbdefb; font-weight: 600; }
.step.pending { background: #fafafa; color: #9e9e9e; border-color: #eee; }
.sn { width: 20px; height: 20px; border-radius: 50%; font-size: 10px; font-weight: 700;
      display: flex; align-items: center; justify-content: center; flex-shrink: 0; }
.step.done    .sn { background: #43a047; color: #fff; }
.step.active  .sn { background: #1976d2; color: #fff; }
.step.pending .sn { background: #e0e0e0; color: #9e9e9e; }

/* ── VM INFO GRID ── */
.vmg { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin: 14px 0; }
.vmgi { background: #f7f9f9; border: 1px solid #e5e8e8; border-radius: 6px; padding: 10px 12px; }
.vmgi .l { font-size: 10px; text-transform: uppercase; letter-spacing: .5px; color: #888; }
.vmgi .v { font-size: 13px; font-weight: 600; color: var(--dark); margin-top: 2px;
           font-family: 'Courier New', monospace; word-break: break-all; }

/* ── BOUTONS ── */
.btns { display: flex; gap: 8px; flex-wrap: wrap; margin-top: 18px; }
.btn  { padding: 9px 20px; border-radius: 6px; font-size: 12.5px; font-weight: 700;
        border: none; cursor: pointer; text-decoration: none;
        display: inline-flex; align-items: center; gap: 7px; transition: all .2s; }
.btn-p { background: var(--teal);   color: #fff; }
.btn-p:hover { background: var(--teal-dk); transform: translateY(-1px); box-shadow: 0 3px 10px rgba(0,150,136,.3); }
.btn-d { background: #e53935; color: #fff; }
.btn-d:hover { background: #c62828; }
.btn-o { background: transparent; color: var(--text); border: 1.5px solid #d5d5d5; }
.btn-o:hover { background: var(--gray-bg); }

/* ── TERMINAL (ouvert dans nouvel onglet) ── */
.term-wrap { display: none; margin-top: 16px; }
.term-ready { background: #1e1e2e; border-radius: var(--r); overflow: hidden;
              box-shadow: 0 6px 24px rgba(0,0,0,.25); padding: 24px 28px;
              display: flex; align-items: center; gap: 20px; flex-wrap: wrap; }
.term-ready-icon { font-size: 36px; flex-shrink: 0; }
.term-ready-info h3 { color: #cdd6f4; font-size: 15px; font-weight: 700; margin-bottom: 4px; }
.term-ready-info p  { color: #6c7086; font-size: 12.5px; }
.term-ready-btns { margin-left: auto; display: flex; gap: 8px; flex-wrap: wrap; }
.btn-term { padding: 10px 22px; border-radius: 6px; font-size: 13px; font-weight: 700;
            border: none; cursor: pointer; text-decoration: none;
            display: inline-flex; align-items: center; gap: 8px; transition: all .2s; }
.btn-term-open  { background: #28c840; color: #fff; }
.btn-term-open:hover { background: #22a835; transform: translateY(-1px); box-shadow: 0 3px 12px rgba(40,200,64,.35); }
.btn-term-retry { background: #3d3d5c; color: #cdd6f4; }
.btn-term-retry:hover { background: #4d4d70; }

/* ── TIMER ── */
.timer { display: none; background: #fff; border-radius: var(--r); border: 1px solid #e0e0e0;
         box-shadow: var(--sh); padding: 12px 20px; margin-top: 14px;
         align-items: center; gap: 16px; flex-wrap: wrap; }
.timer-lbl { font-size: 12.5px; color: #666; display: flex; align-items: center; gap: 7px; }
.timer-val { font-size: 22px; font-weight: 800; font-family: 'Courier New', monospace; color: var(--teal); }
.timer-bar-w { flex: 1; min-width: 100px; max-width: 280px; }
.timer-track { height: 4px; background: #e0e0e0; border-radius: 2px; overflow: hidden; }
.timer-fill  { height: 100%; background: var(--teal); transition: width 1s linear; border-radius: 2px; }

/* ── SIDEBAR ── */
.ib { background: #fff; border-radius: var(--r); border: 1px solid #e8e8e8;
      box-shadow: var(--sh); overflow: hidden; margin-bottom: 14px; }
.ibh { background: var(--teal); color: #fff; padding: 11px 14px;
       font-size: 12.5px; font-weight: 700; display: flex; align-items: center; gap: 7px; }
.ibb { padding: 12px 14px; }
.ir  { display: flex; justify-content: space-between; align-items: flex-start;
       padding: 6px 0; border-bottom: 1px solid #f0f0f0; font-size: 11.5px; gap: 8px; }
.ir:last-child { border-bottom: none; }
.ir .il { color: #888; flex-shrink: 0; }
.ir .iv { font-weight: 600; color: var(--dark); text-align: right; word-break: break-all; }
.tip { background: #e8f4fd; border: 1px solid #bee3f8; border-radius: 6px;
       padding: 10px 12px; font-size: 11.5px; color: #1a6b9a; line-height: 1.6; }

/* ── FOOTER ── */
.footer { background: var(--dark); color: #999; text-align: center;
          padding: 14px; font-size: 11.5px; margin-top: auto; }
.footer a { color: var(--teal); text-decoration: none; }

/* ── RESPONSIVE ── */
@media (max-width: 768px) {
  .grid { grid-template-columns: 1fr; }
  .sidebar { order: -1; }
  .vmg { grid-template-columns: 1fr; }
  .floats .fi { display: none; }
  .mainnav { display: none; }
  .topbar { display: none; }
  .hero { padding: 16px 16px 0; }
  .body { padding: 0 12px; margin: 14px auto; }
  .mainbar { padding: 0 16px; }
}
</style>
</head>
<body>

<!-- TOPBAR -->
<div class="topbar">
  <a href="<?= MOODLE_WWWROOT ?>">Accueil</a>
  <div class="sep"></div>
  <a href="#">OFPPT</a>
  <div class="sep"></div>
  <a href="#">Capital Humain</a>
  <div class="sep"></div>
  <a href="#">Contact</a>
  <div class="sep"></div>
  <div class="lang" style="display:flex;gap:6px">
    <a href="#" class="active">FR</a>
    <a href="#">AR</a>
  </div>
</div>

<!-- MAINBAR -->
<div class="mainbar">
  <a href="<?= MOODLE_WWWROOT ?>" class="logo">
    <div class="logo-circle">
      <!-- Logo OFPPT SVG officiel -->
      <svg viewBox="0 0 60 60" width="50" height="50" xmlns="http://www.w3.org/2000/svg">
        <circle cx="30" cy="30" r="28" fill="#fff" stroke="#e0e0e0" stroke-width="1"/>
        <!-- Losanges colores (diamants imbriques) -->
        <g transform="translate(30,14)">
          <polygon points="-10,0 -5,-6 0,0 -5,6"  fill="#009688"/>
          <polygon points="-4,0  1,-6 6,0  1,6"   fill="#4CAF50"/>
          <polygon points="2,0   7,-6 12,0  7,6"  fill="#1a5276"/>
        </g>
        <text x="30" y="30" font-family="Arial,sans-serif" font-size="8.5"
              font-weight="900" fill="#3a3a3a" text-anchor="middle" dominant-baseline="middle">OFPPT</text>
        <text x="30" y="43" font-family="Arial,sans-serif" font-size="4.2"
              fill="#009688" text-anchor="middle">La voie de l'avenir</text>
      </svg>
    </div>
    <div class="logo-txt">
      <div class="brand">OFPPT Academy</div>
      <div class="tagline">Plateforme de Formation Professionnelle</div>
    </div>
  </a>

  <nav class="mainnav">
    <a href="<?= MOODLE_WWWROOT ?>/course/index.php" class="or">TROUVER UNE FORMATION</a>
    <div class="vsep"></div>
    <a href="<?= MOODLE_WWWROOT ?>/my/" class="tl">ESPACE STAGIAIRE</a>
    <div class="vsep"></div>
    <a href="#" class="tl">ESPACE ENTREPRISE</a>
  </nav>

  <div class="user-chip">
    <div class="avatar"><?= htmlspecialchars($initAvatar) ?></div>
    <span><?= htmlspecialchars($moodleFullname) ?></span>
  </div>
</div>

<!-- HERO -->
<div class="hero">
  <div class="floats">
    <div class="fi fi-1">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="22" height="22">
        <rect x="2" y="3" width="20" height="14" rx="2"/>
        <line x1="8" y1="21" x2="16" y2="21"/>
        <line x1="12" y1="17" x2="12" y2="21"/>
      </svg>
    </div>
    <div class="fi fi-2">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="22" height="22">
        <path d="M22 10v6M2 10l10-5 10 5-10 5z"/>
        <path d="M6 12v5c3 3 9 3 12 0v-5"/>
      </svg>
    </div>
    <div class="fi fi-3">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="22" height="22">
        <polyline points="16 18 22 12 16 6"/>
        <polyline points="8 6 2 12 8 18"/>
      </svg>
    </div>
    <div class="fi fi-4">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="22" height="22">
        <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>
      </svg>
    </div>
  </div>

  <div class="hero-band">
    <div class="hb-icon"><?= $svgIcon ?></div>
    <div>
      <h1>OFPPT Academy — Lab TP</h1>
      <p><?= htmlspecialchars($fil['label']) ?> &nbsp;&#8250;&nbsp; <?= htmlspecialchars($tp['label']) ?></p>
    </div>
    <div class="hero-badge"><?= htmlspecialchars($tpCode) ?></div>
  </div>
</div>

<!-- BREADCRUMB -->
<div class="bc">
  <a href="<?= MOODLE_WWWROOT ?>">Accueil</a>
  <span>&#8250;</span>
  <?php if ($courseId): ?>
  <a href="<?= htmlspecialchars($courseUrl) ?>">Cours</a>
  <span>&#8250;</span>
  <?php endif; ?>
  <span class="cur">Lab TP &mdash; <?= htmlspecialchars($tpCode) ?></span>
</div>

<!-- BODY -->
<div class="body">
<div class="grid">

<!-- MAIN -->
<div>

<?php if ($error): ?>
<div class="card">
  <div class="card-head">
    <div class="ch-icon" style="background:#e53935">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="18" height="18">
        <circle cx="12" cy="12" r="10"/>
        <line x1="15" y1="9" x2="9" y2="15"/>
        <line x1="9" y1="9" x2="15" y2="15"/>
      </svg>
    </div>
    <h2>Erreur de demarrage</h2>
  </div>
  <div class="card-body">
    <div class="sb err">
      <div class="sb-icon">&#9888;</div>
      <div>
        <h3>Impossible de lancer la VM</h3>
        <p><?= htmlspecialchars($error) ?></p>
      </div>
    </div>
    <div class="btns">
      <a href="?tp=<?= urlencode($tpCode) ?>&amp;course=<?= (int)$courseId ?>" class="btn btn-p">&#8635; Reessayer</a>
      <a href="<?= htmlspecialchars($courseUrl) ?>" class="btn btn-o">&#8592; Retour au cours</a>
    </div>
  </div>
</div>

<?php else: ?>

<!-- CARTE ETAT VM -->
<div class="card">
  <div class="card-head">
    <div class="ch-icon"><?= $svgIcon ?></div>
    <h2>Environnement de TP &mdash; <?= htmlspecialchars($fil['label']) ?></h2>
    <span class="tp-badge"><?= htmlspecialchars($tpCode) ?></span>
  </div>
  <div class="card-body">
    <div class="sb boot" id="sb">
      <div class="spin" id="spin"></div>
      <div>
        <h3 id="sb-title">Demarrage de votre environnement...</h3>
        <p id="sb-desc">
          <?= $created
            ? 'Provisionnement depuis la formule <strong>' . htmlspecialchars(DTL_FORMULAS[$tp['filiere']] ?? 'DTL') . '</strong>...'
            : 'Votre VM existe - demarrage en cours...' ?>
        </p>
      </div>
    </div>

    <div class="prog-track"><div class="prog-fill" id="pf"></div></div>
    <div class="prog-lbl" id="pl">Initialisation...</div>

    <div class="steps">
      <div class="step done"  id="s1"><div class="sn">&#10003;</div>Authentification Azure &mdash; Service Principal valide</div>
      <div class="step <?= $created ? 'active' : 'done' ?>" id="s2">
        <div class="sn"><?= $created ? '2' : '&#10003;' ?></div>
        <?= $created ? 'Provisionnement de la VM en cours...' : 'VM recuperee dans le lab' ?>
      </div>
      <div class="step pending" id="s3"><div class="sn">3</div>Demarrage des services reseau (SSH &middot; ttyd)</div>
      <div class="step pending" id="s4"><div class="sn">4</div>Ouverture du terminal SSH interactif</div>
    </div>

    <div class="vmg">
      <div class="vmgi"><div class="l">Nom VM</div><div class="v" id="vi-vm"><?= htmlspecialchars($vmName) ?></div></div>
      <div class="vmgi"><div class="l">IP / FQDN</div><div class="v" id="vi-ip">En attente...</div></div>
      <div class="vmgi"><div class="l">Filiere</div><div class="v"><?= htmlspecialchars($fil['label']) ?></div></div>
      <div class="vmgi"><div class="l">Etat</div><div class="v" id="vi-st">Provisionnement...</div></div>
    </div>

    <div class="btns">
      <a href="<?= htmlspecialchars($stopUrl) ?>" class="btn btn-d"
         onclick="return confirm('Terminer et supprimer votre VM de TP ?')">
        &#9632; Terminer le TP
      </a>
      <a href="<?= htmlspecialchars($courseUrl) ?>" class="btn btn-o">&#8592; Retour au cours</a>
    </div>
  </div>
</div>

<!-- TERMINAL ttyd — ouvert dans un nouvel onglet -->
<div class="term-wrap" id="term-wrap">
  <div class="term-ready">
    <div class="term-ready-icon">&#128196;</div>
    <div class="term-ready-info">
      <h3>&#10003; Terminal ouvert dans un nouvel onglet</h3>
      <p id="term-url-hint">Connexion SSH web : <span id="term-url-display" style="color:#7dcfff;font-family:monospace"></span></p>
    </div>
    <div class="term-ready-btns">
      <a id="ttyd-link" href="#" target="_blank" class="btn-term btn-term-open">
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
          <rect x="3" y="3" width="18" height="18" rx="2"/>
          <polyline points="16 3 21 3 21 8"/>
          <line x1="10" y1="14" x2="21" y2="3"/>
        </svg>
        Ouvrir le terminal
      </a>
      <button onclick="reloadTerm()" class="btn-term btn-term-retry">
        &#8635; Ré-ouvrir
      </button>
    </div>
  </div>
</div>

<!-- TIMER -->
<div class="timer" id="timer">
  <div class="timer-lbl">
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
      <circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>
    </svg>
    Temps restant avant arret automatique
  </div>
  <div class="timer-val" id="tv">4:00:00</div>
  <div class="timer-bar-w">
    <div class="timer-track"><div class="timer-fill" id="tf" style="width:100%"></div></div>
  </div>
</div>

<?php endif; ?>
</div><!-- /main -->

<!-- SIDEBAR -->
<aside>
  <!-- Info TP -->
  <div class="ib">
    <div class="ibh">
      <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/>
        <line x1="12" y1="16" x2="12.01" y2="16"/>
      </svg>
      Informations TP
    </div>
    <div class="ibb">
      <div class="ir"><span class="il">Code TP</span><span class="iv" style="font-family:monospace"><?= htmlspecialchars($tpCode) ?></span></div>
      <div class="ir"><span class="il">Filiere</span><span class="iv"><?= htmlspecialchars($fil['label']) ?></span></div>
      <div class="ir"><span class="il">Sujet</span><span class="iv" style="font-size:10.5px"><?= htmlspecialchars($tp['label']) ?></span></div>
      <div class="ir"><span class="il">Outils</span><span class="iv" style="font-size:10px"><?= htmlspecialchars($fil['desc']) ?></span></div>
      <div class="ir"><span class="il">Duree max</span><span class="iv">4 heures</span></div>
    </div>
  </div>

  <!-- Acces SSH (visible quand VM prete) -->
  <div class="ib" id="ssh-box" style="display:none">
    <div class="ibh" style="background:#1565c0">
      <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <rect x="2" y="7" width="20" height="14" rx="2"/>
        <path d="M16 21V5a2 2 0 00-2-2h-4a2 2 0 00-2 2v16"/>
      </svg>
      Acces SSH Direct
    </div>
    <div class="ibb">
      <div class="ir"><span class="il">Hote</span><span class="iv" id="ssh-host" style="font-size:10px;font-family:monospace">-</span></div>
      <div class="ir"><span class="il">Utilisateur</span><span class="iv" style="font-family:monospace">azureofppt</span></div>
      <div class="ir"><span class="il">Port SSH</span><span class="iv" style="font-family:monospace">22</span></div>
      <div class="ir"><span class="il">Web SSH</span>
        <span class="iv"><a id="ttyd-badge" href="#" target="_blank" style="color:var(--teal);font-size:10.5px">:7681 &#8594;</a></span>
      </div>
    </div>
  </div>

  <!-- Aide -->
  <div class="ib">
    <div class="ibh" style="background:#00897b">
      <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <circle cx="12" cy="12" r="10"/>
        <path d="M9.09 9a3 3 0 015.83 1c0 2-3 3-3 3"/>
        <line x1="12" y1="17" x2="12.01" y2="17"/>
      </svg>
      Aide
    </div>
    <div class="ibb">
      <div class="tip">
        Le terminal s'ouvre dans le navigateur via <strong>ttyd</strong>.
        Aucun client SSH requis. La VM est supprimee automatiquement apres <strong>4h</strong>.
      </div>
      <div style="margin-top:10px;font-size:11px;color:#666;line-height:1.7">
        &#128161; Copier/Coller : <strong>Ctrl+Shift+C/V</strong>
      </div>
    </div>
  </div>
</aside>

</div><!-- /grid -->
</div><!-- /body -->

<!-- FOOTER -->
<footer class="footer">
  <strong>OFPPT Academy</strong> &mdash; Plateforme Nationale de Formation Professionnelle
  &nbsp;|&nbsp; Propulse par <a href="#">Azure DevTest Labs</a>
  &nbsp;|&nbsp; <a href="<?= htmlspecialchars($courseUrl) ?>">&#8592; Retour au cours</a>
</footer>

<!-- SCRIPT POLLING -->
<?php if (!$error): ?>
<script>
const VM    = <?= json_encode($vmName) ?>;
const TOKEN = <?= json_encode($pollToken) ?>;
const SURL  = <?= json_encode($statusUrl) ?>;
const PORT  = <?= (int)TTYD_PORT ?>;
const TMAX  = <?= (int)VM_BOOT_TIMEOUT ?>;

let poll = null, t0 = Date.now(), tStart = null, curIp = null;

const $sb      = document.getElementById('sb');
const $spin    = document.getElementById('spin');
const $title   = document.getElementById('sb-title');
const $desc    = document.getElementById('sb-desc');
const $pf      = document.getElementById('pf');
const $pl      = document.getElementById('pl');
const $viip    = document.getElementById('vi-ip');
const $vist    = document.getElementById('vi-st');
const $term    = document.getElementById('term-wrap');
const $timer   = document.getElementById('timer');
const $tv      = document.getElementById('tv');
const $tf      = document.getElementById('tf');
const $sshbx   = document.getElementById('ssh-box');
const $sshhst  = document.getElementById('ssh-host');
const $tbadge  = document.getElementById('ttyd-badge');
const $tlink   = document.getElementById('ttyd-link');
const $termUrl = document.getElementById('term-url-display');

function step(n, lbl) {
    [2,3,4].forEach(i => {
        const el = document.getElementById('s' + i);
        if (!el) return;
        const sn = el.querySelector('.sn');
        if (i < n)  { el.className = 'step done';    sn.innerHTML = '&#10003;'; }
        if (i === n){ el.className = 'step active';  sn.textContent = i; }
        if (i > n)  { el.className = 'step pending'; sn.textContent = i; }
    });
    const pctMap = {2:20, 3:55, 4:85};
    $pf.style.width = (pctMap[n] || 92) + '%';
    $pl.textContent = lbl;
}

function setReady(ip) {
    curIp = ip;
    const url = 'http://' + ip + ':' + PORT;
    $sb.className  = 'sb ok';
    if ($spin) $spin.style.display = 'none';
    $title.textContent = '\u2705 Votre environnement est pret !';
    $desc.innerHTML    = 'Terminal SSH disponible sur <strong>' + ip + '</strong>';
    $pf.style.width    = '100%';
    $pl.textContent    = '100% \u2014 Pret';
    ['s3','s4'].forEach(id => {
        const el = document.getElementById(id);
        if (el) { el.className = 'step done'; el.querySelector('.sn').innerHTML = '&#10003;'; }
    });
    $viip.textContent = ip;
    $vist.textContent = 'En cours d\u2019execution';
    if ($sshbx) { $sshhst.textContent = ip; $tbadge.href = url; $sshbx.style.display = 'block'; }
    if ($tlink) $tlink.href = url;
    if ($termUrl) $termUrl.textContent = url;
    if ($term) $term.style.display = 'block';
    // Ouvrir ttyd dans un nouvel onglet automatiquement
    window.open(url, '_blank', 'noopener');
    tStart = Date.now();
    if ($timer) { $timer.style.display = 'flex'; }
    updateTimer();
    setInterval(updateTimer, 1000);
    clearInterval(poll);
}

function setError(msg) {
    $sb.className = 'sb err';
    if ($spin) $spin.style.display = 'none';
    $title.textContent = '\u274C Erreur de demarrage';
    $desc.textContent  = msg;
    $vist.textContent  = 'Erreur';
    clearInterval(poll);
}

function updateTimer() {
    if (!tStart) return;
    const rem = Math.max(0, 4 * 3600 - Math.floor((Date.now() - tStart) / 1000));
    const h = Math.floor(rem / 3600), m = Math.floor((rem % 3600) / 60), s = rem % 60;
    $tv.textContent = h + ':' + String(m).padStart(2,'0') + ':' + String(s).padStart(2,'0');
    if ($tf) $tf.style.width = Math.max(0, (rem / (4*3600)) * 100) + '%';
    if (rem < 300) $tv.style.color = '#e53935';
}

function reloadTerm() {
    if (curIp) {
        window.open('http://' + curIp + ':' + PORT, '_blank', 'noopener');
    }
}

async function doPoll() {
    const elapsed = (Date.now() - t0) / 1000;
    if (elapsed > TMAX) { setError('Timeout: la VM n\u2019a pas demarre en ' + Math.floor(TMAX/60) + ' min.'); return; }
    $pf.style.width = Math.max(5, Math.min(75, Math.floor((elapsed / 180) * 75))) + '%';
    if (elapsed < 60)       step(2, 'Provisionnement Azure DevTest Labs...');
    else if (elapsed < 180) step(3, 'Demarrage des services SSH et ttyd...');
    else                    step(3, 'Verification accessibilite ttyd...');
    try {
        const r = await fetch(SURL + '?vm=' + encodeURIComponent(VM) + '&token=' + encodeURIComponent(TOKEN), {cache:'no-store'});
        const d = await r.json();
        if (d.ip) { $viip.textContent = d.ip; $vist.textContent = d.provisioningState || '-'; }
        if (d.ready && d.ip) setReady(d.ip);
        else if (d.error) setError(d.error);
    } catch(e) { console.warn('[OFPPT-Lab]', e.message); }
}

step(2, 'Connexion a Azure DevTest Labs...');
doPoll();
poll = setInterval(doPoll, 10000);
</script>
<?php endif; ?>

</body>
</html>
