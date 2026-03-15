# CLAUDE.md — OFPPT-Lab Infrastructure
> Mis à jour le 2026-03-15 (session 11) | Branche : `feature/azure-devtestlab-deployment`

## 0. Instructions Claude (TOUJOURS RESPECTER)

- **Exécuter toutes les commandes directement** — ne jamais demander à l'utilisateur de lancer quoi que ce soit.
- Agir de manière autonome du début à la fin de chaque tâche.

---
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

### Intégration Moodle — Déployée sur Vagrant (sessions 4+5) ✅
- [x] Service Principal `sp-ofppt-moodle-dtl` créé + rôles assignés
- [x] **Contributor subscription-level** assigné au SP (nécessaire pour les compute RGs DTL auto-créés)
- [x] `config.php` — credentials SP réels intégrés + `SetEnv` Apache configuré
- [x] `azure_dtl_api.php` — classe API Azure (OAuth2 + VM lifecycle) — **déployée et testée sur Vagrant**
- [x] `launch_tp.php` — page lanceur TP (iframe ttyd + timer 4h + design OFPPT Academy)
- [x] `status.php` — endpoint AJAX polling VM status (vérifie `ready && ttydReady`)
- [x] `install.sh` — script installation sur serveur Moodle
- [x] `setup_moodle_activities.php` — création activités Moodle en CLI
- [x] **Moodle login** fonctionnel — reset password via `update_internal_user_password()`
- [x] **Token Azure obtenu** — fix `http_build_query` separator (commité 96bc020)
- [x] **VM `vm-admin-cc101t` créée via PHP API** — Running, NSG attaché, port 22 ouvert ✅

### État VM de test Moodle (session 7)
- VM Name : `vm-admin-cc101t`
- FQDN : `vm-admin-cc101t.francecentral.cloudapp.azure.com`
- IP : `20.216.128.34` (recréée en session 7)
- Compute RG : `ofppt-lab-formation-vm-admin-cc101t-017751`
- Port 22 (SSH) : **OUVERT** ✅
- Port 7681 (ttyd) : **OUVERT** ✅ — ttyd 1.7.3 installé + service systemd actif
- `status.php` : `ready:true` + `ttydReady:true` **validé** ✅

### Comportement ttyd (session 6)
- `launch_tp.php` : ttyd s'ouvre dans un **nouvel onglet** automatiquement (plus d'iframe)
- Bouton "Ouvrir le terminal" + "Ré-ouvrir" disponibles sur la page Moodle
- La page Moodle reste ouverte avec timer 4h et infos VM

---

## 4. Ce qui RESTE À FAIRE ⚠️

### Priorité 0 — ✅ COMPLÉTÉ (session 7)
- [x] **Validation end-to-end `launch_tp.php`** sur Vagrant — `ready:true` + `ttydReady:true` confirmé
- [x] **VM recréée** `vm-admin-cc101t` (RG: `ofppt-lab-formation-vm-admin-cc101t-017751`, IP: `20.216.128.34`)
  - ttyd 1.7.3 installé + service systemd actif, port 7681 LISTEN
  - NSG créé (`nsg-vm-admin-cc101t`) et attaché à la NIC — SSH:22 + ttyd:7681 + HTTP:80 OUVERTS
- [x] **launch_tp.php sync** sur Vagrant — version session 6 (nouvel onglet)
- [x] **Fix popup blocker** dans `launch_tp.php` — message d'aide si popup bloqué par le navigateur
- [x] **Extension PHP mysqli** activée sur Vagrant (phpenmod mysqli)
- [x] **`deploy_prod.sh`** — nouveau script déploiement prod sécurisé (génère TP_SECRET_KEY aléatoire)

### Priorité 1 — Artifact ttyd (pour futures VMs)
- [x] **Artifacts mis à jour** `cloud-tools/install.sh`, `reseau-tools/install.sh`, `cyber-tools/install.sh`
  - ttyd (version latest via GitHub API) + service systemd présents dans les 3 scripts ✅

### Priorité 2 — ARM Template + Policy
- [ ] **Mettre à jour `arm_lab_template.json`** :
  - Remplacer `Standard_B2s` par `Standard_D2s_v3` comme taille par défaut des formules
  - Ajouter création NSG avec rules SSH+ttyd dans le template

### Priorité 3 — Déploiement Moodle prod
- [ ] **Déployer intégration Moodle** sur le serveur :
  ```bash
  bash moodle/devtestlab_integration/install.sh
  php moodle/devtestlab_integration/setup_moodle_activities.php
  ```

### Priorité 4 — Script création VM amélioré
- [x] **Script `create_vm_with_nsg.ps1`** — VM + NSG + attachement NIC en une seule opération ✅
  - Paramètres : `-VmPrefix`, `-VmSize`, `-Formula`, `-WaitReady`
  - Découverte automatique du compute RG, fix ConvertFrom-Json (IndexOf) (session 8)

---

## 5. Prochaine étape précise

```
SESSION 8 — COMPLETEE ✅
1. Fix ConvertFrom-Json (IndexOf) dans create_vm_with_nsg.ps1 (leçon 11)
2. CLAUDE.md mis à jour : Priorité 1 (artifacts) + Priorité 4 (create_vm_with_nsg.ps1) cochés

SESSION 9 — COMPLETEE ✅
1. Fix encoding PS1 (em-dash → ASCII) dans create_vm_with_nsg.ps1
2. Fix formulaId → GET formule + injecter galleryImageReference (leçon 17)
3. VM tp-0315-0659 creee avec formule OFPPT-Cloud-Computing — Succeeded
   - NSG cree + attache NIC, port 22 + 7681 OUVERTS
   - ttyd 1.7.3 installe + service systemd actif

SESSION 10 — COMPLETEE ✅
1. Migration Moodle Vagrant -> Azure (VM OFPPT-ACADEMY-LMS, northeurope, D2s_v3)
   - IP : 40.115.121.107 | FQDN : ofppt-academy-lms.northeurope.cloudapp.azure.com
   - RG : rg-ofppt-moodle-prod | SSH : azureofppt@40.115.121.107
   - Moodle 4.5.10 migre (DB moodledb 494 tables + moodledata)
   - URL : http://40.115.121.107/moodle
2. Integration DevTest Labs deployee (deploy_prod.sh) -- Token Azure OK

SESSION 11 — COMPLETEE ✅
1. SSH vers VM Moodle prod repare (clé ofppt_azure ajoutée via run-command)
2. Apache SetEnv configure (AZURE_CLIENT_SECRET, TP_SECRET_KEY, MOODLE_DB_PASS, etc.)
   → /etc/apache2/sites-enabled/000-default.conf
3. cookiesecure=0 dans mdl_config (fix login HTTP)
4. Shortnames cours mis a jour (CC101, CC302, NET101, NET201, NET301, CYB101, CYB201, CYB301)
5. setup_moodle_activities.php réécrit (insertion directe DB, plus add_moduleinfo)
   → 12 activités TP créées dans 8 cours Moodle
6. Validation end-to-end launch_tp.php + status.php :
   - launch_tp.php : HTTP 200, page OFPPT Academy chargée, VM vm-admin-cc101t détectée
   - status.php : ready:true + ttydReady:true validé ✅
7. VM vm-admin-cc101t redémarrée (était deallocated), SSH + ttyd OK

SESSION 12 — ETAPES :
1. (Optionnel) Configurer DNS moodle.ofppt-academy.ma -> 40.115.121.107
2. (Optionnel) HTTPS avec Let's Encrypt : certbot --apache -d moodle.ofppt-academy.ma
3. Test end-to-end complet avec un stagiaire réel (login, lancer TP, accéder ttyd)
4. Nettoyage VM vm-admin-cc101t (deallocate pour économiser quota PIP)
```

**Commandes de reprise rapides :**
```powershell
# Vérifier état Azure complet
powershell -ExecutionPolicy Bypass -File azure\devtestlab\check_status.ps1

# Tester SSH + ttyd sur VM existante
powershell -ExecutionPolicy Bypass -File azure\devtestlab\check_pip_and_ssh.ps1

# Ouvrir page de test Moodle (après vagrant up vm-cloud)
# http://localhost:8080/moodle/local/devtestlab/launch_tp.php?tp=CC101-TP1

# Re-créer NSG si la VM a été recréée
powershell -ExecutionPolicy Bypass -File azure\devtestlab\create_nsg_vm_admin.ps1

# Sync fichiers PHP sur Vagrant (après modifications locales)
scp -P 2222 -i "$env:USERPROFILE\.vagrant.d\insecure_private_keys\vagrant.key.rsa" `
  -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o PubkeyAcceptedKeyTypes=+ssh-rsa `
  moodle\devtestlab_integration\launch_tp.php vagrant@127.0.0.1:/tmp/ltp.php
vagrant ssh vm-cloud -- "sudo cp /tmp/ltp.php /var/www/html/moodle/local/devtestlab/launch_tp.php && sudo chown www-data:www-data /var/www/html/moodle/local/devtestlab/launch_tp.php"
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
12. **Moodle `arg_separator.output`** : `lib/setup.php` ligne 818 fait `ini_set('arg_separator.output', '&amp;')` — casse `http_build_query()` qui produit `&amp;` au lieu de `&` → Azure reçoit un seul paramètre malformé → AADSTS7000216. Fix : `http_build_query([...], '', '&')`.
13. **HTTP 411 Length Required** : Azure REST API exige `Content-Length: 0` sur les POST sans body (`/start`, `/stop`) → `curl_setopt($ch, CURLOPT_POSTFIELDS, '')` pour les POST avec `$body === null`.
14. **RBAC DTL** : Le rôle "DevTest Labs User" NE comprend PAS `Microsoft.DevTestLab/labs/virtualMachines/write` → assigner **Contributor au niveau subscription** (les compute RGs sont auto-créés par DTL et ne peuvent pas être prédits).
15. **`status.php` ttyd check** : `isTtydReachable()` vérifie via `fsockopen` que le port 7681 répond AVANT de retourner `ready:true` → si ttyd pas installé, la page reste bloquée à l'étape 2 même si la VM est Running.
16. **Debug lines à ne jamais commiter** : Les lignes `dtl_log('[DEBUG] ... client_secret ...')` exposent la clé en clair dans les logs — toujours supprimer avant commit.
17. **DTL `formulaId` inexistant dans l'API** : L'API DTL ne supporte pas `formulaId` dans le body de création VM → `MissingRequiredProperties`. Il faut GET la formule, extraire `formulaContent.properties.galleryImageReference` et l'injecter dans le body VM. Le `storageType` de la formule est aussi à récupérer.
18. **`add_moduleinfo()` Moodle** : Échoue en CLI avec "active database transaction detected" → utiliser insertion directe dans `mdl_url` + `mdl_course_modules` + mise à jour `sequence` dans `mdl_course_sections` + `rebuild_course_cache()`.
19. **`cookiesecure=1` Moodle** : Si Moodle est en HTTP (pas HTTPS), les cookies session ne sont pas envoyés → login redirige indéfiniment. Fix : `UPDATE mdl_config SET value='0' WHERE name='cookiesecure'`.
20. **SSH authorized_keys VM prod** : La VM Moodle OFPPT-ACADEMY-LMS n'avait que la clé `Administrateur@PC-PORTABLE`. Ajouter la clé `ofppt_azure.pub` via `az vm run-command invoke` pour accès SSH depuis Claude Code.
21. **DTL vmExists vs Azure VM state** : La DTL API `vmExists()` retourne true même si la VM sous-jacente est deallocated (état Azure réel ≠ état DTL). Toujours vérifier `getVmStatus()` pour le power state réel. Le runbook `StopVmsByDuration` deallocate les VMs sans les supprimer du DTL.

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
