# CLAUDE.md — OFPPT-Lab Infrastructure
> Mis à jour le 2026-03-14 (session 3) | Branche : `feature/azure-devtestlab-deployment`
> Repo : https://github.com/mounirelgholabzouri/ofppt-lab-infra

---

## 1. Vue d'ensemble du projet

Déploiement de VMs de TP pour **OFPPT Academy** (plateforme LMS Moodle) via **Azure DevTest Labs**.
Les stagiaires lancent leurs VMs depuis la page du cours Moodle ; l'accès se fait via **ttyd** (terminal SSH dans le navigateur, port 7681).

---

## 2. Paramètres clés

| Paramètre | Valeur |
|-----------|--------|
| Subscription | `b64ddf59-d9cf-4c48-8174-27962dfc261c` |
| Resource Group | `rg-ofppt-devtestlab` |
| Lab | `ofppt-lab-formation` (francecentral) |
| Automation Account | `aa-ofppt-dtl-stop` (northeurope) |
| VNet | `vnet-ofppt-dtl` / subnet `subnet-ofppt-dtl` (10.0.0.0/24) |
| SSH Key | `C:\Users\Administrateur\.ssh\ofppt_azure` |
| ttyd Port | `7681` |
| Durée max VM | 4 heures (runbook StopVmsByDuration) |
| Max VMs/stagiaire | 3 |
| Max VMs/lab | 30 |
| Az CLI path | `C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd` |
| Taille VM par défaut | `Standard_D2s_v3` (Standard_B2s indisponible en France Central) |
| Username VM | `azureofppt` |
| Password VM | `Ofppt@lab2026!` |

**Service Principal Moodle** :
- SP Name: `sp-ofppt-moodle-dtl`
- Client ID: `ae328530-c971-44a9-98dc-443f0618b4fc`
- Tenant: `687d3cdf-7038-4560-a9f5-b3f0403eb863`
- Credentials: `moodle/devtestlab_integration/.env.local` (non commité)

---

## 3. État complet — Ce qui est FAIT ✅

### Infrastructure Azure (toutes ressources Succeeded)
- [x] **DevTest Lab** `ofppt-lab-formation` — francecentral
- [x] **KeyVault** `ofpptlabformation1208` — francecentral
- [x] **Storage Account** `aofpptlabformation139` — francecentral
- [x] **VNet** `vnet-ofppt-dtl` (10.0.0.0/16) + subnet + association lab
- [x] **Automation Account** `aa-ofppt-dtl-stop` (northeurope)
- [x] **Runbook** `StopVmsByDuration` — Published (arrête VMs >4h)
- [x] **Schedule** `schedule-stop-4h` — Enabled (Hourly, lié au runbook)
- [x] **Formules DTL** (3) — toutes Succeeded :
  - `OFPPT-Cloud-Computing` (Docker, Terraform, kubectl, Azure CLI)
  - `OFPPT-Reseau-Infrastructure` (Wireshark, FRRouting, OpenVPN)
  - `OFPPT-Cybersecurite` (Metasploit, Nmap, sqlmap, DVWA)

### Création VM validée end-to-end
- [x] **VM de test** `tp-d2-0314-1401` — Succeeded, Standard_D2s_v3
  - FQDN: `tp-d2-0314-1401.francecentral.cloudapp.azure.com`
  - IP: `20.111.47.151`
  - NSG créé et attaché à la NIC (rules: Allow-SSH:22, Allow-ttyd:7681, Allow-HTTP:80)
  - **Port 22 (SSH) : OUVERT** ✅
  - **Port 7681 (ttyd) : OUVERT** ✅ — ttyd 1.7.3 installé, service systemd actif
  - URL ttyd: `http://tp-d2-0314-1401.francecentral.cloudapp.azure.com:7681`

### Intégration Moodle (fichiers créés, non déployés)
- [x] Service Principal `sp-ofppt-moodle-dtl` créé + rôles assignés
- [x] `config.php` — credentials SP réels intégrés
- [x] `azure_dtl_api.php` — classe API Azure (OAuth2 + VM lifecycle)
- [x] `launch_tp.php` — page lanceur TP (iframe ttyd + timer 4h)
- [x] `status.php` — endpoint AJAX polling VM status
- [x] `install.sh` — script installation sur serveur Moodle
- [x] `setup_moodle_activities.php` — création activités Moodle en CLI

---

## 4. Ce qui RESTE À FAIRE ⚠️

### Priorité 1 — Artifact ttyd (pour futures VMs)
- [ ] **Mettre à jour les artifacts** `cloud-tools/install.sh`, `reseau-tools/install.sh`, `cyber-tools/install.sh`
  - Ajouter installation ttyd 1.7.3 + service systemd
  - Ajouter les règles NSG dans le script de création VM

### Priorité 2 — ARM Template + Policy
- [ ] **Mettre à jour `arm_lab_template.json`** :
  - Remplacer `Standard_B2s` par `Standard_D2s_v3` comme taille par défaut des formules
  - Ajouter création NSG avec rules SSH+ttyd dans le template

### Priorité 3 — Déploiement Moodle
- [ ] **Déployer intégration Moodle** sur le serveur :
  ```bash
  bash moodle/devtestlab_integration/install.sh
  php moodle/devtestlab_integration/setup_moodle_activities.php
  ```

### Priorité 4 — Script création VM amélioré
- [ ] **Script `create_vm_with_nsg.ps1`** — créer VM + NSG + attacher NSG en une seule opération

---

## 5. Prochaine étape précise

```
ETAPE SUIVANTE :
1. Mettre à jour les artifacts (install.sh) pour inclure ttyd + NSG auto
2. Mettre à jour arm_lab_template.json (taille D2s_v3 + NSG dans template)
3. Créer script unifié create_vm_with_nsg.ps1
4. Git commit + push
5. Déployer intégration Moodle sur serveur
```

**Commandes de reprise rapides :**
```powershell
# Vérifier état Azure complet
powershell -ExecutionPolicy Bypass -File azure\devtestlab\check_status.ps1

# Créer une nouvelle VM (D2s_v3) + NSG
powershell -ExecutionPolicy Bypass -File azure\devtestlab\create_vm_with_nsg.ps1

# Tester SSH + ttyd sur VM existante
powershell -ExecutionPolicy Bypass -File azure\devtestlab\check_pip_and_ssh.ps1
```

---

## 6. Leçons techniques importantes

1. **Encoding PS1** : Toujours écrire via l'outil Write — les Unicode (em-dash `─`) causent `Le terminateur " est manquant`.
2. **`az rest` body** : Toujours via fichier temp JSON (`@$file`) + `--headers "Content-Type=application/json"`.
3. **Schedule Automation** : API `2022-08-08` + format `+00:00` (pas `Z`) pour startTime.
4. **Automation Account région** : Free Trial → northeurope (pas francecentral).
5. **Formules DTL** : Utiliser DTL VNet ID (`GET /virtualnetworks`) + no artifacts pour éviter Failed.
6. **VNet DTL** : ID DTL-scoped (pas Azure Network ID) → récupérer via `GET .../virtualnetworks`.
7. **SKU** : `Standard_B2s` = SkuNotAvailable en France Central → utiliser `Standard_D2s_v3`.
8. **PIP quota** : Free Trial = 3 PIPs max — nettoyer les VMs Failed avec `cleanup_failed_vms.ps1`.
9. **NSG obligatoire** : Les VMs DTL n'ont pas de NSG par défaut → ports 22 et 7681 bloqués → créer NSG + attacher à la NIC avec `az network nic update --network-security-group`.
10. **ttyd** : Installer via `curl` depuis GitHub releases (v1.7.3) + service systemd, user=azureofppt.
11. **`ConvertFrom-Json`** : Échoue sur output mixte WARNING+JSON → extraire JSON par `.IndexOf('{')`.

---

## 7. Architecture fichiers

```
azure/devtestlab/
├── arm_lab_template.json          # Template ARM principal
├── deploy_arm.ps1                 # Déploiement ARM
├── deploy_devtestlab.sh           # CLI wrapper
├── add_stagiaires.sh              # Enrôlement stagiaires
├── runbook_stop_by_duration.ps1   # Code runbook Azure Automation
├── setup_vnet.ps1                 # Création + association VNet
├── test_vm.ps1                    # Test création VM (basique)
├── test_vm_d2sv3.ps1              # Test création VM D2s_v3
├── test_vm_pass.ps1               # Test VM avec password
├── full_cleanup_and_test.ps1      # Cleanup + création VM complète
├── cleanup_failed_vms.ps1         # Nettoyage VMs Failed + orphan RGs
├── check_status.ps1               # Vérification état complet lab
├── check_nsg_and_fix.ps1          # Check + add NSG rules
├── check_nic_and_nsg.ps1          # Diagnostic NIC/NSG
├── check_pip_and_ssh.ps1          # Test SSH/ttyd + PIP details
├── create_nsg_for_vm.ps1          # Création NSG (standalone)
├── attach_nsg_to_nic.ps1          # Attacher NSG à NIC existante
├── install_ttyd.ps1               # Installation ttyd v1
├── install_ttyd_v2.ps1            # Installation ttyd v2 (step by step) ✅
├── diagnose_ssh.ps1               # Diagnostic SSH via run-command
├── debug_dtl_error.ps1            # Lecture activity log erreurs
├── find_available_size.ps1        # Lister SKUs disponibles
├── list_images.ps1                # Liste images gallery
├── check_vnet_and_create_vm.ps1   # VNet check + création VM
├── automation/
│   ├── setup_runbook_final.ps1
│   ├── publish_runbook.ps1
│   ├── create_schedule.ps1
│   └── deploy_automation.ps1
├── formulas/
│   ├── formula-cloud.json
│   ├── formula-reseau.json
│   └── formula-cyber.json
└── artifacts/
    ├── cloud-tools/install.sh     # À METTRE À JOUR avec ttyd
    ├── reseau-tools/install.sh    # À METTRE À JOUR avec ttyd
    └── cyber-tools/install.sh     # À METTRE À JOUR avec ttyd

moodle/devtestlab_integration/
├── config.php                     # Config SP Azure (credentials réels)
├── azure_dtl_api.php              # Classe API Azure
├── launch_tp.php                  # Page lanceur TP
├── status.php                     # Endpoint AJAX
├── install.sh                     # Installation Moodle server
├── setup_moodle_activities.php    # CLI Moodle
└── .env.local                     # Credentials SP (non commité)
```
