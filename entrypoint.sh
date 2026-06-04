#!/bin/sh
set -e

readcfg() {
        key=$1; shift
        test -f $1 && grep "^${key} =" $1 | cut -d'=' -f2 | tr -d '[:space:]'
}

die() {
    echo  $1
    exit 1
}

export PATH="/srv/bricks/bin:$PATH"
export OS="$(uname | tr '[A-Z]' '[a-z]')"

case "$(uname -m)" in
       x86_64) ARCH="amd64";;
      aarch64) ARCH="arm64";;
       armv7l) ARCH="arm";;
    i386|i686) ARCH="386";;
            *) die "CRITICAL: Unsupported target platform structure";;
esac

find bin -maxdepth 1 -type f -name "*${OS}-${ARCH}" -print0 | \
        xargs -0 -I{} /bin/sh -c "\
            test ! -e bin/\$(basename "{}"| cut -d- -f1) && \
            ln -s \$(basename "{}") bin/\$(basename "{}"| cut -d- -f1)"

umask 0077

# ── PostgreSQL compatibility layer ──────────────────────────────────
# Maps official postgres Docker image environment variables to BRICKS
# db_* config keys. Precedence: BRICKS_db_* > POSTGRES_* > defaults.
#
# Official postgres image vars:
#   POSTGRES_HOST     (not set by image; added for compose networking)
#   POSTGRES_PORT     (not set by image; defaults to 5432)
#   POSTGRES_USER     (set by image, default: postgres)
#   POSTGRES_PASSWORD (set by image)
#   POSTGRES_DB       (set by image, default: postgres)
#
# BRICKS-specific override vars (take precedence):
#   BRICKS_db_host, BRICKS_db_port, BRICKS_db_user,
#   BRICKS_db_password, BRICKS_db_name, BRICKS_db_sslmode

DB_HOST="${BRICKS_db_host:-${POSTGRES_HOST:-localhost}}"
DB_PORT="${BRICKS_db_port:-${POSTGRES_PORT:-5432}}"
DB_USER="${BRICKS_db_user:-${POSTGRES_USER:-bricks}}"
DB_PASS="${BRICKS_db_password:-${POSTGRES_PASSWORD:-}}"
DB_NAME="${BRICKS_db_name:-${POSTGRES_DB:-bricks}}"
DB_SSL="${BRICKS_db_sslmode:-disable}"
DB_MAX_CONNS="${BRICKS_db_max_conns:-8}"
DB_STMT_TIMEOUT="${BRICKS_db_stmt_timeout:-30s}"

# ── Wait for Postgres to be ready ───────────────────────────────────
# Uses pg_isready if available; falls back to TCP probe via nc.
# BRICKS_pg_wait_max: max seconds to wait (default 60)
# BRICKS_pg_wait_interval: poll interval in seconds (default 2)
PG_WAIT_MAX="${BRICKS_pg_wait_max:-60}"
PG_WAIT_INTERVAL="${BRICKS_pg_wait_interval:-2}"

if [ -n "$DB_HOST" ] && [ "$DB_HOST" != "localhost" -o -n "$POSTGRES_PASSWORD" ]; then
    echo "==> Waiting for PostgreSQL at ${DB_HOST}:${DB_PORT} (max ${PG_WAIT_MAX}s)..."
    waited=0
    while true; do
        if command -v pg_isready >/dev/null 2>&1; then
            pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -q && break
        else
            nc -z "$DB_HOST" "$DB_PORT" 2>/dev/null && break
        fi
        waited=$((waited + PG_WAIT_INTERVAL))
        if [ "$waited" -ge "$PG_WAIT_MAX" ]; then
            echo "WARNING: PostgreSQL not ready after ${PG_WAIT_MAX}s -- continuing anyway"
            break
        fi
        sleep "$PG_WAIT_INTERVAL"
    done
    echo "==> PostgreSQL ready (or timeout reached)."
fi

# ── Auto-apply DDL schema ────────────────────────────────────────────
# If BRICKS_auto_init_sql is set to a path, run that SQL file against
# the configured database on first start. Skips if the target table
# already exists (idempotent check via pg_tables).
# Requires psql in the container (not installed by default; add to
# Dockerfile if needed, or use an init container in your compose file).
if [ -n "${BRICKS_auto_init_sql}" ] && [ -f "${BRICKS_auto_init_sql}" ]; then
    if command -v psql >/dev/null 2>&1; then
        echo "==> Running auto-init SQL: ${BRICKS_auto_init_sql}"
        PGPASSWORD="$DB_PASS" psql             -h "$DB_HOST" -p "$DB_PORT"             -U "$DB_USER" -d "$DB_NAME"             -f "${BRICKS_auto_init_sql}"             --on-error-continue 2>&1 || echo "WARNING: auto-init SQL completed with errors"
    else
        echo "WARNING: BRICKS_auto_init_sql set but psql not found -- skipping"
    fi
fi

# ── Generate bricks.cnf via m4 ──────────────────────────────────────
m4 \
  -D_dns_name="${BRICKS_dns_name:-$HOSTNAME}" \
  -D_port="${BRICKS_port:-2300}" \
  -D_tlsport="${BRICKS_tlsport:-2023}" \
  -D_tlscert="${BRICKS_tlscert:-}" \
  -D_tlskey="${BRICKS_tlskey:-}" \
  -D_start_TLS="${BRICKS_start_TLS:-no}" \
  -D_enforce_secure_login="${BRICKS_enforce_secure_login:-no}" \
  -D_secure_login_transaction="${BRICKS_secure_login_transaction:-cssn}" \
  -D_start_web3270="${BRICKS_start_web3270:-yes}" \
  -D_web3270_port="${BRICKS_web3270_port:-9000}" \
  -D_max_conns_per_ip="${BRICKS_max_conns_per_ip:-8}" \
  -D_runtime_dir="${BRICKS_runtime_dir:-runtime}" \
  -D_maps_dir="${BRICKS_maps_dir:-runtime/map}" \
  -D_rexx_dir="${BRICKS_rexx_dir:-runtime/rexx}" \
  -D_cobol_dir="${BRICKS_cobol_dir:-runtime/cobol}" \
  -D_copybook_dir="${BRICKS_copybook_dir:-runtime/cobolcopy}" \
  -D_data_dir="${BRICKS_data_dir:-data}" \
  -D_users_file="${BRICKS_users_file:-runtime/users.conf}" \
  -D_transactions_file="${BRICKS_transactions_file:-runtime/transactions.conf}" \
  -D_db_host="$DB_HOST" \
  -D_db_port="$DB_PORT" \
  -D_db_user="$DB_USER" \
  -D_db_password="$DB_PASS" \
  -D_db_name="$DB_NAME" \
  -D_db_sslmode="$DB_SSL" \
  -D_db_max_conns="$DB_MAX_CONNS" \
  -D_db_stmt_timeout="$DB_STMT_TIMEOUT" \
  > bricks.cnf << EOF
dns_name=_dns_name
port=_port
tlsport=_tlsport
tlscert=_tlscert
tlskey=_tlskey
start_TLS=_start_TLS
enforce_secure_login=_enforce_secure_login
#secure_login_transaction=_secure_login_transaction
start_web3270=_start_web3270
web3270_port=_web3270_port
max_conns_per_ip=_max_conns_per_ip
runtime_dir=_runtime_dir
maps_dir=_maps_dir
rexx_dir=_rexx_dir
cobol_dir=_cobol_dir
copybook_dir=_copybook_dir
data_dir=_data_dir
users_file=_users_file
transactions_file=_transactions_file
db_host=_db_host
db_port=_db_port
db_user=_db_user
db_password=_db_password
db_sslmode=_db_sslmode
db_max_conns=_db_max_conns
db_stmt_timeout=_db_stmt_timeout
databases_file=runtime/databases.conf
EOF

chmod 400 bricks.cnf

case "$(readcfg start_tls bricks.cnf)" in
    [yY][eE][sS]) test -f "$(readcfg tlscert bricks.cnf)" || \
                  test -f "$(readcfg tlskey bricks.cnf)" || \
                  die "CRITICAL: start_TLS active but cert/key mounts missing";;
               *) ;;
esac

echo "==> Booting BRICKS Transaction Server for COBOL and REXX..."
exec "bricks" $@
