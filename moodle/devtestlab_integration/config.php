<?php
// =============================================================================
// config.php — Configuration de l'intégration Moodle ↔ Azure DevTest Labs
// =============================================================================
// Fichier à copier sur le serveur Moodle dans :
//   /var/www/html/moodle/local/devtestlab/
// ou dans un répertoire web protégé accessible par PHP.
//
// ⚠️  NE JAMAIS committer ce fichier avec de vraies valeurs !
//     Utiliser des variables d'environnement en production.
// =============================================================================

// ── Azure Service Principal ──────────────────────────────────────────────────
define('AZURE_TENANT_ID',       getenv('AZURE_TENANT_ID')       ?: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx');
define('AZURE_CLIENT_ID',       getenv('AZURE_CLIENT_ID')       ?: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx');
define('AZURE_CLIENT_SECRET',   getenv('AZURE_CLIENT_SECRET')   ?: 'votre-secret-ici');
define('AZURE_SUBSCRIPTION_ID', getenv('AZURE_SUBSCRIPTION_ID') ?: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx');

// ── Azure DevTest Labs ────────────────────────────────────────────────────────
define('DTL_RESOURCE_GROUP', 'rg-ofppt-devtestlab');
define('DTL_LAB_NAME',       'ofppt-lab-formation');
define('DTL_LOCATION',       'francecentral');
define('DTL_ADMIN_USER',     'azureofppt');

// Mot de passe SSH généré dynamiquement par VM (format: TP@<username>2024!)
// La clé publique SSH du lab est utilisée si définie
define('DTL_SSH_PUBLIC_KEY', getenv('DTL_SSH_PUBLIC_KEY') ?: '');

// Formules DTL par filière (doivent correspondre aux formules créées dans le lab)
define('DTL_FORMULAS', [
    'cloud'  => 'OFPPT-Cloud-Computing',
    'reseau' => 'OFPPT-Reseau-Infrastructure',
    'cyber'  => 'OFPPT-Cybersecurite',
]);

// Port ttyd (SSH web) installé sur chaque VM
define('TTYD_PORT', 7681);

// ── Moodle ────────────────────────────────────────────────────────────────────
define('MOODLE_ROOT',       '/var/www/html/moodle');
define('MOODLE_WWWROOT',    getenv('MOODLE_WWWROOT') ?: 'https://moodle.ofppt-academy.ma');
define('MOODLE_DB_HOST',    getenv('MOODLE_DB_HOST') ?: 'localhost');
define('MOODLE_DB_NAME',    getenv('MOODLE_DB_NAME') ?: 'moodle');
define('MOODLE_DB_USER',    getenv('MOODLE_DB_USER') ?: 'moodleuser');
define('MOODLE_DB_PASS',    getenv('MOODLE_DB_PASS') ?: 'MoodlePass@2024!');

// ── Sécurité ──────────────────────────────────────────────────────────────────
// Clé secrète pour signer les tokens de session du lanceur TP
define('TP_SECRET_KEY', getenv('TP_SECRET_KEY') ?: 'ofppt-tp-secret-key-2024-change-me');

// Durée de vie d'une VM éphémère (secondes) — doit correspondre au runbook
define('VM_MAX_LIFETIME_SECONDS', 4 * 3600); // 4 heures

// Délai max d'attente du démarrage de VM (secondes)
define('VM_BOOT_TIMEOUT', 600); // 10 minutes

// ── Logging ───────────────────────────────────────────────────────────────────
define('LOG_FILE',  '/var/log/ofppt-devtestlab.log');
define('LOG_LEVEL', 'INFO'); // DEBUG, INFO, WARN, ERROR

// ── Mapping TP → Filière ──────────────────────────────────────────────────────
// Associe chaque code TP à sa filière et à la formule DTL correspondante
define('TP_CATALOG', [
    // Cloud Computing
    'CC101-TP1' => ['filiere' => 'cloud',  'label' => 'Docker — Premiers conteneurs',          'vm_size' => 'Standard_D4s_v3'],
    'CC101-TP2' => ['filiere' => 'cloud',  'label' => 'Docker Compose — Application multi-conteneurs', 'vm_size' => 'Standard_D4s_v3'],
    'CC302-TP1' => ['filiere' => 'cloud',  'label' => 'Kubernetes — Déploiement de pods',      'vm_size' => 'Standard_D4s_v3'],
    'CC302-TP2' => ['filiere' => 'cloud',  'label' => 'Terraform — Infrastructure as Code',   'vm_size' => 'Standard_D4s_v3'],
    // Réseau & Infrastructure
    'NET101-TP1'=> ['filiere' => 'reseau', 'label' => 'Wireshark — Analyse de trames',        'vm_size' => 'Standard_D2s_v3'],
    'NET101-TP2'=> ['filiere' => 'reseau', 'label' => 'OSPF — Configuration du routage dynamique', 'vm_size' => 'Standard_D2s_v3'],
    'NET201-TP1'=> ['filiere' => 'reseau', 'label' => 'VPN OpenVPN — Tunnel sécurisé',        'vm_size' => 'Standard_D2s_v3'],
    'NET301-TP1'=> ['filiere' => 'reseau', 'label' => 'WireGuard — VPN moderne',              'vm_size' => 'Standard_D2s_v3'],
    // Cybersécurité
    'CYB101-TP1'=> ['filiere' => 'cyber',  'label' => 'Nmap — Reconnaissance réseau',          'vm_size' => 'Standard_D4s_v3'],
    'CYB101-TP2'=> ['filiere' => 'cyber',  'label' => 'Metasploit — Exploitation de base',     'vm_size' => 'Standard_D4s_v3'],
    'CYB201-TP1'=> ['filiere' => 'cyber',  'label' => 'DVWA — Tests d\'injection SQL',         'vm_size' => 'Standard_D4s_v3'],
    'CYB301-TP1'=> ['filiere' => 'cyber',  'label' => 'Volatility — Analyse forensique',       'vm_size' => 'Standard_D4s_v3'],
]);
