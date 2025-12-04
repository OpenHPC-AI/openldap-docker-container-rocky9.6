# Create openldap docker container image
Install the git package
```bash
yum install git
```
Clone the openldap code in your environment
```bash
git clone 
```
# Configure LDAP Container Setup

1. **Edit the `.env` file on both master nodes**  
   Update all required environment variables to match your cluster setup.

2. **Create the `hpc_container_pv` directory**  
   This directory will store persistent data for the LDAP container.  
   Also update the `docker-compose.yml` file to ensure the LDAP container uses this path for its persistent volume.

3. **Load the LDAP Docker image**  
   Load the pre-built LDAP image into the local Docker environment:
   ```bash
   docker load < {docker_ldap_images}
   ```
