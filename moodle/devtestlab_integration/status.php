<?php
// =============================================================================
// status.php — Endpoint AJAX de polling de l'état de la VM
// =============================================================================
// Appelé par le JS de launch_tp.php toutes les 10 secondes.
// Retourne JSON : { ready, ip, powerState, provisioningState, error? }
// =============================================================================

declare(strict_types=1);

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/azure_dtl_api.php';

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, no-cache');
header('X-Content-Type-Options: nosniff');

// ── Validation du token signé ─────────────────────────────────────────────────
$rawToken = filter_input(INPUT_GET, 'token', FILTER_SANITIZE_SPECIAL_CHARS) ?? '';
$vmName   = filter_input(INPUT_GET, 'vm',    FILTER_SANITIZE_SPECIAL_CHARS) ?? '';

if (empty($rawToken) || empty($vmName)) {
    dtl_json(['error' => 'Paramètres manquants'], 400);
}

// Vérifier signature
$parts = explode('.', $rawToken, 2);
if (count($parts) !== 2) {
    dtl_json(['error' => 'Token invalide'], 403);
}
[$payload, $sig] = $parts;
$expectedSig = hash_hmac('sha256', $payload, TP_SECRET_KEY);
if (!hash_equals($expectedSig, $sig)) {
    dtl_log("Token invalide pour VM '$vmName'", 'WARN');
    dtl_json(['error' => 'Token invalide ou expiré'], 403);
}

// Décoder le payload
$data = json_decode(base64_decode($payload), true);
if (!$data || $data['expires'] < time()) {
    dtl_json(['error' => 'Token expiré'], 403);
}
if ($data['vm'] !== $vmName) {
    dtl_json(['error' => 'VM non autorisée'], 403);
}

// ── Récupérer le statut de la VM ──────────────────────────────────────────────
try {
    $dtl    = new AzureDTLApi();
    $status = $dtl->getVmStatus($vmName);

    // Vérifier si ttyd est accessible (VM vraiment prête)
    $ttydReady = false;
    if ($status['ready'] && !empty($status['ip'])) {
        $ttydReady = isTtydReachable($status['ip'], TTYD_PORT);
    }

    dtl_json([
        'vm'               => $vmName,
        'ready'            => $status['ready'] && $ttydReady,
        'powerState'       => $status['powerState'],
        'provisioningState'=> $status['provisioningState'],
        'ip'               => $status['ip'],
        'ttydReady'        => $ttydReady,
        'ts'               => time(),
    ]);

} catch (Exception $e) {
    dtl_log("Erreur status.php pour '$vmName' : " . $e->getMessage(), 'ERROR');
    dtl_json(['error' => 'Erreur interne : ' . $e->getMessage()], 500);
}

// ── Helper : vérifier si ttyd répond ─────────────────────────────────────────
function isTtydReachable(string $ip, int $port, int $timeoutSec = 3): bool {
    $socket = @fsockopen($ip, $port, $errno, $errstr, $timeoutSec);
    if ($socket) {
        fclose($socket);
        return true;
    }
    return false;
}
