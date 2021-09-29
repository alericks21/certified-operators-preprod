/*


Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package main

import (
	"flag"
	"fmt"
	"os"

	"k8s.io/apimachinery/pkg/runtime"
	utilruntime "k8s.io/apimachinery/pkg/util/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	_ "k8s.io/client-go/plugin/pkg/client/auth/gcp"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"

	samplev1beta1 "github.ibm.com/CloudPakOpenContent/ibm-sample-panamax-operator/api/v1beta1"
	"github.ibm.com/CloudPakOpenContent/ibm-sample-panamax-operator/controllers"

	routev1 "github.com/openshift/api/route/v1"
	security "github.com/openshift/api/security/v1"

	admissionregistration "k8s.io/api/admissionregistration/v1beta1"
	// +kubebuilder:scaffold:imports
)

// Used in OLM only
const (
	WebhookPort     = 9443
	WebhookCertDir  = "/apiserver.local.config/certificates"
	WebhookCertName = "apiserver.crt"
	WebhookKeyName  = "apiserver.key"
)

var (
	scheme   = runtime.NewScheme()
	setupLog = ctrl.Log.WithName("setup")
)

func init() {
	utilruntime.Must(clientgoscheme.AddToScheme(scheme))
	utilruntime.Must(samplev1beta1.AddToScheme(scheme))
	utilruntime.Must(routev1.AddToScheme(scheme))
	utilruntime.Must(security.AddToScheme(scheme))
	utilruntime.Must(admissionregistration.AddToScheme(scheme))

	// +kubebuilder:scaffold:scheme
}

// getWatchNamespace returns the Namespace the operator should be watching for changes
func getWatchNamespace() (string, error) {
	// WatchNamespaceEnvVar is the constant for env variable WATCH_NAMESPACE
	// which specifies the Namespace to watch.
	// An empty value means the operator is running with cluster scope.
	var watchNamespaceEnvVar = "WATCH_NAMESPACE"

	ns, found := os.LookupEnv(watchNamespaceEnvVar)
	if !found {
		return "", fmt.Errorf("%s must be set", watchNamespaceEnvVar)
	}
	return ns, nil
}

// getMyNamespace returns the Namespace the operator is actually running in
func getMyNamespace() (string, error) {

	var myNamespaceEnvVar = "MY_NAMESPACE"

	ns, found := os.LookupEnv(myNamespaceEnvVar)
	if !found {
		return "", fmt.Errorf("%s must be set", myNamespaceEnvVar)
	}
	return ns, nil
}

func main() {
	var metricsAddr string
	var enableLeaderElection bool
	flag.StringVar(&metricsAddr, "metrics-addr", ":8080", "The address the metric endpoint binds to.")
	flag.BoolVar(&enableLeaderElection, "enable-leader-election", false,
		"Enable leader election for controller manager. "+
			"Enabling this will ensure there is only one active controller manager.")
	flag.Parse()

	ctrl.SetLogger(zap.New(zap.UseDevMode(true)))

	var namespace string = ""
	var clusterScope bool = false

	namespace, err := getWatchNamespace()
	if err != nil {
		setupLog.Info("Failed to get watch namespace")
		//os.Exit(1)
	}

	if namespace == "" {
		namespace, err = getMyNamespace()

		clusterScope = true
		setupLog.Info("Watch namespace is empty assume cluster installmode, get the operatornamespace and use that", "namespace", namespace)
		if err != nil {
			setupLog.Error(err, "Failed to get operator namespace")
			os.Exit(1)
		}
	}

	options := ctrl.Options{
		Scheme:             scheme,
		MetricsBindAddress: metricsAddr,
		Port:               9443,
		LeaderElection:     enableLeaderElection,
		LeaderElectionID:   "edb9eae0.ibm.com",
	}

	if !clusterScope {
		options.Namespace = namespace
	}

	mgr, err := ctrl.NewManager(ctrl.GetConfigOrDie(), options)
	if err != nil {
		setupLog.Error(err, "unable to start manager")
		os.Exit(1)
	}

	// Specify OLM CA Info
	// only do this in operator bundle mode
	// use a variable in bundle yaml as it's an API we control

	if os.Getenv("WEBHOOK_ENABLED") != "false" {
		setupLog.Info("Webhook Enabled")

		_, present := os.LookupEnv("OLM_DEPLOY")
		if present {
			setupLog.Info("Detected running in OLM")
			srv := mgr.GetWebhookServer()
			srv.CertDir = WebhookCertDir
			srv.CertName = WebhookCertName
			srv.KeyName = WebhookKeyName
			srv.Port = WebhookPort
		} else {
			setupLog.Info("Detected running outside of OLM")
		}

		if err = (&samplev1beta1.Panamax{}).SetupWebhookWithManager(mgr); err != nil {
			setupLog.Error(err, "unable to create webhook", "webhook", "Panamax")
			os.Exit(1)
		}
	} else {
		setupLog.Info("Webhook not enabled")
	}

	if err = (&controllers.PanamaxReconciler{
		Client: mgr.GetClient(),
		Log:    ctrl.Log.WithName("controllers").WithName("Panamax"),
		Scheme: mgr.GetScheme(),
	}).SetupWithManager(mgr); err != nil {
		setupLog.Error(err, "unable to create controller", "controller", "Panamax")
		os.Exit(1)
	}

	if err = (&controllers.PanamaxConfigReconciler{
		Client: mgr.GetClient(),
		Log:    ctrl.Log.WithName("controllers").WithName("PanamaxConfig"),
		Scheme: mgr.GetScheme(),
	}).SetupWithManager(mgr); err != nil {
		setupLog.Error(err, "unable to create controller", "controller", "PanamaxConfig")
		os.Exit(1)
	}

	setupLog.Info("starting manager")
	if err := mgr.Start(ctrl.SetupSignalHandler()); err != nil {
		setupLog.Error(err, "problem running manager")
		os.Exit(1)
	}
}
