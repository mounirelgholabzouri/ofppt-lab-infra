<?php
// =============================================================================
// azure_dtl_api.php — Client PHP pour l'API REST Azure DevTest Labs
// =============================================================================
// Aligné sur create_vm_with_nsg.ps1 :
//   - Image Ubuntu 22.04 directe (quota D2s_v3 validé)
//   - IP publique dédiée par VM (disallowPublicIpAddress = false)
//   - NSG auto (SSH:22 + ttyd:7681 + HTTP:80) créé et attaché à la NIC
// =============================================================================

require_once __DIR__ . '/config.php';

class AzureDTLApi {

    private string $token       = '';
    private string $tokenExpiry = '';
    private string $subscriptionId;
    private string $resourceGroup;
    private string $labName;
    private string $apiVersion  = '2018-09-15';

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

        dtl_log('[DEBUG] getToken() AZURE_CLIENT_SECRET len=' . strlen(AZURE_CLIENT_SECRET) . ' val_start=' . substr(AZURE_CLIENT_SECRET, 0, 4), 'DEBUG');
        $url  = "https://login.microsoftonline.com/" . AZURE_TENANT_ID . "/oauth2/v2.0/token";
        $body = http_build_query([
            'grant_type'    => 'client_credentials',
            'client_id'     => AZURE_CLIENT_ID,
            'client_secret' => AZURE_CLIENT_SECRET,
            'scope'         => 'https://management.azure.com/.default',
        ], '', '&');  // explicit '&' — Moodle sets arg_separator.output='&amp;'

        dtl_log('[DEBUG] getToken body=' . urldecode($body), 'DEBUG');
        $response = $this->curl('POST', $url, $body, ['Content-Type: application/x-www-form-urlencoded']);
        if (empty($response['access_token'])) {
            throw new RuntimeException("Impossible d'obtenir le token Azure : " . json_encode($response));
        }

        $this->token       = $response['access_token'];
        $this->tokenExpiry = date('Y-m-d H:i:s', time() + ($response['expires_in'] ?? 3600) - 60);
        return $this->token;
    }

    // ── Appel générique à l'API Azure REST ───────────────────────────────────
    private function curl(string $method, string $url, mixed $body = null, array $extraHeaders = [], int $timeout = 60): array {
        $ch = curl_init();

        // N'ajouter Content-Type: application/json que si aucun Content-Type dans extraHeaders
        $hasContentType = (bool) array_filter($extraHeaders, fn($h) => stripos($h, 'Content-Type:') === 0);
        $headers = array_merge(
            ['Accept: application/json'],
            $hasContentType ? [] : ['Content-Type: application/json'],
            $extraHeaders
        );

        if ($this->token) {
            $headers[] = 'Authorization: Bearer ' . $this->token;
        }

        curl_setopt_array($ch, [
            CURLOPT_URL            => $url,
            CURLOPT_CUSTOMREQUEST  => $method,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_HTTPHEADER     => $headers,
            CURLOPT_TIMEOUT        => $timeout,
            CURLOPT_SSL_VERIFYPEER => true,
            CURLOPT_FOLLOWLOCATION => true,
        ]);

        if ($body !== null) {
            curl_setopt($ch, CURLOPT_POSTFIELDS, is_array($body) ? json_encode($body) : $body);
        }

        $result   = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $curlErr  = curl_error($ch);
        curl_close($ch);

        if ($curlErr) {
            dtl_log("cURL error [$method $url] : $curlErr", 'ERROR');
            throw new RuntimeException("Erreur réseau curl : $curlErr");
        }

        $decoded = json_decode($result ?: '{}', true) ?? [];
        if ($httpCode >= 400) {
            $msg = $decoded['error']['message'] ?? ($result ?: "HTTP $httpCode");
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

    // ── Récupérer le VNet du lab DTL ─────────────────────────────────────────
    private function getDtlVnet(): string {
        $url    = $this->labUrl('virtualnetworks');
        $result = $this->curl('GET', $url);
        $vnetId = $result['value'][0]['id'] ?? '';
        if (!$vnetId) {
            dtl_log("VNet DTL introuvable — vérifiez que setup_vnet.ps1 a été exécuté", 'WARN');
        }
        return $vnetId;
    }

    // ── Créer une VM dans le lab (approche directe, IP publique dédiée) ───────
    // Aligné sur create_vm_with_nsg.ps1 : Ubuntu 22.04 + disallowPublicIpAddress=false
    // La VM reçoit son propre NSG (SSH:22 + ttyd:7681 + HTTP:80) après provisionnement.
    public function createVm(string $vmName, string $tpCode, string $username): array {
        $this->getToken();

        $tp = TP_CATALOG[$tpCode] ?? null;
        if (!$tp) {
            throw new InvalidArgumentException("TP inconnu : $tpCode");
        }

        // VNet du lab
        $vnetId = $this->getDtlVnet();
        if (!$vnetId) {
            throw new RuntimeException("VNet DTL introuvable — impossible de créer la VM");
        }

        // Mot de passe unique par stagiaire (déterministe, format: TP@XXXXXXXX2024!)
        $vmPassword = 'TP@' . strtoupper(substr(md5($username . TP_SECRET_KEY), 0, 8)) . '2024!';

        $payload = [
            'name'     => $vmName,
            'location' => DTL_LOCATION,
            'tags'     => [
                'Stagiaire' => $username,
                'TP'        => $tpCode,
                'Filiere'   => $tp['filiere'],
                'Ephemere'  => 'true',
                'Source'    => 'moodle-launch-tp',
            ],
            'properties' => [
                'size'                       => $tp['vm_size'],
                'userName'                   => DTL_ADMIN_USER,
                'password'                   => $vmPassword,
                'isAuthenticationWithSshKey' => false,
                'allowClaim'                 => false,
                'disallowPublicIpAddress'    => false,   // IP publique dédiée
                'storageType'                => 'Standard',
                'labVirtualNetworkId'        => $vnetId,
                'labSubnetName'              => 'subnet-ofppt-dtl',
                'galleryImageReference'      => [
                    'offer'     => 'ubuntu-22_04-lts',
                    'publisher' => 'Canonical',
                    'sku'       => 'server-gen1',
                    'osType'    => 'Linux',
                    'version'   => 'latest',
                ],
                'notes' => "TP: $tpCode | Stagiaire: $username | Créée: " . date('d/m/Y H:i'),
            ],
        ];

        dtl_log("Création VM '$vmName' pour '$username' (TP: $tpCode, taille: {$tp['vm_size']})");
        $url    = $this->labUrl("virtualmachines/$vmName");
        $result = $this->curl('PUT', $url, $payload, [], 120); // DTL creation can take up to 2min to respond

        if (!empty($result['error'])) {
            $errMsg = $result['error']['message'] ?? json_encode($result['error']);
            throw new RuntimeException("Erreur création VM : $errMsg");
        }

        return $result;
    }

    // ── Récupérer l'état d'une VM ─────────────────────────────────────────────
    // Déclenche ensureNsg() automatiquement dès que la VM est Succeeded.
    public function getVmStatus(string $vmName): array {
        $this->getToken();
        $url    = $this->labUrl("virtualmachines/$vmName");
        $result = $this->curl('GET', $url);

        $powerState  = $result['properties']['lastKnownPowerState'] ?? 'Unknown';
        $provState   = $result['properties']['provisioningState']   ?? 'Unknown';
        $fqdn        = $result['properties']['fqdn']                ?? '';
        $computeId   = $result['properties']['computeId']           ?? '';

        // Récupérer l'IP publique
        $publicIp = '';
        if ($fqdn) {
            $publicIp = $fqdn;
        } elseif ($computeId) {
            $publicIp = $this->getVmPublicIp($computeId);
        }

        // Dès que la VM est Succeeded, s'assurer que le NSG est en place
        if ($provState === 'Succeeded' && !empty($publicIp)) {
            try {
                $this->ensureNsg($vmName);
            } catch (Exception $e) {
                dtl_log("ensureNsg '$vmName' : " . $e->getMessage(), 'WARN');
            }
        }

        return [
            'name'              => $vmName,
            'powerState'        => $powerState,
            'provisioningState' => $provState,
            'ip'                => $publicIp,
            'fqdn'              => $fqdn,
            'ready'             => ($powerState === 'Running' && $provState === 'Succeeded'),
        ];
    }

    // ── Récupérer l'IP publique depuis l'ID compute ───────────────────────────
    private function getVmPublicIp(string $computeId): string {
        $this->getToken();
        try {
            $url    = "https://management.azure.com{$computeId}?api-version=2023-04-01&\$expand=instanceView";
            $result = $this->curl('GET', $url);
            $nicId  = $result['properties']['networkProfile']['networkInterfaces'][0]['id'] ?? '';
            if (!$nicId) return '';

            $nic   = $this->curl('GET', "https://management.azure.com{$nicId}?api-version=2023-04-01");
            $pipId = $nic['properties']['ipConfigurations'][0]['properties']['publicIPAddress']['id'] ?? '';
            if (!$pipId) return '';

            $pip = $this->curl('GET', "https://management.azure.com{$pipId}?api-version=2023-04-01");
            return $pip['properties']['ipAddress'] ?? '';
        } catch (Exception $e) {
            dtl_log("getVmPublicIp '$computeId' : " . $e->getMessage(), 'WARN');
            return '';
        }
    }

    // ── Trouver le RG compute d'une VM par nom ────────────────────────────────
    // Les VMs DTL ont leur propre RG compute nommé d'après le nom de la VM.
    private function findComputeRg(string $vmName): string {
        $url    = "https://management.azure.com/subscriptions/{$this->subscriptionId}/resourcegroups?api-version=2021-04-01";
        $result = $this->curl('GET', $url);
        foreach ($result['value'] ?? [] as $rg) {
            if (stripos($rg['name'], $vmName) !== false) {
                return $rg['name'];
            }
        }
        return '';
    }

    // ── Créer NSG (SSH:22 + ttyd:7681 + HTTP:80) et l'attacher à la NIC ──────
    // Idempotent : ne fait rien si le NSG existe déjà.
    public function ensureNsg(string $vmName): bool {
        $this->getToken();

        $computeRg = $this->findComputeRg($vmName);
        if (!$computeRg) {
            dtl_log("ensureNsg: RG compute non trouvé pour '$vmName'", 'WARN');
            return false;
        }

        $nsgName = "nsg-$vmName";
        $nsgUrl  = "https://management.azure.com/subscriptions/{$this->subscriptionId}"
                 . "/resourceGroups/$computeRg/providers/Microsoft.Network/networkSecurityGroups/$nsgName"
                 . "?api-version=2023-09-01";

        // Vérifier si NSG existe déjà
        $existing = $this->curl('GET', $nsgUrl);
        if (!empty($existing['id'])) {
            return true; // Déjà en place
        }

        // Créer NSG avec les règles nécessaires
        $nsgPayload = [
            'location'   => DTL_LOCATION,
            'properties' => [
                'securityRules' => [
                    [
                        'name'       => 'Allow-SSH',
                        'properties' => [
                            'priority'                 => 100,
                            'protocol'                 => 'Tcp',
                            'access'                   => 'Allow',
                            'direction'                => 'Inbound',
                            'sourceAddressPrefix'      => '*',
                            'sourcePortRange'          => '*',
                            'destinationAddressPrefix' => '*',
                            'destinationPortRange'     => '22',
                        ],
                    ],
                    [
                        'name'       => 'Allow-ttyd',
                        'properties' => [
                            'priority'                 => 110,
                            'protocol'                 => 'Tcp',
                            'access'                   => 'Allow',
                            'direction'                => 'Inbound',
                            'sourceAddressPrefix'      => '*',
                            'sourcePortRange'          => '*',
                            'destinationAddressPrefix' => '*',
                            'destinationPortRange'     => (string)TTYD_PORT,
                        ],
                    ],
                    [
                        'name'       => 'Allow-HTTP',
                        'properties' => [
                            'priority'                 => 120,
                            'protocol'                 => 'Tcp',
                            'access'                   => 'Allow',
                            'direction'                => 'Inbound',
                            'sourceAddressPrefix'      => '*',
                            'sourcePortRange'          => '*',
                            'destinationAddressPrefix' => '*',
                            'destinationPortRange'     => '80',
                        ],
                    ],
                ],
            ],
        ];

        $nsgResult = $this->curl('PUT', $nsgUrl, $nsgPayload);
        $nsgId     = $nsgResult['id'] ?? '';

        if (!$nsgId) {
            dtl_log("ensureNsg: échec création NSG '$nsgName' pour '$vmName'", 'WARN');
            return false;
        }

        // Attacher le NSG à la NIC de la VM
        $nicUrl = "https://management.azure.com/subscriptions/{$this->subscriptionId}"
                . "/resourceGroups/$computeRg/providers/Microsoft.Network/networkInterfaces/$vmName"
                . "?api-version=2023-09-01";
        $nic = $this->curl('GET', $nicUrl);

        if (empty($nic['id'])) {
            dtl_log("ensureNsg: NIC '$vmName' non trouvée dans '$computeRg'", 'WARN');
            return false;
        }

        // Mettre à jour la NIC avec le NSG
        $nic['properties']['networkSecurityGroup'] = ['id' => $nsgId];
        $this->curl('PUT', $nicUrl, $nic);

        dtl_log("NSG '$nsgName' créé et attaché à la NIC de '$vmName' (RG: $computeRg)");
        return true;
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

    // ── Générer le nom de VM (max 15 car., alphanumérique + tiret) ────────────
    public static function buildVmName(string $username, string $tpCode): string {
        $clean = preg_replace('/[^a-z0-9]/', '', strtolower($username));
        $tp    = strtolower(str_replace(['-', '_'], '', $tpCode));
        $name  = 'vm-' . substr($clean, 0, 5) . '-' . substr($tp, 0, 7);
        return substr($name, 0, 15);
    }
}

// ── Helpers globaux ────────────────────────────────────────────────────────────
function dtl_log(string $message, string $level = 'INFO'): void {
    if (defined('LOG_LEVEL') && LOG_LEVEL === 'ERROR' && $level !== 'ERROR') return;
    $line = sprintf("[%s][%s] %s\n", date('Y-m-d H:i:s'), $level, $message);
    if (defined('LOG_FILE') && LOG_FILE) {
        @file_put_contents(LOG_FILE, $line, FILE_APPEND | LOCK_EX);
    }
    if (defined('WP_DEBUG') && WP_DEBUG) error_log($line);
}

function dtl_json(array $data, int $httpCode = 200): void {
    http_response_code($httpCode);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
    exit;
}
