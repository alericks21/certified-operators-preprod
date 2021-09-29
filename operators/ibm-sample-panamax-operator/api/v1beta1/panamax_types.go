package v1beta1

import (
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

const (
	PANAMAX_GROUP       string = "sample.ibm.com"
	PANAMAX_API_VERSION string = "v1beta1"
	PANAMAX_KIND        string = "Panamax"
)

// PanamaxSpec defines the desired state of Panamax
type PanamaxSpec struct {
	// +operator-sdk:csv:customresourcedefinitions:type=spec,displayName="Operand Running Status",xDescriptors="urn:alm:descriptor:com.tectonic.ui:text"
	SystemStatus string `json:"systemStatus,omitempty"`

	// +operator-sdk:csv:customresourcedefinitions:type=spec,displayName="Operand Version",xDescriptors="urn:alm:descriptor:com.tectonic.ui:text"
	Version string `json:"version,omitempty"`

	// +operator-sdk:csv:customresourcedefinitions:type=spec,displayName="Operand License Structure",xDescriptors="urn:alm:descriptor:com.tectonic.ui:text"
	License PanamaxLicense `json:"license,omitempty"`
}

type PanamaxLicense struct {
	// +operator-sdk:csv:customresourcedefinitions:type=spec,displayName="Accept Operand License",xDescriptors="urn:alm:descriptor:com.tectonic.ui:booleanSwitch"
	Accept bool `json:"accept,omitempty"`

	// +operator-sdk:csv:customresourcedefinitions:type=spec
	License string `json:"license,omitempty"`

	// +operator-sdk:csv:customresourcedefinitions:type=spec
	Use string `json:"use,omitempty"`

	// +operator-sdk:csv:customresourcedefinitions:type=spec
	Measure string `json:"measure,omitempty"`

	// +operator-sdk:csv:customresourcedefinitions:type=spec
	KeyFrom PanamaxKey `json:"keyFrom,omitempty"`
}

type PanamaxKey struct {
	// +operator-sdk:csv:customresourcedefinitions:type=spec
	SecretKeyRef SecretRef `json:"secretKeyRef,omitempty"`
}

type SecretRef struct {
	// +operator-sdk:csv:customresourcedefinitions:type=spec,displayName="Operand License Key",xDescriptors="urn:alm:descriptor:io.kubernetes:Secret"
	Name string `json:"name,omitempty"`
}

// PanamaxStatus defines the observed state of Panamax
type PanamaxStatus struct {
	// +operator-sdk:csv:customresourcedefinitions:type=status
	Name string `json:"name"`

	// +operator-sdk:csv:customresourcedefinitions:type=status
	Conditions []PanamaxCondition `json:"conditions,omitempty"`

	// +operator-sdk:csv:customresourcedefinitions:type=status
	Version PanamaxReconciledVersions `json:"versions,omitempty"`
}

type PanamaxAvailable struct {

	// +operator-sdk:csv:customresourcedefinitions:type=status
	Versions []PanamaxAvailableVersions `json:"versions,omitempty"`

	// +operator-sdk:csv:customresourcedefinitions:type=status
	Channels []PanamaxAvailableChannels `json:"channels,omitempty"`
}

type PanamaxAvailableVersions struct {

	// +operator-sdk:csv:customresourcedefinitions:type=status
	Name string `json:"name"`
}

type PanamaxAvailableChannels struct {

	// +operator-sdk:csv:customresourcedefinitions:type=status
	Name string `json:"name"`
}

type PanamaxReconciledVersions struct {

	// +operator-sdk:csv:customresourcedefinitions:type=status
	Reconciled string `json:"reconciled"` // Reconciled is a required field, so need to remove the omitempty JSON tag

	// +operator-sdk:csv:customresourcedefinitions:type=status
	Available PanamaxAvailable `json:"available,omitempty"`
}

type PanamaxCondition struct {

	// +operator-sdk:csv:customresourcedefinitions:type=status
	Type PanamaxConditionType `json:"type"`

	// +operator-sdk:csv:customresourcedefinitions:type=status
	Status corev1.ConditionStatus `json:"status"`

	// +operator-sdk:csv:customresourcedefinitions:type=status
	Reason string `json:"reason,omitempty"`

	// +operator-sdk:csv:customresourcedefinitions:type=status
	Message string `json:"message,omitempty"`
}

type PanamaxConditionType string

const (
	PanamaxConditionStarted   PanamaxConditionType = "Started"
	PanamaxConditionCompleted PanamaxConditionType = "Completed"
	PanamaxConditionFailed    PanamaxConditionType = "Failed"
	PanamaxConditionConnected PanamaxConditionType = "ConnectedToCouchDB"
)

// +kubebuilder:object:root=true

// Panamax is the Schema for the nginxes API
// +operator-sdk:csv:customresourcedefinitions:displayName="Panamax Custom Implementation",resources={{Panamaxes,v1beta1,""},{Deployments,v1,""},{Replicasets,v1,""},{Route,v1,""},{Services,v1,""},{Pods,v1,""},{ConfigMaps,v1,""}}
type Panamax struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   PanamaxSpec   `json:"spec,omitempty"`
	Status PanamaxStatus `json:"status,omitempty"`
}

// PanamaxList contains a list of Panamax
// +kubebuilder:object:root=true
type PanamaxList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []Panamax `json:"items"`
}

func init() {
	SchemeBuilder.Register(&Panamax{}, &PanamaxList{})
}
