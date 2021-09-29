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

package controllers

import (
	"context"
	"fmt"
	"os"
	"reflect"

	goschutils "github.ibm.com/CloudPakOpenContent/go-sch/utils"
	samplev1beta1 "github.ibm.com/CloudPakOpenContent/ibm-sample-panamax-operator/api/v1beta1"

	routev1 "github.com/openshift/api/route/v1"
	"github.com/prometheus/common/log"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/apimachinery/pkg/util/intstr"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"

	"github.com/go-logr/logr"
	"k8s.io/apimachinery/pkg/runtime"
)

const (
	//Full Name Constants
	fullNameMaxNameLength            = 63
	fullNameReleaseNameTruncLength   = 42
	fullNameAppNameTruncLength       = 20
	fullNameComponentNameTruncLength = 0
)

var managedBy = "panamax-operator-deployment"
var appName = "panamax-operator-deployment"

// PanamaxReconciler reconciles a Panamax object
type PanamaxReconciler struct {
	client.Client
	Log    logr.Logger
	Scheme *runtime.Scheme
}

var _ reconcile.Reconciler = &PanamaxReconciler{}

// +kubebuilder:rbac:groups=coordination.k8s.io,resources=leases,verbs=create;get;list;update

// SetupWithManager creates the watches
func (r *PanamaxReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&samplev1beta1.Panamax{}).Owns(&corev1.ConfigMap{}).Owns(&appsv1.Deployment{}).Owns(&corev1.Service{}).
		Complete(r)
}

// SAName is the service account name
var SAName string

// setup RBAC
func (r *PanamaxReconciler) reconcileRBAC(instance *samplev1beta1.Panamax, request reconcile.Request) error {

	reqLogger := r.Log.WithValues("Request.Namespace", request.Namespace, "Request.Name", request.Name)
	reqLogger.Info("Reconciling RBAC configuration")

	SAName = "panamax-operator-" + instance.Namespace + "-sa"
	SAName = goschutils.GetAppName(SAName, goschutils.DefaultFullNameTruncationConfig())

	stdSALabels := goschutils.GetStandardLabels(
		appName,
		managedBy,
		SAName,
		"",
		map[string]string{"app.kubernetes.io/part-of": "Panamax-Operator", "app.kubernetes.io/version": instance.Spec.Version},
		goschutils.DefaultFullNameTruncationConfig())

	serviceAccount := &corev1.ServiceAccount{
		ObjectMeta: metav1.ObjectMeta{
			Name:      SAName,
			Namespace: instance.Namespace,
			Labels:    stdSALabels,
		},
	}

	// Check if the ServiceAccount already exists and create it if it doesn't
	foundServiceAccount := &corev1.ServiceAccount{}
	err := r.Client.Get(context.TODO(), types.NamespacedName{Name: serviceAccount.Name, Namespace: serviceAccount.Namespace}, foundServiceAccount)
	if err != nil && errors.IsNotFound(err) {
		reqLogger.Info("Creating ServiceAccount", serviceAccount.Namespace, serviceAccount.Name)
		err = r.Client.Create(context.TODO(), serviceAccount)
		if err != nil {
			return err
		}
	} else if err != nil {
		return err
	}

	return nil
}

func (r *PanamaxReconciler) reconcileConfigMap(instance *samplev1beta1.Panamax, request reconcile.Request) error {
	reqLogger := r.Log.WithValues("Request.Namespace", request.Namespace, "Request.Name", request.Name)
	reqLogger.Info("Reconciling ConfigMap")

	status := instance.Spec.SystemStatus
	version := instance.Spec.Version

	stdLabels := goschutils.GetStandardLabels(
		appName,
		managedBy,
		instance.Name,
		"",
		map[string]string{"app.kubernetes.io/part-of": "Panamax-Operator", "app.kubernetes.io/version": instance.Spec.Version},
		goschutils.DefaultFullNameTruncationConfig())

	// Define a configmap named index.html to replace the default panamax page
	configMap := &corev1.ConfigMap{
		ObjectMeta: metav1.ObjectMeta{
			Name:      instance.Name + "-configmap",
			Namespace: instance.Namespace,
			Labels:    stdLabels,
			Annotations: map[string]string{
				"com.ibm.license":         instance.Spec.License.License,
				"com.ibm.license.use":     instance.Spec.License.Use,
				"com.ibm.license.measure": instance.Spec.License.Measure,
			},
		},
		Data: map[string]string{
			"index.html": `
<!DOCTYPE html>
<html>
<head>
<title>Welcome to panamax!</title>
<style>
    body {
        width: 35em;
        margin: 0 auto;
        font-family: Tahoma, Verdana, Arial, sans-serif;
    }
</style>
</head>
<body>
<h1>Current system status</h1>
<p>Status: ` + status + `</p>
<p>Version: ` + version + `</p>
</body>
</html>`,
		},
	}

	// Check if the ConfigMap already exists and create it if it doesn't
	foundConfigMap := &corev1.ConfigMap{}
	createConfigMap := false
	err := r.Client.Get(context.TODO(), types.NamespacedName{Name: configMap.Name, Namespace: configMap.Namespace}, foundConfigMap)
	if err != nil && errors.IsNotFound(err) {
		reqLogger.Info("Creating ConfigMap", configMap.Namespace, configMap.Name)
		if err = controllerutil.SetControllerReference(instance, configMap, r.Scheme); err != nil {
			return err
		}
		if err = r.Client.Create(context.TODO(), configMap); err != nil {
			return err
		}
		createConfigMap = true
		foundConfigMap = configMap
	} else if err != nil {
		return err
	}

	// Check if the reconciler has been called due to an update to the ConfigMap.
	// If it has, then make a call to update it.
	if !createConfigMap && !reflect.DeepEqual(configMap.Data, foundConfigMap.Data) {
		foundConfigMap.Data = configMap.Data
		reqLogger.Info("Updating ConfigMap", configMap.Namespace, configMap.Name)
		if err = r.Client.Update(context.TODO(), foundConfigMap); err != nil {
			return err
		}
	}
	return nil
}

// reconcile the Service
func (r *PanamaxReconciler) reconcileService(instance *samplev1beta1.Panamax, request reconcile.Request) error {
	reqLogger := r.Log.WithValues("Request.Namespace", request.Namespace, "Request.Name", request.Name)
	reqLogger.Info("Reconciling Service")

	version := instance.Spec.Version

	stdLabels := goschutils.GetStandardLabels(
		appName,
		managedBy,
		instance.Name,
		"",
		map[string]string{"app.kubernetes.io/part-of": "Panamax-Operator", "app.kubernetes.io/version": instance.Spec.Version},
		goschutils.DefaultFullNameTruncationConfig())

	selectorLabels := goschutils.GetStandardLabels(
		appName,
		managedBy,
		instance.Name,
		"",
		map[string]string{"app.kubernetes.io/part-of": "Panamax-Operator", "app.kubernetes.io/version": version, "deployment": instance.Name + "-deployment"},
		goschutils.DefaultFullNameTruncationConfig())

	// Define the desired Service object
	service := &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{
			Name:      instance.Name + "-service",
			Namespace: instance.Namespace,
			Labels:    stdLabels,
		},
		Spec: corev1.ServiceSpec{
			Selector: selectorLabels,
			Type:     "NodePort",
			Ports: []corev1.ServicePort{
				{
					Name:       "panamax",
					Port:       8080,
					Protocol:   "TCP",
					TargetPort: intstr.Parse("8080"),
				},
			},
		},
	}

	// Check if the Service already exists and create it if it doesn't
	foundService := &corev1.Service{}
	createService := false
	err := r.Client.Get(context.TODO(), types.NamespacedName{Name: service.Name, Namespace: service.Namespace}, foundService)
	if err != nil && errors.IsNotFound(err) {
		reqLogger.Info("Creating Service", service.Namespace, service.Name)
		if err = controllerutil.SetControllerReference(instance, service, r.Scheme); err != nil {
			return err
		}
		err = r.Client.Create(context.TODO(), service)
		if err != nil {
			return err
		}
		createService = true
		foundService = service

	} else if err != nil {
		return err
	}

	//check to see if the service was modified, update if it was
	if !createService && !reflect.DeepEqual(service.Spec, service.Spec) {
		foundService.Spec = service.Spec
		reqLogger.Info("Updating Service", service.Namespace, service.Name)
		err = r.Client.Update(context.TODO(), foundService)
		if err != nil {
			return err
		}
	}
	return nil
}

//reconcile the route
func (r *PanamaxReconciler) reconcileRoute(instance *samplev1beta1.Panamax, request reconcile.Request) error {
	reqLogger := r.Log.WithValues("Request.Namespace", request.Namespace, "Request.Name", request.Name)
	reqLogger.Info("Reconciling Route")

	stdLabels := goschutils.GetStandardLabels(
		appName,
		managedBy,
		instance.Name,
		"",
		map[string]string{"app.kubernetes.io/part-of": "Panamax-Operator", "app.kubernetes.io/version": instance.Spec.Version},
		goschutils.DefaultFullNameTruncationConfig())

	routeName, err := goschutils.GetRouteName(instance.Name, instance.Namespace, "http")
	// The only reason why err will be not nil is if we cannot create a valid route due to the namespace length
	if err != nil {
		return err
	}

	portnum := intstr.FromString("8080")
	route := &routev1.Route{
		ObjectMeta: metav1.ObjectMeta{
			Name:      routeName,
			Namespace: instance.Namespace,
			Labels:    stdLabels,
		},
		Spec: routev1.RouteSpec{
			Path: "/",
			Port: &routev1.RoutePort{
				TargetPort: portnum,
			},
			To: routev1.RouteTargetReference{
				Kind: "Service",
				Name: instance.Name + "-service",
			},
		},
	}
	// Check if the route already exists and create it if it doesn't
	foundRoute := &routev1.Route{}
	createRoute := false
	err = r.Client.Get(context.TODO(), types.NamespacedName{Name: route.Name, Namespace: route.Namespace}, foundRoute)
	if err != nil && errors.IsNotFound(err) {
		createRoute = true
		foundRoute = route
		reqLogger.Info("Creating Route", route.Namespace, route.Name)
		if err := controllerutil.SetControllerReference(instance, route, r.Scheme); err != nil {
			return err
		}
		err = r.Client.Create(context.TODO(), route)
		if err != nil {
			return err
		}
	} else if err != nil {
		return err
	}

	// Check if the reconciler has been called due to an update to the Route.
	// If it has, then make a call to update it.
	if !createRoute && !reflect.DeepEqual(route.Spec.To, foundRoute.Spec.To) && !reflect.DeepEqual(route.Spec.Port, foundRoute.Spec.Port) && !reflect.DeepEqual(route.Spec.Path, foundRoute.Spec.Path) {
		foundRoute.Spec = route.Spec
		reqLogger.Info("Updating Route", route.Namespace, route.Name)
		err = r.Client.Update(context.TODO(), foundRoute)
		if err != nil {
			return err
		}
	}
	return nil
}

// reconcile the deployment
func (r *PanamaxReconciler) reconcileDeployment(instance *samplev1beta1.Panamax, request reconcile.Request) error {
	reqLogger := r.Log.WithValues("Request.Namespace", request.Namespace, "Request.Name", request.Name)
	reqLogger.Info("Reconciling Deployment")

	status := instance.Spec.SystemStatus
	version := instance.Spec.Version

	stdLabels := goschutils.GetStandardLabels(
		appName,
		managedBy,
		instance.Name,
		"",
		map[string]string{"app.kubernetes.io/part-of": "Panamax-Operator", "app.kubernetes.io/version": instance.Spec.Version},
		goschutils.DefaultFullNameTruncationConfig())

	selectorLabels := goschutils.GetStandardLabels(
		appName,
		managedBy,
		instance.Name,
		"",
		map[string]string{"app.kubernetes.io/part-of": "Panamax-Operator", "app.kubernetes.io/version": version, "deployment": instance.Name + "-deployment"},
		goschutils.DefaultFullNameTruncationConfig())

	image := os.Getenv("RELATED_IMAGE_PANAMAX")
	if image == "" {
		// nginx:1.17.9
		image = "cp.icr.io/cp/ibm-panamax-nginx@sha256:8223ffae31b299220a3f7ff21c7afde6478cdfb0bf4d1886525a4e1105341741"
	}

	//user := int64(0)
	deploy := &appsv1.Deployment{
		ObjectMeta: metav1.ObjectMeta{
			Name:      instance.Name + "-deployment",
			Namespace: instance.Namespace,
			Labels:    stdLabels,
		},
		Spec: appsv1.DeploymentSpec{
			Selector: &metav1.LabelSelector{
				MatchLabels: selectorLabels,
			},
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{
					Labels: selectorLabels,
					Annotations: map[string]string{
						"productName":    "Reference Product",
						"productID":      "fbf6a96d49214c0abc6a3bc5da6e48cd",
						"productVersion": "v2.0.6",
						"productMetric":  "FREE",
					},
				},
				Spec: corev1.PodSpec{
					ServiceAccountName: SAName,
					Containers: []corev1.Container{
						{
							Name:            instance.Name + "-panamax",
							Image:           image,
							ImagePullPolicy: "Always",
							SecurityContext: &corev1.SecurityContext{
								// RunAsUser:                &user,
								RunAsNonRoot:             func(b bool) *bool { return &b }(false),
								Privileged:               func(b bool) *bool { return &b }(false),
								ReadOnlyRootFilesystem:   func(b bool) *bool { return &b }(false),
								AllowPrivilegeEscalation: func(b bool) *bool { return &b }(false),
								Capabilities: &corev1.Capabilities{
									Drop: []corev1.Capability{
										// comment needed capabilities
										// "CHOWN",
										// "DAC_OVERRIDE",
										// "SETGID",
										// "SETUID",
										// "NET_BIND_SERVICE",
										"FOWNER",
										"FSETID",
										"SETPCAP",
										"NET_RAW",
										"SYS_CHROOT",
										"MKNOD",
										"AUDIT_WRITE",
										"SETFCAP",
									},
								},
							},
							Env: []corev1.EnvVar{
								{
									Name:  "status",
									Value: status,
								},
							},
							Ports: []corev1.ContainerPort{
								{
									Name:          "http",
									ContainerPort: 8080,
								},
							},
							Resources: corev1.ResourceRequirements{
								Limits: corev1.ResourceList{
									corev1.ResourceCPU:    *resource.NewMilliQuantity(100, resource.DecimalSI),
									corev1.ResourceMemory: *resource.NewQuantity(128*1024*1024, resource.BinarySI),
								},
								Requests: corev1.ResourceList{
									corev1.ResourceCPU:    *resource.NewMilliQuantity(100, resource.DecimalSI),
									corev1.ResourceMemory: *resource.NewQuantity(128*1024*1024, resource.BinarySI),
								},
							},
							VolumeMounts: []corev1.VolumeMount{
								{
									Name:      instance.Name + "-volumemount",
									MountPath: "/usr/share/nginx/html",
								},
							},
							LivenessProbe: &corev1.Probe{
								Handler: corev1.Handler{
									HTTPGet: &corev1.HTTPGetAction{
										Path: "/",
										Port: intstr.IntOrString{
											Type:   intstr.Int,
											IntVal: int32(8080),
										},
									},
								},
								InitialDelaySeconds: 30,
								PeriodSeconds:       5,
							},
							ReadinessProbe: &corev1.Probe{
								Handler: corev1.Handler{
									HTTPGet: &corev1.HTTPGetAction{
										Path: "/",
										Port: intstr.IntOrString{
											Type:   intstr.Int,
											IntVal: int32(8080),
										},
									},
								},
								InitialDelaySeconds: 15,
								PeriodSeconds:       5,
							},
						},
					},
					Affinity: &corev1.Affinity{
						NodeAffinity: &corev1.NodeAffinity{
							RequiredDuringSchedulingIgnoredDuringExecution: &corev1.NodeSelector{
								NodeSelectorTerms: []corev1.NodeSelectorTerm{
									{
										MatchExpressions: []corev1.NodeSelectorRequirement{
											{
												Key:      "beta.kubernetes.io/arch",
												Operator: corev1.NodeSelectorOpIn,
												Values: []string{
													"amd64",
												},
											},
										},
									},
								},
							},
							PreferredDuringSchedulingIgnoredDuringExecution: []corev1.PreferredSchedulingTerm{
								{
									Weight: int32(3),
									Preference: corev1.NodeSelectorTerm{
										MatchExpressions: []corev1.NodeSelectorRequirement{
											{
												Key:      "beta.kubernetes.io/arch",
												Operator: corev1.NodeSelectorOpIn,
												Values: []string{
													"amd64",
												},
											},
										},
									},
								},
							},
						},
					},
					Volumes: []corev1.Volume{
						{
							Name: instance.Name + "-volumemount",
							VolumeSource: corev1.VolumeSource{
								ConfigMap: &corev1.ConfigMapVolumeSource{
									LocalObjectReference: corev1.LocalObjectReference{
										Name: instance.Name + "-configmap",
									},
								},
							},
						},
					},
				},
			},
		},
	}

	// Check if the Deployment already exists and create it if it doesn't
	foundDeployment := &appsv1.Deployment{}
	createDeployment := false
	err := r.Client.Get(context.TODO(), types.NamespacedName{Name: deploy.Name, Namespace: deploy.Namespace}, foundDeployment)
	if err != nil && errors.IsNotFound(err) {
		createDeployment = true
		reqLogger.Info("Creating Deployment", deploy.Namespace, deploy.Name)
		if err := controllerutil.SetControllerReference(instance, deploy, r.Scheme); err != nil {
			return err
		}
		err = r.Client.Create(context.TODO(), deploy)

		// create failed setup status to indicate
		if err != nil {
			err = r.updatePanamaxStatus(instance, "initialFail")
			if err != nil {
				reqLogger.Info("updatePanamaxStatus", "Error updating Panamax Status:", err)
				return err
			}
		}

		// create initiated OK
		createDeployment = true
		foundDeployment = deploy

		// setup the initial status for panamax instance just created
		err = r.updatePanamaxStatus(instance, "initial")
		if err != nil {
			reqLogger.Info("updatePanamaxStatus", "Error updating Panamax Status:", err)
			return err
		}

	} else if err != nil {
		return err
	}

	reqLogger.Info("Going to check for deployment spec updates", deploy.Namespace, deploy.Name, "generation", foundDeployment.ObjectMeta.Generation, "observed", foundDeployment.Status.ObservedGeneration)
	// Check if the reconciler has been called due to an update to the Deployment.
	// If it has, then make a call to update it.
	if !createDeployment && !reflect.DeepEqual(deploy.Spec, foundDeployment.Spec) {
		//if !createDeployment && !reflect.DeepEqual(deploy.Spec.Template.Spec, foundDeployment.Spec.Template.Spec) {
		//if !createDeployment && foundDeployment.ObjectMeta.Generation != foundDeployment.Status.ObservedGeneration {
		reqLogger.Info("Updating Deployment", deploy.Namespace, deploy.Name, "generation", foundDeployment.ObjectMeta.Generation, "observed", foundDeployment.Status.ObservedGeneration)
		//foundDeployment.Spec.Template.Spec = deploy.Spec.Template.Spec

		//when I do this I no longer detect any changes even when I edit the resource and change something!~!
		//deploy.DeepCopyInto(foundDeployment)

		deploy.Spec.DeepCopyInto(&foundDeployment.Spec)

		if reflect.DeepEqual(deploy.Spec, foundDeployment.Spec) {
			// shows that things are now deeply equal
			reqLogger.Info("deploy.spec and found.spec are now deeply equal")
		} else {
			reqLogger.Info("deploy.spec and found.spec are STILL NOT deeply equal, EVEN AFTER DeepCopyInto!!!!!!!")
		}

		//this update will cause a new generation to be added
		err = r.Client.Update(context.TODO(), foundDeployment)
		if err != nil {
			return err
		}

		// use the status of the deployment to derive the status for the panamax instance
		// this should really be a deeper check into the overall health, maybe actually trying to
		// use the route generated
		for _, condition := range foundDeployment.Status.Conditions {

			if condition.Type == "Available" {
				if condition.Status == corev1.ConditionTrue {
					err = r.updatePanamaxStatus(instance, "available")
					if err != nil {
						reqLogger.Info("Condition Status Loop", "Error updating Panamax Status:", err)
						return err
					}
				} else {
					err = r.updatePanamaxStatus(instance, "notAvailable")
					if err != nil {
						reqLogger.Info("Condition Status Loop", "Error updating Panamax Status:", err)
						return err
					}
				}
			}
		}
	}
	return nil
}

func pavEquals(lhs samplev1beta1.PanamaxAvailableVersions, rhs samplev1beta1.PanamaxAvailableVersions) bool {
	// Here we check the version strings match, instead of a
	// direct in memory comparision of the struct literals
	return lhs.Name == rhs.Name
}

func versionArrayContains(versionsArray []samplev1beta1.PanamaxAvailableVersions, theVersion samplev1beta1.PanamaxAvailableVersions) bool {
	for _, n := range versionsArray {
		if pavEquals(theVersion, n) {
			return true
		}
	}
	return false
}

func validateOperandVersion(versionsArray []samplev1beta1.PanamaxAvailableVersions, theVersion samplev1beta1.PanamaxAvailableVersions) error {
	if !versionArrayContains(versionsArray, theVersion) {
		e := fmt.Errorf("Specified version %q not supported.  Please reference the following supported versions: %v", theVersion, versionsArray)
		return e
	}
	return nil
}

// Reconcile reads that state of the cluster for a Panamax object and makes changes based on the state read
// and what is in the Panamax.Spec
// Note:
// The Controller will requeue the Request to be processed again if the returned error is non-nil or
// Result.Requeue is true, otherwise upon completion it will remove the work from the queue.
func (r *PanamaxReconciler) Reconcile(ctx context.Context, request reconcile.Request) (reconcile.Result, error) {
	reqLogger := r.Log.WithValues("Request.Namespace", request.Namespace, "Request.Name", request.Name)
	reqLogger.Info("***Reconciling Panamax resource***")

	// Fetch the Panamax instance
	instance := &samplev1beta1.Panamax{}
	err := r.Client.Get(context.TODO(), request.NamespacedName, instance)
	if err != nil {
		if errors.IsNotFound(err) {
			// Object not found, return.  Created objects are automatically garbage collected.
			// For additional cleanup logic use finalizers.
			return reconcile.Result{}, nil
		}
		// Error reading the object - requeue the request.
		return reconcile.Result{}, err
	}

	// Populate version status of the panamax object
	r.populateAvailableVersions(instance)

	version := instance.Spec.Version
	licenseAccept := instance.Spec.License.Accept

	//reqLogger.Info("version:", "version:", version)
	reqLogger.Info("licenseAccept:", "licenseAccept:", licenseAccept)

	versionErr := validateOperandVersion(
		instance.Status.Version.Available.Versions,
		samplev1beta1.PanamaxAvailableVersions{Name: version},
	)
	if versionErr != nil {
		if instance.Status.Version.Available.Versions == nil || len(instance.Status.Version.Available.Versions) == 0 {
			instance.Status.Version.Available.Versions = []samplev1beta1.PanamaxAvailableVersions{{Name: version}}
		} else {
			reqLogger.Info(versionErr.Error())
			return reconcile.Result{}, err
		}
	}

	if !licenseAccept {
		reqLogger.Info("Must accept terms of license")
		return reconcile.Result{}, fmt.Errorf("must accept terms of license")
	}

	err = r.reconcileRBAC(instance, request)
	if err != nil {
		return reconcile.Result{}, err
	}

	err = r.reconcileConfigMap(instance, request)
	if err != nil {
		return reconcile.Result{}, err
	}

	err = r.reconcileDeployment(instance, request)
	if err != nil {
		return reconcile.Result{}, err
	}

	err = r.reconcileService(instance, request)
	if err != nil {
		return reconcile.Result{}, err
	}

	err = r.reconcileRoute(instance, request)
	if err != nil {
		return reconcile.Result{}, err
	}

	return reconcile.Result{}, nil
}

// Update the status conditions for the Panamax object. There is likely a cleaner way to do this.
func (r *PanamaxReconciler) updatePanamaxStatus(instance *samplev1beta1.Panamax, state string) error {
	// If the Panamax object has an existing conditions list, then we need to either append or update

	var pa []samplev1beta1.PanamaxCondition

	switch state {

	case "initial":
		pa = []samplev1beta1.PanamaxCondition{
			{
				Type:    samplev1beta1.PanamaxConditionStarted,
				Status:  corev1.ConditionTrue,
				Reason:  "PanamaxInit",
				Message: "Panamax is intializing",
			},
			{
				Type:    samplev1beta1.PanamaxConditionCompleted,
				Status:  corev1.ConditionFalse,
				Reason:  "PanamaxNotReady",
				Message: "Panamax is not Ready",
			},
			{
				Type:    samplev1beta1.PanamaxConditionFailed,
				Status:  corev1.ConditionFalse,
				Reason:  "PanamaxUnhealthy",
				Message: "Panamax is healthy",
			},
			{
				Type:    samplev1beta1.PanamaxConditionConnected,
				Status:  corev1.ConditionFalse,
				Reason:  "Panamax not yet connected to couchDB",
				Message: "Panamax trying to connect",
			},
		}

	case "initialFail":
		pa = []samplev1beta1.PanamaxCondition{
			{
				Type:    samplev1beta1.PanamaxConditionStarted,
				Status:  corev1.ConditionFalse,
				Reason:  "PanamaxInit",
				Message: "Panamax is not intializing",
			},
			{
				Type:    samplev1beta1.PanamaxConditionCompleted,
				Status:  corev1.ConditionFalse,
				Reason:  "PanamaxNotReady",
				Message: "Panamax is not Ready",
			},
			{
				Type:    samplev1beta1.PanamaxConditionFailed,
				Status:  corev1.ConditionTrue,
				Reason:  "PanamaxUnhealthy",
				Message: "Panamax failed",
			},
			{
				Type:    samplev1beta1.PanamaxConditionConnected,
				Status:  corev1.ConditionFalse,
				Reason:  "Panamax failed to connect to couchDB",
				Message: "Panamax failed to connect to couchDB",
			},
		}

	case "available":
		pa = []samplev1beta1.PanamaxCondition{
			{
				Type:    samplev1beta1.PanamaxConditionStarted,
				Status:  corev1.ConditionTrue,
				Reason:  "PanamaxInit",
				Message: "Panamax has Started",
			},
			{
				Type:    samplev1beta1.PanamaxConditionCompleted,
				Status:  corev1.ConditionTrue,
				Reason:  "PanamaxReady",
				Message: "Panamax is Ready",
			},
			{
				Type:    samplev1beta1.PanamaxConditionFailed,
				Status:  corev1.ConditionFalse,
				Reason:  "PanamaxUnhealthy",
				Message: "Panamax is healthy",
			},
			{
				Type:    samplev1beta1.PanamaxConditionConnected,
				Status:  corev1.ConditionTrue,
				Reason:  "Panamax sucessfully connected to couchDB",
				Message: "Panamax sucessfully connected to couchDB",
			},
		}

	case "notAavailable":
		pa = []samplev1beta1.PanamaxCondition{
			{
				Type:    samplev1beta1.PanamaxConditionStarted,
				Status:  corev1.ConditionTrue,
				Reason:  "PanamaxInit",
				Message: "Panamax has Started",
			},
			{
				Type:    samplev1beta1.PanamaxConditionCompleted,
				Status:  corev1.ConditionFalse,
				Reason:  "PanamaxReady",
				Message: "Panamax is Running",
			},
			{
				Type:    samplev1beta1.PanamaxConditionFailed,
				Status:  corev1.ConditionTrue,
				Reason:  "PanamaxUnhealthy",
				Message: "Panamax is not yet healthy",
			},
			{
				Type:    samplev1beta1.PanamaxConditionConnected,
				Status:  corev1.ConditionTrue,
				Reason:  "Panamax connection not healthy",
				Message: "Panamax connection not healthy",
			},
		}
	}

	// var panamaxReconVer = samplev1beta1.PanamaxReconciledVersions{
	// 	Reconciled: reconciledVersion,
	// 	Available:  panamaxAvailableVersions,
	// }

	panamaxStatus := samplev1beta1.PanamaxStatus{
		//		Version:    panamaxReconVer,
		Name:       instance.Name,
		Conditions: pa,
	}

	//	instance.Status.Version = panamaxStatus.Version
	instance.Status.Conditions = panamaxStatus.Conditions
	instance.Status.Name = panamaxStatus.Name

	return r.Client.Update(context.Background(), instance)
}

func (r *PanamaxReconciler) populateAvailableVersions(instance *samplev1beta1.Panamax) error {
	// Get PanamaxConfig
	var existingConfigList samplev1beta1.PanamaxConfigList
	r.Client.List(context.Background(), &existingConfigList, client.InNamespace(instance.Namespace))
	for _, crconfig := range existingConfigList.Items {
		log.Info("found crconfig", "crconfig", crconfig)

		// Declare an array for both available versions and channels
		var panamaxAvailableVersionsArray []samplev1beta1.PanamaxAvailableVersions
		var panamaxAvailableChannelsArray []samplev1beta1.PanamaxAvailableChannels

		// Loop through available versions specified in PananmaxConfig and put them in an array
		for z, theVersion := range crconfig.Spec.SupportedOperandVersions {
			log.Info("In the version for loop", "z", z)

			var availver = samplev1beta1.PanamaxAvailableVersions{
				Name: theVersion,
			}
			panamaxAvailableVersionsArray = append(panamaxAvailableVersionsArray, availver)
		}

		// Loop through available channels specified in PananmaxConfig and put them in an array
		for i, theChannel := range crconfig.Spec.SupportedOperandChannels {
			log.Info("In theChannel for loop", "i", i)

			var availChannel = samplev1beta1.PanamaxAvailableChannels{
				Name: theChannel,
			}
			panamaxAvailableChannelsArray = append(panamaxAvailableChannelsArray, availChannel)
		}

		// Populate the PanamaxAvailable object with version and channel array
		panamaxAvailable := samplev1beta1.PanamaxAvailable{
			Versions: panamaxAvailableVersionsArray,
			Channels: panamaxAvailableChannelsArray,
		}

		var panamaxReconVer = samplev1beta1.PanamaxReconciledVersions{
			Reconciled: instance.Spec.Version,
			Available:  panamaxAvailable,
		}

		panamaxStatus := samplev1beta1.PanamaxStatus{
			Version: panamaxReconVer,
		}

		instance.Status.Version = panamaxStatus.Version

		log.Info("Available Status", "Available Status", panamaxAvailable)
		log.Info("Reconciled Status", "Reconciled Status", panamaxReconVer, "Single Reconciled Version", panamaxReconVer.Reconciled)
	}

	return nil
}
