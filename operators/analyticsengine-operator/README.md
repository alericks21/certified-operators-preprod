# AnalyticsEngine Operators
AnalyticsEngine service operator on CPD

#### Setps to Build Operator Image

##### Clone this git repo on your bastion node

```
git clone git@github.ibm.com:hummingbird/analyticsengine-operator.git
```

##### Go to operator folder 

```
cd analyticsengine-operator/
```

##### Login to hummingbird image registry

```
docker login registry.ng.bluemix.net/hummingbird
```

##### Build and push operator image

```
make docker-build docker-push IMG=registry.ng.bluemix.net/hummingbird/analyticsengine-operator:v0.0.1
```

#### Steps to Deploy Operator

##### Create namespace-scope configmap for the analyticsengine-operator (same namespace as analyticsengine-operator) to notify the watch namespace. Update the spark1,spark2 to include namespaces you wish to install AnalyticsEngine service in. Note: only CR created in the namespace(s) listed here will trigger operator to install AnalyticsEngine service

```
oc create configmap namespace-scope --from-literal=namespaces=spark1,spark2
```

##### Run make command to deploy operator

```
make deploy IMG=registry.ng.bluemix.net/hummingbird/analyticsengine-operator:v0.0.1 
```

##### Create imagepull secret for operator

```
oc -n analyticsengine-operator-system create secret docker-registry analyticsengine-operator-regsitry-key --docker-server=registry.ng.bluemix.net/hummingbird --docker-username=iamapikey --docker-password=<REPLACE_WITH_IMAGE_REGISTRY_TOKEN> --docker-email=dummy@in.ibm.com
```

##### Link image pull secret with operator's service account

```
oc secrets link ibm-cpd-ae-operator-serviceaccount analyticsengine-operator-regsitry-key --for=pull -n  analyticsengine-operator-system
```

**NOTE:** Check if operator pod is running or not, if it is in imagepullbackoff state just delete that pod which will bring up new operator pod.

#### Steps to deploy AnalyticsEngine service

##### Install Lite Operator

Install lite on your cluster using the following [link](https://github.ibm.com/PrivateCloud/zen-operator) in your project. Make sure to add cpdlegacy: True to the CR.yaml or extra.yaml based on how you install lite, this will allow the legacy SCC and service accounts to be installed

#### AnalyticsEngine CR overview


```
apiVersion: ae.cpd.ibm.com/v1
kind: AnalyticsEngine
metadata:
  name: analyticsengine-sample
  labels:
    app.kubernetes.io/instance: ibm-cpd-ae-operator
    app.kubernetes.io/managed-by: ibm-cpd-ae-operator
    app.kubernetes.io/name: ibm-cpd-ae-operator
    build: BUILD_NUMBER
spec:
  version: "4.0.1"
  license:
    accept: true
#-------------------------------------------------------#
# Following specs are optional and
# we have added default values as example in this CR.
#-------------------------------------------------------#
  scaleConfig: "small"
  pullPrefix: "cp.icr.io/cp/cpd"
#-------------------------------------------------------#
# Following specs are optional and 
# can be altered to change service level configurations
#-------------------------------------------------------#
#  serviceConfig:
#    sparkAdvEnabled: true                         # This flag will enable or disable job UI capabilities of AnalyticsEngine service
#    jobAutoDeleteEnabled: true                    # Set it to false if you do not want to removed spark jobs once they have reached terminal states e.g FINISHED/FAILED
#    fipsEnabled: false                            # Set it to true if your system is FIPS enabled
#    kernelCullTime: 30                            # Change value in minutes, if want to remove idle kernel after X minutes.
#    imagePullCompletions: 20                      # If you have very large Openshift cluster in that case you can update imagePullCompletions & imagePullParallelism accordingly
#    imagePullParallelism: 40                      # e.g. if you have 100 nodes cluster set imagePullCompletions: "100" & imagePullParallelism: "150"
#    kernelCleanupSchedule: "*/30 * * * *"         # By default kernel & job cleanup cronjobs look for idle spark kernels/jobs and based on kernelCullTime parameter
#    jobCleanupSchedule: "*/30 * * * *"            # and removes them, if you want cleanup to less/more aggressive change accordingly. e.g for 1 hour "* */1 * * *" k8s format
#-------------------------------------------------------#
# Following specs are optional and can be altered
# to change spark runtime level configurations 
#-------------------------------------------------------#   
#  sparkRuntimeConfig:                             # If you want to create spark jobs with
#    maxDriverCpuCores: 5                          # Drive CPUs more than 5 than set accordingly  
#    maxExecutorCpuCores: 5                        # or more than 5 CPU per Executor than set accordingly  
#    maxDriverMemory: "50g"                        # or Drive Memory more than 50g than set accordingly  
#    maxExecutorMemory: "50g"                      # or more than 50g Memory per Executor than set accordingly  
#    maxNumWorkers: 50                             # or more than 50 workers/executors than set accordingly  
#-------------------------------------------------------#
# Following specs are optional and can be altered
# to change service instance level configurations.
# Each AE service service instance have resource quota
# (cpu/memory) set by default as following. It can be changed
# via API for an instance but to change default values
# for any new instance creation update following 
#-------------------------------------------------------#
#  serviceInstanceConfig:
#    defaultCpuQuota: 20                           # defaultCpuQuota means accumulative cpu consumption of spark jobs create under an instance can be no more than 20
#    defaultMemoryQuota: 80                        # defaultMemoryQuota means accumulative memory consumption of spark jobs create under an instance can be no more than 80 in GB
```

#### Deploy AnalyticsEngine CR

```
oc create -f config/samples/ae_v1_analyticsengine.yaml -n <namespace_where_lite_is_deployed>
```

##### To Remove AnalyticsEngine CR

```
oc delete -f config/samples/ae_v1_analyticsengine.yaml -n <namespace_where_lite_is_deployed>
```

#### Steps to remove operator

```
make undeploy
```


## PodSecurityPolicy Requirements
TBD

## SecurityContextConstraints Requirements
TBD


