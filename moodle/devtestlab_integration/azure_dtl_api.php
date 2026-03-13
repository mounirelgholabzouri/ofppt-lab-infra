<?php
// =============================================================================
// azure_dtl_api.php — Client PHP pour l'API REST Azure DevTest Labs
// =============================================================================

require_once __DIR__ . '/config.php';

class AzureDTLApi {

    private string $token = '';
    private string $tokenExpiry = '';
    private string $subscriptionId;
    private string $resourceGroup;
    private string $labName;
    private string $apiVersion = '2018-09-15';

    public function __construct() {
        $this->subscriptionId = AZURE_SUBSCRIPTION_ID;
        $this->resourceGroup  = DTL_RESOURCE_GROUP;
        $this->labName        = DTL_LAB_NAME;
    }

    // ── Authentification OAuth2 — Service Principal ───────────────────────────
    private function getToken(): string {
        if ($this->token && time() < strtotime($this->tokenExpiry)) {
            return $this->token;
        }

        $url  = "https://login.microsoftonline.com/" . AZURE_TENANT_ID . "/oauth2/v2.0/token";
        $body = http_build_query([
            'grant_type'    => 'client_credentials',
            'client_id'     => AZURE_CLIENT_ID,
            'client_secret' => AZURE_CLIENT_SECRET,
            'scope'         => 'https://management.azure.com/.default',
        ]);

        $response = $this->curl('POST', $url, $body, ['Content-Type: application/x-www-form-urlencoded']);
        if (empty($response['access_token'])) {
            throw new RuntimeException("Impossible d'obtenir le token Azure : " . json_encode($response));
        }

        $this->token       = $response['access_token'];
        $this->tokenExpiry = date('Y-m-d H:i:s', time() + $response['expires_in'] - 60);
        return $this->token;
    }

    // ── Appel générique à l'API Azure REST ───────────────────────────────────
    private function curl(string $method, string $url, mixed $body = null, array $extraHeaders = []): array {
        $ch = curl_init();
        $headers = array_merge([
            'Accept: application/json',
            'Content-Type: application/json',
        ], $extraHeaders);

        if ($this->token) {
            $headers[] = 'Authorization: Bearer ' . $this->token;
        }

        curl_setopt_array($ch, [
            CURLOPT_URL            => $url,
            CURLOPT_CUSTOMREQUEST  => $method,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_HTTPHEADER     => $headers,
            CURLOPT_TIMEOUT        => 30,
            CURLOPT_SSL_VERIFYPEER => true,
        ]);

        if ($body) {
            curl_setopt($ch, CURLOPT_POSTFIELDS, is_array($body) ? json_encode($body) : $body);
        }

        $result   = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        $decoded = json_decode($result, true) ?? [];
        if ($httpCode >= 400) {
            $msg = $decoded['error']['message'] ?? $result;
            dtl_log("ERREUR API Azure [$httpCode] $method $url : $msg", 'ERROR');
        }

        return $decoded;
    }

    // ── URL de base Azure Management ─────────────────────────────────────────
    private function labUrl(string $path = ''): string {
        return "https://management.azure.com/subscriptions/{$this->subscriptionId}"
             . "/resourceGroups/{$this->resourceGroup}"
             . "/providers/Microsoft.DevTestLab/labs/{$this->labName}"
             . ($path ? "/$path" : '')
             . "?api-version={$this->apiVersion}";
    }

    // ── Créer une VM dans le lab ──────────────────────────────────────────────
    public function createVm(string $vmName, string $tpCode, string $username): array {
        $this->getToken();

        $tp = TP_CATALOG[$tpCode] ?? null;
        if (!$tp) {
            throw new InvalidArgumentException("TP inconnu : $tpCode");
        }

        $filiere    = $tp['filiere'];
        $formula    = DTL_FORMULAS[$filiere] ?? null;
        if (!$formula) {
            throw new RuntimeException("Formule introuvable pour la filière : $filiere");
        }

        $formulaId = "/subscriptions/{$this->subscriptionId}"
                   . "/resourceGroups/{$this->resourceGroup}"
                   . "/providers/Microsoft.DevTestLab/labs/{$this->labName}"
                   . "/formulas/$formula";

        // Mot de passe SSH unique par stagiaire (déterministe mais fort)
        $vmPassword = 'TP@' . strtoupper(substr(md5($username . TP_SECRET_KEY), 0, 8)) . '2024!';

        $payload = [
            'location'   => DTL_LOCATION,
            'properties' => [
                'formulaId'    => $formulaId,
                'userName'     => DTL_ADMIN_USER,
                'password'     => $vmPassword,
                'size'         => $tp['vm_size'],
                'storageType'  => 'Premium',
                'notes'        => "TP: $tpCode | Stagiaire: $username | Créée: " . date('d/m/Y H:i'),
                'tags'         => [
                    'Stagiaire' => $username,
                    'TP'        => $tpCode,
                    'Filiere'   => $filiere,
                    'Ephemere'  => 'true',
                ],
            ],
        ];

        dtl_log("Création VM '$vmName' pour '$username' (TP: $tpCode, formule: $formula)");
        $url = $this->labUrl("virtualmachines/$vmName");
        return $this->curl('PUT', $url, $payload);
    }

    // ── Récupérer l'état d'une VM ─────────────────────────────────────────────
    public function getVmStatus(string $vmName): array {
        $this->getToken();
        $url    = $this->labUrl("virtualmachines/$vmName");
        $result = $this->curl('GET', $url);

        $state        = $result['properties']['lastKnownPowerState'] ?? 'Unknown';
        $provState    = $result['properties']['provisioningState']   ?? 'Unknown';
        $fqdn         = $result['properties']['fqdn']                ?? '';
        $computeId    = $result['properties']['computeId']           ?? '';

        // Récupérer l'IP publique si disponible
        $publicIp = '';
        if ($fqdn) {
            $publicIp = $fqdn;
        } elseif ($computeId) {
            $publicIp = $this->getVmPublicIp($computeId);
        }

        return [
            'name'             => $vmName,
            'powerState'       => $state,
            'provisioningState'=> $provState,
            'ip'               => $publicIp,
            'fqdn'             => $fqdn,
            'ready'            => ($state === 'Running' && $provState === 'Succeeded'),
        ];
    }

    // ── Récupérer l'IP publique depuis l'ID de la VM Compute ─────────────────
    private function getVmPublicIp(string $computeId): string {
        $this->getToken();
        try {
            $url    = "https://management.azure.com{$computeId}?api-version=2023-04-01&\$expand=instanceView";
            $result = $this->curl('GET', $url);
            $nicId  = $result['properties']['networkProfile']['networkInterfaces'][0]['id'] ?? '';
            if (!$nicId) return '';

            $nic    = $this->curl('GET', "https://management.azure.com{$nicId}?api-version=2023-04-01");
            $pipId  = $nic['properties']['ipConfigurations'][0]['properties']['publicIPAddress']['id'] ?? '';
            if (!$pipId) return '';

            $pip    = $this->curl('GET', "https://management.azure.com{$pipId}?api-version=2023-04-01");
            return $pip['properties']['ipAddress'] ?? '';
        } catch (Exception $e) {
            dtl_log("Impossible de récupérer l'IP : " . $e->getMessage(), 'WARN');
            return '';
        }
    }

    // ── Démarrer une VM existante ─────────────────────────────────────────────
    public function startVm(string $vmName): bool {
        $this->getToken();
        $url    = $this->labUrl("virtualmachines/$vmName/start");
        $result = $this->curl('POST', $url);
        dtl_log("Démarrage VM '$vmName'");
        return empty($result['error']);
    }

    // ── Arrêter une VM ────────────────────────────────────────────────────────
    public function stopVm(string $vmName): bool {
        $this->getToken();
        $url    = $this->labUrl("virtualmachines/$vmName/stop");
        $result = $this->curl('POST', $url);
        dtl_log("Arrêt VM '$vmName'");
        return empty($result['error']);
    }

    // ── Supprimer une VM (mode éphémère) ──────────────────────────────────────
    public function deleteVm(string $vmName): bool {
        $this->getToken();
        $url    = $this->labUrl("virtualmachines/$vmName");
        $result = $this->curl('DELETE', $url);
        dtl_log("Suppression VM '$vmName'");
        return empty($result['error']);
    }

    // ── Vérifier si une VM existe déjà ────────────────────────────────────────
    public function vmExists(string $vmName): bool {
        $this->getToken();
        $url    = $this->labUrl("virtualmachines/$vmName");
        $result = $this->curl('GET', $url);
        return !empty($result['id']);
    }

    // ── Lister les VMs d'un stagiaire ─────────────────────────────────────────
    public function listUserVms(string $username): array {
        $this->getToken();
        $url    = $this->labUrl('virtualmachines') . "&\$filter=tags/Stagiaire eq '$username'";
        $result = $this->curl('GET', $url);
        return $result['value'] ?? [];
    }

    // ── Générer le nom de VM pour un stagiaire + TP ────────────────────────────
    public static function buildVmName(string $username, string $tpCode): string {
        // Nom Azure DTL : max 15 caractères, alphanumérique + tiret
        $clean   = preg_replace('/[^a-z0-9]/', '', strtolower($username));
        $tp      = strtolower(str_replace(['-', '_'], '', $tpCode));
        $name    = 'vm-' . substr($clean, 0, 5) . '-' . substr($tp, 0, 7);
        return substr($name, 0, 15);
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────
function dtl_log(string $message, string $level = 'INFO'): void {
    if (defined('LOG_LEVEL') && LOG_LEVEL === 'ERROR' && $level !== 'ERROR') return;
    $line = sprintf("[%s][%s] %s\n", date('Y-m-d H:i:s'), $level, $message);
    if (defined('LOG_FILE')) {
        file_put_contents(LOG_FILE, $line, FILE_APPEND | LOCK_EX);
    }
    if (defined('WP_DEBUG') && WP_DEBUG) error_log($line);
}

function dtl_json(array $data, int $httpCode = 200): void {
    http_response_code($httpCode);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
    exit;
}
