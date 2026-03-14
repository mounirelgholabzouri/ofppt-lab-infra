# CONTEXT.md — OFPPT-Lab Infrastructure
> Généré le 2026-03-14 | Branche : `feature/azure-devtestlab-deployment`
> Repo : https://github.com/mounirelgholabzouri/ofppt-lab-infra

---

## 1. Vue d'ensemble du projet

Déploiement de VMs de TP pour **OFPPT Academy** (plateforme LMS Moodle) via **Azure DevTest Labs**.
Les stagiaires lancent leurs VMs directement depuis la page du cours Moodle ; l'accès se fait via **ttyd** (terminal SSH dans le navigateur, port 7681).

### Trois méthodes de déploiement coexistent
| Méthode | Dossier | Statut |
|---------|---------|--------|
| Vagrant + VirtualBox | `vagrant/` | Fonctionnel (existant) |
| Terraform Azure | `azure/main.tf` | Fonctionnel (existant) |
| **Azure DevTest Labs** (en cours) | `azure/devtestlab/` | **En cours — voir §3** |

---

## 2. État Azure — Ressources déployées

**Subscription ID** : `b64ddf59-d9cf-4c48-8174-27962dfc261c`
**Resource Group** : `rg-ofppt-devtestlab`

| Ressource | Nom | Région | Statut |
|-----------|-----|--------|--------|
| DevTest Lab | `ofppt-lab-formation` | francecentral | ✅ Succeeded |
| KeyVault | `ofpptlabformation1208` | francecentral | ✅ Succeeded |
| Storage Account | `aofpptlabformation139` | francecentral | ✅ Succeeded |
| Virtual Network | `vnet-ofppt-dtl` | francecentral | ✅ Succeeded |
| Automation Account | `aa-ofppt-dtl-stop` | northeurope | ✅ Succeeded |
| Runbook | `StopVmsByDuration` | northeurope | ✅ **Published** |
| Schedule | `schedule-stop-4h` | northeurope | ✅ Enabled (Hourly) |
| VM de test | `test-vm-0314-1302` | francecentral | ✅ Succeeded |

### Détails Automation
- **Runbook** : `StopVmsByDuration` (PowerShell, état: **Published**)
  - Arrête les VMs DTL tournant depuis plus de 4 heures
  - Utilise Managed Identity (`Connect-AzAccount -Identity`)
- **Schedule** : `schedule-stop-4h` (toutes les heures, prochain run: `2026-03-15T00:30:00Z`)
- **Job Schedule** ID: `92bb5452-00a6-4e83-9a43-b23514800168` (runbook lié au schedule)

### VNet Lab
- **VNet** : `vnet-ofppt-dtl` (10.0.0.0/16)
- **Subnet** : `subnet-ofppt-dtl` (10.0.0.0/24)
- Associé au lab avec `allowPublicIp = Allow` et `useInVmCreationPermission = Allow`

### Formules DTL (état Failed — à corriger)
| Formule | Filière |
|---------|---------|
| `OFPPT-Cloud-Computing` | Cloud (Docker, Terraform, kubectl, Azure CLI) |
| `OFPPT-Reseau-Infrastructure` | Réseau (Wireshark, FRRouting, OpenVPN) |
| `OFPPT-Cybersecurite` | Cyber (Metasploit, Nmap, sqlmap, DVWA) |

> Les formules ont un état `Failed` (probablement lié aux artifacts). La création de VM directe avec image gallery fonctionne.

---

## 3. Tâches — État détaillé

### ✅ TERMINÉ
- [x] **ARM Template déployé** (`arm_lab_template.json`) — lab + policies + formulas + schedule 23:59
- [x] **Automation Account créé** (`aa-ofppt-dtl-stop`, northeurope)
- [x] **Managed Identity activée** + rôle Contributor assigné au lab
- [x] **Runbook `StopVmsByDuration` Published** (contenu uploadé + publié via REST)
- [x] **Schedule `schedule-stop-4h`** créé (Hourly, API version 2022-08-08, format `+00:00`)
- [x] **Job Schedule** créé — runbook lié au schedule
- [x] **VNet `vnet-ofppt-dtl`** créé et associé au lab
- [x] **VM de test créée** (`test-vm-0314-1302`, Ubuntu 22.04, Standard_B2s)
- [x] **Intégration Moodle** — tous les fichiers PHP créés :
  - `config.php` — credentials SP + catalog 12 TPs
  - `azure_dtl_api.php` — classe AzureDTLApi (OAuth2 + CRUD VM)
  - `launch_tp.php` — page HTML complète (iframe ttyd, timer 4h, polling)
  - `status.php` — endpoint AJAX avec HMAC token
  - `install.sh` — script installation sur serveur Moodle
  - `setup_moodle_activities.php` — création activités Moodle en CLI

### ⚠️ EN COURS / À FAIRE
- [ ] **Corriger les formules DTL** (état `Failed`) — redéployer via `az lab formula create` ou corriger le JSON artifact source
- [ ] **Créer le Service Principal Azure** pour l'intégration PHP Moodle
  ```bash
  az ad sp create-for-rbac --name "sp-ofppt-moodle-dtl" \
    --role "DevTest Labs User" \
    --scopes "/subscriptions/b64ddf59.../resourceGroups/rg-ofppt-devtestlab/providers/Microsoft.DevTestLab/labs/ofppt-lab-formation"
  ```
  → Mettre les credentials dans `moodle/devtestlab_integration/config.php`
- [ ] **Déployer l'intégration Moodle** sur le serveur (`install.sh` + `setup_moodle_activities.php`)
- [ ] **Tester SSH ttyd** sur la VM de test (port 7681)
- [ ] **Git commit + push** des fichiers non commités (voir §4)

---

## 4. Fichiers non commités (git status)

```
M  azure/devtestlab/list_images.ps1
M  azure/devtestlab/test_vm.ps1
?? azure/devtestlab/check_vnet_and_create_vm.ps1
?? azure/devtestlab/setup_vnet.ps1
?? azure/devtestlab/check_status.ps1           (nouveau)
?? azure/devtestlab/automation/publish_runbook.ps1
?? azure/devtestlab/automation/create_schedule.ps1
```

**Commande pour tout commiter :**
```bash
cd C:\Users\Administrateur\Desktop\ofppt-lab
git add azure/devtestlab/
git commit -m "feat(dtl): VNet + Runbook Published + Schedule + VM test OK"
git push origin feature/azure-devtestlab-deployment
```

---

## 5. Architecture fichiers DevTest Labs

```
azure/devtestlab/
├── arm_lab_template.json          # Template ARM principal (lab + policies + formulas)
├── deploy_arm.ps1                 # Script déploiement ARM
├── deploy_devtestlab.sh           # CLI wrapper (deploy/status/destroy)
├── add_stagiaires.sh              # Enrôlement stagiaires (CSV / email / interactif)
├── runbook_stop_by_duration.ps1   # Code PowerShell du runbook Azure Automation
├── setup_vnet.ps1                 # Création + association VNet au lab
├── test_vm.ps1                    # Test création VM (Ubuntu 22.04 gallery)
├── check_status.ps1               # Vérification état complet du lab
├── list_images.ps1                # Liste images gallery disponibles
├── check_vnet_and_create_vm.ps1   # Combo vnet check + création VM
├── automation/
│   ├── setup_runbook_final.ps1    # Création runbook (corrigé — sans Unicode)
│   ├── publish_runbook.ps1        # Upload contenu + publication runbook
│   ├── create_schedule.ps1        # Création schedule (API 2022-08-08)
│   └── deploy_automation.ps1      # Déploiement compte Automation
├── formulas/
│   ├── formula-cloud.json
│   ├── formula-reseau.json
│   └── formula-cyber.json
└── artifacts/
    ├── cloud-tools/install.sh     # Docker, Terraform, kubectl + ttyd
    ├── reseau-tools/install.sh    # Wireshark, FRRouting + ttyd
    └── cyber-tools/install.sh     # Metasploit, Nmap + ttyd

moodle/devtestlab_integration/
├── config.php                     # Config SP Azure + catalog TPs
├── azure_dtl_api.php              # Classe API Azure (OAuth2 + VM lifecycle)
├── launch_tp.php                  # Page lanceur TP (iframe ttyd + timer)
├── status.php                     # Endpoint AJAX polling VM status
├── install.sh                     # Install sur serveur Moodle
└── setup_moodle_activities.php    # CLI Moodle — création activités
```

---

## 6. Paramètres clés

| Paramètre | Valeur |
|-----------|--------|
| Subscription | `b64ddf59-d9cf-4c48-8174-27962dfc261c` |
| Resource Group | `rg-ofppt-devtestlab` |
| Lab | `ofppt-lab-formation` (francecentral) |
| Automation Account | `aa-ofppt-dtl-stop` (northeurope — Free Trial limit) |
| VNet | `vnet-ofppt-dtl` / subnet `subnet-ofppt-dtl` |
| SSH Key | `C:\Users\Administrateur\.ssh\ofppt_azure` |
| ttyd Port | `7681` |
| Durée max VM | **4 heures** |
| Max VMs/stagiaire | **3** |
| Max VMs/lab | **30** |
| Auto-shutdown safety | 23:59 (en plus de la limite 4h par runbook) |
| Az CLI path | `C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd` |

---

## 7. Points techniques importants (leçons apprises)

1. **Encoding PowerShell** : Toujours écrire les scripts PS1 via l'outil Write — les caractères Unicode (em-dash `─`, tirets spéciaux) causent `Le terminateur " est manquant`.
2. **`az rest` + body** : Utiliser des fichiers temp JSON (`@$file`) + `--headers "Content-Type=application/json"` — passer le JSON inline via PowerShell échoue.
3. **Schedule Azure Automation** : Utiliser API version `2022-08-08` (pas `2023-11-01`) et format `+00:00` (pas `Z`) pour le `startTime`.
4. **Automation Account région** : Free Trial n'autorise pas francecentral → utiliser `northeurope`.
5. **Formules DTL** : Noms déployés = `OFPPT-Cloud-Computing`, `OFPPT-Reseau-Infrastructure`, `OFPPT-Cybersecurite` (pas `cloud-tools`).
6. **VNet obligatoire** : Le lab ne fournit pas de VNet par défaut via ARM — créer `vnet-ofppt-dtl` + subnet + association via REST avant toute création VM.
7. **Gallery images** : Utiliser `"Ubuntu Server 22.04 LTS"` avec `--image-type gallery`.

---

## 8. Prochaine session — Reprendre ici

```
ETAPE SUIVANTE : Git commit de tous les fichiers non commités
puis : Créer le Service Principal pour Moodle
puis : Corriger les formules DTL (état Failed)
puis : Tester SSH ttyd sur la VM test-vm-0314-1302
```

**Commandes de reprise rapides :**
```powershell
# 1. Vérifier état Azure
powershell -ExecutionPolicy Bypass -File azure\devtestlab\check_status.ps1

# 2. Tester création VM
powershell -ExecutionPolicy Bypass -File azure\devtestlab\test_vm.ps1

# 3. Créer Service Principal Moodle
$az = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
& $az ad sp create-for-rbac --name "sp-ofppt-moodle-dtl" --role "DevTest Labs User" `
  --scopes "/subscriptions/b64ddf59-d9cf-4c48-8174-27962dfc261c/resourceGroups/rg-ofppt-devtestlab/providers/Microsoft.DevTestLab/labs/ofppt-lab-formation"
```
