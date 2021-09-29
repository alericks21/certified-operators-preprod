#!/usr/bin/env bash

oc delete ns joeolm
oc delete catalogsource.operators.coreos.com/ibm-sample-panamax-catalog -nopenshift-marketplace
oc get validatingwebhookconfigurations | grep panamax | cut -d' ' -f1 | xargs -I {} oc delete validatingwebhookconfigurations {}  
oc get mutatingwebhookconfigurations | grep panamax | cut -d' ' -f1 | xargs -I {} oc delete mutatingwebhookconfigurations {}  
oc get clusterrolebindings | grep panamax | cut -d' ' -f1 | xargs -I {} oc delete  clusterrolebindings {}  -
oc get clusterroles | grep panamax | cut -d' ' -f1 | xargs -I {} oc delete clusterroles {}  
oc get scc | grep panamax | cut -d' ' -f1 | xargs -I {} oc delete scc {} 
oc get crd | grep panamax | cut -d' ' -f1 | xargs -I {} oc delete crd {}
oc create ns joeolm
oc project joeolm