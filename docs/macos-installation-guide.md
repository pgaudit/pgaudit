# Guide d'installation de pgAudit pour PostgreSQL sur macOS

Ce guide fournit des instructions détaillées pour installer pgAudit sur macOS, y compris sur les systèmes Apple Silicon (processeurs ARM).

## Prérequis

- PostgreSQL installé via l'installateur Enterprise DB ou Homebrew
- Xcode Command Line Tools
- SDK macOS (installé avec Xcode Command Line Tools)
- Droits d'administration (sudo)

## Problèmes connus sur macOS

L'installation de pgAudit sur macOS, en particulier sur les machines Apple Silicon (M1/M2/M3), peut rencontrer plusieurs obstacles :

1. **Incompatibilité de SDK** : PostgreSQL peut avoir été compilé avec un SDK macOS différent de celui disponible sur votre système
2. **Problèmes d'architecture** : Différences entre x86_64 et arm64 sur les systèmes Apple Silicon
3. **Dépendances OpenSSL** : Chemins et versions d'OpenSSL différents entre les systèmes

## Installation sur macOS (Universal)

### Méthode 1 : Installation manuelle via source

Le script suivant automatise la compilation et l'installation de pgAudit sur macOS :

```bash
#!/bin/bash
# Script pour compiler pgAudit pour PostgreSQL sur macOS

set -e

# Vérification si le répertoire existe déjà
if [ ! -d "/tmp/pgaudit" ]; then
  # Cloner le dépôt pgAudit
  echo "Clonage du dépôt pgAudit..."
  mkdir -p /tmp/pgaudit
  cd /tmp/pgaudit
  git clone https://github.com/pgaudit/pgaudit.git .
  git checkout REL_16_STABLE  # Ajuster la version selon votre PostgreSQL
else
  cd /tmp/pgaudit
  git checkout REL_16_STABLE  # Ajuster la version selon votre PostgreSQL
fi

# Récupérer les informations de configuration PostgreSQL
PG_CONFIG=/Library/PostgreSQL/16/bin/pg_config  # Ajuster le chemin selon votre installation
PG_INCLUDEDIR=$($PG_CONFIG --includedir)
PG_PKGLIBDIR=$($PG_CONFIG --pkglibdir)
PG_SHAREDIR=$($PG_CONFIG --sharedir)
PG_CFLAGS=$($PG_CONFIG --cflags)
PG_CPPFLAGS=$($PG_CONFIG --cppflags)
PG_LDFLAGS=$($PG_CONFIG --ldflags)

# Configurer pour utiliser le SDK disponible 
# Trouver automatiquement le SDK le plus récent
SDK_PATH=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk | sort -V | tail -1)

echo "Compilation de pgAudit avec les options suivantes:"
echo "PG_INCLUDEDIR: $PG_INCLUDEDIR"
echo "PG_PKGLIBDIR: $PG_PKGLIBDIR"
echo "SDK_PATH: $SDK_PATH"

# Compiler pgAudit
echo "Compilation de pgAudit..."
make clean || true
make USE_PGXS=1 PG_CONFIG=$PG_CONFIG CFLAGS="$PG_CFLAGS -isysroot $SDK_PATH" CPPFLAGS="$PG_CPPFLAGS -isysroot $SDK_PATH" LDFLAGS="$PG_LDFLAGS -isysroot $SDK_PATH"

# Installer pgAudit
echo "Installation de pgAudit..."
sudo make install USE_PGXS=1 PG_CONFIG=$PG_CONFIG

# Vérifier si le module a été installé correctement
if [ -f "$PG_PKGLIBDIR/pgaudit.so" ] || [ -f "$PG_PKGLIBDIR/pgaudit.dylib" ]; then
  echo "Module pgaudit installé avec succès dans $PG_PKGLIBDIR"
else
  echo "Erreur: Module pgaudit non installé!"
  exit 1
fi

# Créer le fichier de contrôle s'il n'existe pas déjà
CONTROL_FILE="$PG_SHAREDIR/extension/pgaudit.control"
if [ ! -f "$CONTROL_FILE" ]; then
  echo "Création du fichier de contrôle pgaudit.control..."
  sudo bash -c "cat > $CONTROL_FILE << EOF
# pgAudit extension
comment = 'PostgreSQL Audit Extension'
default_version = '16.0'
module_pathname = '\$libdir/pgaudit'
relocatable = false
trusted = true
EOF"
fi

# Vérifier si le fichier de contrôle a été installé correctement
if [ -f "$CONTROL_FILE" ]; then
  echo "Fichier pgaudit.control installé avec succès dans $PG_SHAREDIR/extension"
else
  echo "Erreur: Fichier pgaudit.control non installé!"
  exit 1
fi

# Vérifier les fichiers SQL
SQL_DIR="$PG_SHAREDIR/extension"
if [ -f "$SQL_DIR/pgaudit--16.0.sql" ] || [ -f "$SQL_DIR/pgaudit--16.1.sql" ]; then
  echo "Fichiers SQL de pgAudit trouvés dans $SQL_DIR"
else
  echo "Avertissement: Aucun fichier SQL de pgAudit trouvé dans $SQL_DIR"
  
  # Création des fichiers SQL de base si nécessaires
  if [ ! -f "$SQL_DIR/pgaudit--16.0.sql" ]; then
    echo "Création d'un fichier SQL basique pour pgAudit 16.0..."
    sudo bash -c "cat > $SQL_DIR/pgaudit--16.0.sql << EOF
-- complains if script is sourced in psql, since it's not inside a transaction
\echo Use \"CREATE EXTENSION pgaudit\" to load this file. \quit

-- Empty SQL file for pgAudit 16.0
EOF"
  fi
fi

echo "Installation de pgAudit terminée!"
```

Sauvegardez ce script dans un fichier, rendez-le exécutable avec `chmod +x script.sh`, puis exécutez-le.

### Méthode 2 : Installation via Homebrew (recommandé si PostgreSQL est installé via Homebrew)

Si vous avez installé PostgreSQL via Homebrew, il est recommandé d'installer également pgAudit via Homebrew :

```bash
# Pour PostgreSQL 16 (ajustez le numéro de version selon votre installation)
brew install postgresql@16
brew install libpq

# Assurez-vous que les bons chemins sont dans votre PATH
echo 'export PATH="/opt/homebrew/opt/libpq/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc

# Installation de pgAudit via Homebrew (si disponible)
brew install pgaudit
```

## Configuration de pgAudit

Une fois pgAudit installé, vous devez le configurer dans PostgreSQL :

```bash
# Exemple de configuration pgAudit
cat << EOF > pgaudit_config.conf
# Charger pgAudit
shared_preload_libraries = 'pgaudit'

# Configuration de l'audit
pgaudit.log = 'ddl, write'       # Audit des instructions DDL et écriture
pgaudit.log_catalog = on         # Audit des objets du catalogue
pgaudit.log_parameter = on       # Inclure les arguments des requêtes
pgaudit.log_statement_once = on  # Log la requête une seule fois
pgaudit.log_level = 'log'        # Niveau de log
pgaudit.log_relation = on        # Log toutes les relations référencées

# Configuration de la journalisation standard
logging_collector = on                # Activer la collecte des logs
log_directory = 'pg_log'              # Répertoire des logs
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log' # Format du nom de fichier de log
log_line_prefix = '%m [%p] %q%u@%d ' # Format du préfixe de ligne
log_statement = 'none'                # Désactiver la journalisation standard des requêtes
EOF

# Ajouter la configuration à postgresql.conf
sudo bash -c "cat pgaudit_config.conf >> /Library/PostgreSQL/16/data/postgresql.conf"

# Créer le répertoire de logs si nécessaire
sudo mkdir -p /Library/PostgreSQL/16/data/pg_log
sudo chown postgres:postgres /Library/PostgreSQL/16/data/pg_log
sudo chmod 700 /Library/PostgreSQL/16/data/pg_log

# Redémarrer PostgreSQL
sudo -u postgres /Library/PostgreSQL/16/bin/pg_ctl restart -D /Library/PostgreSQL/16/data/
```

## Test de l'installation

Pour vérifier que pgAudit fonctionne correctement :

```sql
-- Exécuter dans psql
SELECT * FROM pg_available_extensions WHERE name = 'pgaudit';

-- Créer une base de données de test
CREATE DATABASE audit_test;
\c audit_test

-- Activer l'extension pgaudit
CREATE EXTENSION IF NOT EXISTS pgaudit;

-- Tester avec quelques requêtes
CREATE TABLE test_table (id int, name text);
INSERT INTO test_table VALUES (1, 'test');
SELECT * FROM test_table;
```

Vérifiez ensuite les logs d'audit :

```bash
sudo grep -i "AUDIT:" /Library/PostgreSQL/16/data/pg_log/postgresql-*.log
```

## Résolution des problèmes

### Problème : Le module pgaudit.so/dylib n'est pas trouvé

Vérifiez que le module a été installé au bon endroit :

```bash
ls -la $(/Library/PostgreSQL/16/bin/pg_config --pkglibdir)/pgaudit*
```

### Problème : Erreurs de chargement de l'extension

Vérifiez les logs PostgreSQL pour plus de détails :

```bash
sudo tail -n 100 /Library/PostgreSQL/16/data/pg_log/postgresql-*.log
```

### Problème : Incompatibilité d'architecture (Apple Silicon)

Si vous recevez des erreurs liées à l'architecture, assurez-vous que PostgreSQL et le module pgAudit sont compilés pour la même architecture :

```bash
# Vérifier l'architecture de PostgreSQL
file /Library/PostgreSQL/16/bin/postgres

# Vérifier l'architecture de pgAudit
file $(/Library/PostgreSQL/16/bin/pg_config --pkglibdir)/pgaudit.so
```

Sur Apple Silicon, vous pourriez avoir besoin de forcer la compilation pour l'architecture arm64 :

```bash
CFLAGS="-target arm64-apple-macos11" make USE_PGXS=1 PG_CONFIG=/Library/PostgreSQL/16/bin/pg_config
```

## Conclusion

L'installation de pgAudit sur macOS, en particulier sur les systèmes Apple Silicon, présente quelques défis spécifiques liés aux différences d'architecture et de SDK. Les méthodes présentées dans ce guide devraient vous permettre de surmonter ces obstacles et d'utiliser pgAudit efficacement pour l'audit de vos bases de données PostgreSQL."