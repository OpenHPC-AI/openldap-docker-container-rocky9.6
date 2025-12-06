# Create openldap docker container image

**Install the git package**
```bash
yum install git
```
**Clone the openldap code in your environment**
```bash
git clone https://github.com/OpenHPC-AI/openldap-docker-container-rocky9.6.git
```
**Build openldap docker image**
```bash
cd ./openldap-docker-container-rocky9.6/ldap-server
docker build --network host -t openldap:2.4.46 .
```
**Export the OpenLDAP Docker image to make it portable for use on other servers**
```bash
docker save -o openldap_2.4.46_img.tar openldap:2.4.46
```
# Configure LDAP Container Setup

1. **Edit the `.env` file on both master nodes**  
   Update all required environment variables to match your cluster setup.

2. **Create the `hpc_container_pv` directory**  
   This directory will store persistent data for the LDAP container.
   ```bash
   mkdir /hpc_container_pv
   ```
   Also update the `docker-compose.yml` file to ensure the LDAP container uses this path for its persistent volume.

4. ***Load the LDAP Docker image (If your OpenLDAP image was built on another machine, transfer the saved image to this server and load it locally before starting the container.)***
   ```
   **Skip this step when operating on the same server environment.**
   ```
   Load the pre-built LDAP image into the local Docker environment:
   ```bash
   docker load < openldap_2.4.46_img.tar
   ```
6. **Update docker-compose.yml**
   Modify the file to reference the loaded LDAP image and the persistent volume configuration:
   ```bash
   vim docker-compose.yml
   ```
7. **Create and start the LDAP container**
   ```bash
   docker-compose up -d
   ```
8. **Verify the LDAP container is running**
   Confirm that the image is loaded and the container is up and healthy:
   ```bash
   docker images | grep ldap
   docker ps | grep ldap
   ```
**The LDAP service should now be successfully deployed using Docker Compose with persistent storage.**

**Bonus:**

# LDAP Host Machine Setup 

These steps required to configure the host machine to use the LDAP commands from host machine.
---

1. **Install Required LDAP Client Packages**
 Install necessary packages on the host machine:
  ```bash
  yum install -y nss-pam-ldapd authconfig openldap openldap-clients
  ```
2. **Backup Default System Configuration Files**
  Take a backup of the default configuration files before replacing them:
  ```bash
  mv /etc/nsswitch.conf /etc/nsswitch.conf.bk
  mv /etc/nslcd.conf /etc/nslcd.conf.bk
  mv /etc/openldap /etc/openldap.bk
  mv /var/lib/ldap /var/lib/ldap.bk
  ```
3. **Copy LDAP Configuration Files From Container**
  Copy the required files from your LDAP container to the host:
  ```bash
  docker cp ldap_server:/etc/nsswitch.conf /etc/
  docker cp ldap_server:/etc/nslcd.conf /etc/
  ```
***Note - Replace ldap_server with the actual container name or ID of your LDAP container.***

4. **Create Symlinks for LDAP Persistent Data**
   Link host system paths to the persistent volume used by the LDAP container:
   ```bash
   ln -s /hpc_container_pv/ldapdata/var/lib/ldap /var/lib/
   ln -s /hpc_container_pv/ldapdata/etc/openldap /etc/
   ```
5. **Enable and Start the nslcd Service**
   ```bash
   systemctl enable --now nslcd
   ```
