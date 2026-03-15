<?php
// =============================================================================
// cleanup_tp.php — Suppression automatique de la VM quand le stagiaire ferme le TP
// =============================================================================
// Appelé par navigator.sendBeacon() dans launch_tp.php dès que la page devient
// cachée (onglet fermé, navigateur fermé, navigation vers une autre page).
// Également appelé en fetch() par le bouton "Terminer le TP" et quand le timer 4h expire.
//
// Sécurité : token HMAC signé avec TP_SECRET_KEY (même logique que status.php).
// La suppression DTL est lancée en arrière-plan après l'envoi de la réponse HTTP.
// =============================================================================

declare(strict_types=1);

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/azure_dtl_api.php';

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, no-cache');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, GET');
header('Access-Control-Allow-Headers: Content-Type');

// ── Lire paramètres (sendBeacon peut envoyer FormData ou JSON) ───────────────
$rawInput = file_get_contents('php://input');
$json     = json_decode($rawInput ?: '{}', true) ?? [];

// Priorité : JSON body > POST form > GET params
$rawToken = $json['token'] ?? ($_POST['token'] ?? ($_GET['token'] ?? ''));
$vmName   = $json['vm']    ?? ($_POST['vm']    ?? ($_GET['vm']    ?? ''));

if (empty($rawToken) || empty($vmName)) {
    http_response_code(400);
    echo json_encode(['error' => 'Paramètres manquants']);
    exit;
}

// ── Validation du token HMAC ──────────────────────────────────────────────────
$parts = explode('.', $rawToken, 2);
if (count($parts) !== 2) {
    http_response_code(403);
    echo json_encode(['error' => 'Token invalide']);
    exit;
}

[$payload, $sig] = $parts;
$expected = hash_hmac('sha256', $payload, TP_SECRET_KEY);
if (!hash_equals($expected, $sig)) {
    http_response_code(403);
    echo json_encode(['error' => 'Signature invalide']);
    exit;
}

$data = json_decode(base64_decode($payload), true) ?? [];
if (($data['expires'] ?? 0) < time()) {
    http_response_code(403);
    echo json_encode(['error' => 'Token expiré']);
    exit;
}

// Vérifier que le vmName correspond au token
if (($data['vm'] ?? '') !== $vmName) {
    http_response_code(403);
    echo json_encode(['error' => 'VM non autorisée']);
    exit;
}

$user  = $data['user']  ?? 'unknown';
$tpCode = $data['tp']   ?? 'unknown';
dtl_log("Cleanup déclenché pour VM '$vmName' (user: $user, TP: $tpCode)");

// ── Répondre immédiatement (sendBeacon n'attend pas la réponse) ───────────────
http_response_code(200);
echo json_encode(['ok' => true, 'vm' => $vmName, 'msg' => 'Suppression en cours']);

// Flush la réponse vers le client avant de continuer en arrière-plan
ignore_user_abort(true);
if (function_exists('fastcgi_finish_request')) {
    fastcgi_finish_request();
} else {
    if (ob_get_level()) ob_end_flush();
    flush();
}

// ── Suppression de la VM DTL (en arrière-plan, après le flush) ───────────────
try {
    $dtl = new AzureDTLApi();
    if ($dtl->vmExists($vmName)) {
        $dtl->deleteVm($vmName);
        dtl_log("VM '$vmName' supprimée avec succès (fermeture TP par $user)");
    } else {
        dtl_log("VM '$vmName' déjà absente du lab (user: $user)");
    }
} catch (Exception $e) {
    dtl_log("Erreur cleanup VM '$vmName' : " . $e->getMessage(), 'ERROR');
}
