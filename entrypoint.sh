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
        xargs -0 -I{} /bin/sh -c "ln -s \$(basename "{}") bin/\$(basename "{}"| cut -d- -f1)"

umask 0077

# Configuration generator - Maintainer Note: heardocs + m4(1) are crufty but maybe a better way
#                                            is using spf13/viper and spf13/pflag directly 
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
