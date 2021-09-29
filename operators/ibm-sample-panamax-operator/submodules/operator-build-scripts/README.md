# Setup Workers

These are scripts to setup a remote worker (e.g. Fyre). 

[setupWorker](setupWorker.sh) - This sets up a worker node. Assumes Ubuntu is used.

[.env](.env) - This is a file with only environment variables in it. Make sure to fill in the values before running [setupWorker](setupWorker.sh)

1. If you don't already have it on MacOS, install ssh-copy-id

   ```bash
   brew install ssh-copy-id
   ```

1. If you don't have a public/private key setup, create one (NOTE: need higher bits than default for MacOS):

   ```bash
   ssh-keygen -t rsa -b 2048
   ```

   1. When prompted accept default path and empty passphrase.

1. Source your .env file

   ```bash
   source .env
   ```

1. For each of the worker nodes copy your own key to the nodes so you can easily access them

   ```bash
   ssh-copy-id root@${X_NODE}
   ssh-copy-id root@${P_NODE}
   ssh-copy-id root@${Z_NODE}
   ```

1. Setup the x86_64 node so it can access the ppc64le and s390x node:

   ```bash
   mkdir -p /tmp/xnodekeys/ && scp root@${X_NODE}:.ssh/id_rsa.pub /tmp/xnodekeys && ssh-copy-id -i /tmp/xnodekeys/id_rsa.pub root@${P_NODE} && ssh-copy-id -i /tmp/xnodekeys/id_rsa.pub root@${Z_NODE}
   ```

1. ssh to x86_64 node and then ssh to the ppc64le and s390x node to accept the key fingerprint. You'll need to exit after each connection.

   ```bash
   ssh -tt root@${X_NODE} ssh ${P_NODE}
   exit
   ssh -tt root@${X_NODE} ssh ${Z_NODE}
   exit
   ```

1. For each of the worker nodes setup the code needed

   ```bash
   ssh root@${X_NODE} 'mkdir -p setup' && rsync -av ./ root@${X_NODE}:setup && ssh root@${X_NODE} setup/setupWorker.sh
   ssh root@${P_NODE} 'mkdir -p setup' && rsync -av ./ root@${P_NODE}:setup && ssh root@${P_NODE} setup/setupWorker.sh
   ssh root@${Z_NODE} 'mkdir -p setup' && rsync -av ./ root@${Z_NODE}:setup && ssh root@${Z_NODE} setup/setupWorker.sh
   ```


1. Log into each node, and generate a gpg key to use with the keystore. Answer all of the prompts (e.g. Name, email, etc.).
When it prompts for a passphrase don't provide one (just hit return) and accept the "are you sure" messages. 
While the passphrase is more secure, it means that the passphrase needs to be provided in some fashion (i.e. interactive terminal 
or configuring the system to keep the passphrase so you don't have to enter it). An attempt was made to store the passphrase
but that never worked. When generating the key it could take a while if there is no available entropy.

   ```bash
   gpg2 --gen-key
   ```

1. The `pass` tool (which is the password manager) and `docker-credential-pass` (which is a docker helper to talk to `pass`) is installed 
onto the system with the previous script. `pass` needs initialization:

   ```bash
   pass init jhunkins@us.ibm.com
   ```

1. For Red Hat registries you need a token... Follow the instructions in https://playbook.cloudpaklab.ibm.com/developer-guide/images/pulling-red-hat-images-outside-of-cluster/

1. docker login to any registries

   ```bash
   docker login -u='11868048|name_of_my_key' registry.redhat.io
   docker login -u=iamapikey cp.stg.icr.io
   docker pull registry.redhat.io/openshift4/ose-operator-registry:v4.5
   ```

1. If you want, you can see the token that is stored in the password manager
   
   ```bash
   pass show 'docker-credential-helpers/cmVnaXN0cnkucmVkaGF0Lmlv/11868048|name_of_my_key'
   ```


# Operator Build Scripts

[buildBundles](buildBundles.sh) - Build OLM Bundle Images

[buildIndex](buildIndex.sh) - Build OLM Index Image

[buildManifest](buildManifest.sh) - Builds the fat manifest image for a multi-platform image

[buildMultiarchImage](buildMultiarchImage.sh) - build docker images for multiple architectures and a manifest image for them

[buildProductionVersionOfIndex](buildProductionVersionOfIndex.sh) - 

[pushBundles](pushBundles.sh) - Push OLM Bundle Images

[pushIndex](pushIndex.sh) - Push OLM Index Image

[utils](utils.sh) - utility functions sourced by other scripts

[versionsAndBundlesFromReleases](versionsAndBundlesFromReleases.sh) - iterate through git releases and current branch, building bundle images and versions.txt for other operator build scripts
