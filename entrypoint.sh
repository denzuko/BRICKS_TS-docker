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

# ── PostgreSQL environment variable mapping ──────────────────────────
# Maps official postgres Docker image environment variables to BRICKS
# db_* config keys. Precedence: BRICKS_db_* > POSTGRES_* > defaults.
#
# Official postgres image vars (set by postgres:N-alpine at runtime):
#   POSTGRES_USER     (default: postgres)
#   POSTGRES_PASSWORD
#   POSTGRES_DB       (default: postgres)
#
# Non-standard vars for compose service networking (not set by image):
#   POSTGRES_HOST     set this in the bricks service to name the db service
#   POSTGRES_PORT     optional; defaults to 5432
#
# BRICKS-specific overrides take precedence over POSTGRES_* vars.
BRICKS_db_host="${BRICKS_db_host:-${POSTGRES_HOST:-localhost}}"
BRICKS_db_port="${BRICKS_db_port:-${POSTGRES_PORT:-5432}}"
BRICKS_db_user="${BRICKS_db_user:-${POSTGRES_USER:-bricks}}"
BRICKS_db_password="${BRICKS_db_password:-${POSTGRES_PASSWORD:-}}"
BRICKS_db_sslmode="${BRICKS_db_sslmode:-disable}"
BRICKS_db_max_conns="${BRICKS_db_max_conns:-8}"
BRICKS_db_stmt_timeout="${BRICKS_db_stmt_timeout:-30s}"
BRICKS_db_file="${BRICKS_db_file:-runtime/databases.conf}"

# Configuration generator - Maintainer Note: m4(1) is crufty but functional.
#                           A cleaner path: spf13/viper + spf13/pflag directly.
m4 \
  -D_dns_name="${BRICKS_dns_name:-$HOSTNAME}" \
  -D_port="${BRICKS_port:-2300}" \
  -D_tlsport="${BRICKS_tlsport:-2023}" \
  -D_tlscert="${BRICKS_tlscert:-}" \
  -D_tlskey="${BRICKS_tlskey:-}" \
  -D_start_TLS="${BRICKS_start_TLS:-no}" \
  -D_enforce_secure_login="${BRICKS_enforce_secure_login:-no}" \
  -D_secure_login_transaction="${BRICKS_secure_login_transaction:-cssn}" \
  -D_start_web3270="${BRICKS_start_web3270:-no}" \
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
  -D_databases_file="${BRICKS_db_file}" \
  -D_db_host="${BRICKS_db_host}" \
  -D_db_port="${BRICKS_db_port}" \
  -D_db_user="${BRICKS_db_user}" \
  -D_db_password="${BRICKS_db_password}" \
  -D_db_sslmode="${BRICKS_db_sslmode}" \
  -D_db_max_conns="${BRICKS_db_max_conns}" \
  -D_db_stmt_timeout="${BRICKS_db_stmt_timeout}" \
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
databases_file=_databases_file
db_host=_db_host
db_port=_db_port
db_user=_db_user
db_password=_db_password
db_sslmode=_db_sslmode
db_max_conns=_db_max_conns
db_stmt_timeout=_db_stmt_timeout
EOF

chmod 400 bricks.cnf

RUN_TLS=$(readcfg start_tls bricks.cnf)
CERT_PATH=$(readcfg tlscert bricks.cnf)
KEY_PATH=$(readcfg tlskey bricks.cnf)

case  "$(readcfg start_tls bricks.cnf)" in
        [yY][eE][sS])  test -f "$(readcfg tlscert bricks.cnf)" || \
                       test -f "$(readcfg tlskey bricks.cnf)" || \
                       die "CRITICAL: start_TLS option active but asset mounts do not resolve:";;
                   *) ;;
esac

echo "==> Booting BRICKS Transaction Server for Cobol and REXXX..."
exec "bricks" $@
