#!/bin/bash
set -xe

# Reduce maximum number of open file descriptors to 1024
ulimit -n 1024

variable_set() {
    # Check if required environment variables are set
    required_vars=(LDAP_ROOT_PASSWD BASE_PRIMARY_DC BASE_SECONDARY_DC BASE_SUBDOMAIN_DC CN OU1 OU2 OU3 OU4 OU5 OU6 OU7 LDAP_SERVER_IP)

    # Set default OpenLDAP debug level if not provided
    OPENLDAP_DEBUG_LEVEL=${OPENLDAP_DEBUG_LEVEL:-256}

    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            echo "Error: Environment variable $var is not set." >&2
            exit 1
        fi
    done

    # Generate configuration files from templates
    envsubst < /ldap_config/basedomain.ldif.template > /ldap_config/basedomain.ldif
    envsubst < /ldap_config/chdomain.ldif.template > /ldap_config/chdomain.ldif
    envsubst < /ldap_config/nslcd.conf.template > /etc/nslcd.conf
    envsubst < /ldap_config/migrate_common.ph.template > /usr/share/migrationtools/migrate_common.ph
    envsubst < /ldap_config/ldap.conf.template  > /etc/openldap/ldap.conf
    envsubst < /ldap_config/ldap-script/testuser.ldif.template > /ldap_config/ldap-script/testuser.ldif
}

enable_slapd_service() {
    # Start slapd in the background
    slapd -h "ldap:/// ldaps:/// ldapi:///" -d 256 > /dev/null 2>&1 &
    slapd_pid=$!

    # Wait for slapd to start
    for i in {1..30}; do
        if ldapsearch -Y EXTERNAL -H ldapi:/// -s base -b "cn=config" > /dev/null 2>&1; then
            break
        fi
        sleep 1
    done

    if ! ps -p "$slapd_pid" > /dev/null 2>&1; then
        echo "Error: slapd failed to start." >&2
        exit 1
    fi
}

ldap_root_pw() {
    # Generate root password hash
    OPENLDAP_ROOT_PASSWORD_HASH=$(slappasswd -s "${LDAP_ROOT_PASSWD}")
    echo "${OPENLDAP_ROOT_PASSWORD_HASH}" > /ldap_root_hash_pw

    # Set root password
    sed -i "s|OPENLDAP_ROOT_PASSWORD|${OPENLDAP_ROOT_PASSWORD_HASH}|g" /ldap_config/chrootpw.ldif
    ldapadd -Y EXTERNAL -H ldapi:/// -f /ldap_config/chrootpw.ldif || { echo "Error: Failed to set root password."; exit 1; }
}


import_basic_schema() {
    # Add basic schemas
    ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/cosine.ldif -d $OPENLDAP_DEBUG_LEVEL > /dev/null 2>&1
    ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/nis.ldif -d $OPENLDAP_DEBUG_LEVEL > /dev/null 2>&1
    ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/inetorgperson.ldif -d $OPENLDAP_DEBUG_LEVEL > /dev/null 2>&1
    ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/nsmattribute.ldif -d $OPENLDAP_DEBUG_LEVEL > /dev/null 2>&1
}


set_domain_name() {
    # Configure the domain
    sed -i "s|OPENLDAP_ROOT_PASSWORD|${OPENLDAP_ROOT_PASSWORD_HASH}|g" /ldap_config/chdomain.ldif
    ldapmodify -Y EXTERNAL -H ldapi:/// -f /ldap_config/chdomain.ldif || { echo "Error: Failed to configure domain."; exit 1; }

    # Add basedomain entries
    if ! ldapsearch -x -D "cn=${CN},dc=${BASE_SECONDARY_DC},dc=${BASE_PRIMARY_DC}" \
         -w "${LDAP_ROOT_PASSWD}" -b "dc=${BASE_SECONDARY_DC},dc=${BASE_PRIMARY_DC}" "(objectClass=*)" > /dev/null 2>&1; then

        echo "Basedomain entries not found. Adding basedomain entries..."
        ldapadd -x -D "cn=${CN},dc=${BASE_SECONDARY_DC},dc=${BASE_PRIMARY_DC}" \
            -w "${LDAP_ROOT_PASSWD}" -f /ldap_config/basedomain.ldif || \
            { echo "Error: Failed to add basedomain entries."; exit 1; }
    else
        echo "Basedomain entries already exist. Skipping ldapadd."
    fi
}

Stop_slapd() {
    # Stop slapd service
    kill -2 "$slapd_pid"
    wait "$slapd_pid" || { echo "Error: slapd did not stop correctly."; exit 1; }
}

slap_test() {
    # Test configuration files
    slaptest || echo "Warning: Configuration test failed. Check the output for details."
}

setup_complete() {
    # Mark setup as complete
    touch /etc/openldap/CONFIGURED
}

Start_ldap_services() {
    echo "Starting supervisord..."
    exec /usr/bin/supervisord -c /etc/supervisord.conf
}

if [ ! -f /etc/openldap/CONFIGURED ] && [[ -d "/ldapdata.NEEDINIT" ]]; then
    rsync -a --ignore-existing /ldapdata.NEEDINIT/* /ldapdata/
    mv /ldapdata.NEEDINIT /ldapdata.orig

    # Reduce maximum number of open file descriptors to 1024
    ulimit -n 1024

    variable_set
    enable_slapd_service
    ldap_root_pw
    import_basic_schema
    set_domain_name
    slap_test
    setup_complete

    sleep 5
    Stop_slapd
    Start_ldap_services
else
    Start_ldap_services
fi

# Keep the container running
timeout 10s wait


