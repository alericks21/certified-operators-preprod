# IBM Sample Panamax

The `ibm-sample-panamax-operator` is an example Go-based Operator meant to show best practices in the development and testing of an Operator, including OCP Catalog integration.

**Note:** This is a sample README of what an Operator README could look like.

**Note:** With how quickly things are changing in this space, Panamax will always be a work in progress.

## Supported platforms

Red Hat OpenShift Container Platform 4.3 or newer installed on one of the following platforms:

   - Linux x86_64
   - Linux ppc64le
   - Linux s390x

## Operator versions

   - v1.0.0

## Prerequisites

Before you install this operator, you need to first install the operator prerequisites:

- Links to any prerequisites would go here

## Documentation

- Links to knowledge center documentation would go here

## SecurityContextConstraints Requirements

### Panamax Controller

The Sample Panamax Operator controller currently runs with the default Red Hat `restricted` SCC.

This Operator also defines a custom SecurityContextConstraints object which is used to finely control the permissions/capabilities needed to deploy this Operator, the definition of this SCC is shown below:

#### Custom SecurityContextConstraints definition:

```yaml
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: panamaxSCC
allowHostPorts: false
priority: null
requiredDropCapabilities:
  - MKNOD
allowPrivilegedContainer: false
runAsUser:
  type: MustRunAsRange
users: []
allowHostDirVolumePlugin: false
allowHostIPC: false
seLinuxContext:
  type: MustRunAs
readOnlyRootFilesystem: false
fsGroup:
  type: MustRunAs
groups: []
defaultAddCapabilities: null
supplementalGroups:
  type: RunAsAny
volumes:
  - configMap
  - downwardAPI
  - emptyDir
  - persistentVolumeClaim
  - projected
  - secret
allowHostPID: false
allowHostNetwork: false
allowPrivilegeEscalation: true
allowedCapabilities: null
```

If you wish to deploy the Operator Controller under the custom SCC enforcement, then the SCC must be bound to the namespace before installing the Operator. Copy the above SCC into a file to apply it to your cluster.

```
# Save the yaml definition from the README to panamax-scc.yaml
$ oc login # login as cluster admin 
$ oc apply -f panamax-scc.yaml
$ oc create clusterrole panamax-scc-binding-cluster-role --verb="use" --resource="securityContextConstraints" --resource-name="panamaxSCC"
$ oc create rolebinding panamax-scc-binding-namespace-role-binding --clusterrole="panamax-scc-binding-cluster-role" --group="system:serviceaccounts:<namespace for panamax deployment>" 
```

For more information about the OpenShift Container Platform Security Context Constraints, see [Managing Security Context Constraints](https://docs.openshift.com/container-platform/4.3/authentication/managing-security-context-constraints.html).

## Reporting issues

Issues with the Panamax Operator can be reported in the [#cloudpak-certify](https://ibm-cloudplatform.slack.com/archives/C6A052PCL) slack channel, or issues can be raised on the [container-content-roadmap Github repository](https://github.ibm.com/IBMPrivateCloud/container-content-roadmap/issues/new/choose).

