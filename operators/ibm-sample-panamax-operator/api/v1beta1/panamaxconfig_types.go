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

package v1beta1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// PanamaxConfigSpec defines the desired state of PanamaxConfig
type PanamaxConfigSpec struct {
	// INSERT ADDITIONAL SPEC FIELDS - desired state of cluster
	// Important: Run "operator-sdk generate k8s" to regenerate code after modifying this file
	// Add custom validation using kubebuilder tags: https://book-v1.book.kubebuilder.io/beyond_basics/generating_crd.html

	// +operator-sdk:csv:customresourcedefinitions:type=spec
	SupportedOperandChannels []string `json:"supportedOperandChannels,omitempty"`

	// +operator-sdk:csv:customresourcedefinitions:type=spec
	SupportedOperandVersions []string `json:"supportedOperandVersions,omitempty"`
}

// PanamaxConfigStatus defines the observed state of PanamaxConfig
type PanamaxConfigStatus struct {
	// INSERT ADDITIONAL STATUS FIELD - define observed state of cluster
	// Important: Run "operator-sdk generate k8s" to regenerate code after modifying this file
	// Add custom validation using kubebuilder tags: https://book-v1.book.kubebuilder.io/beyond_basics/generating_crd.html

	// +operator-sdk:csv:customresourcedefinitions:type=status
	LastUpdate string `json:"lastUpdate"`
}

// +kubebuilder:object:root=true

// PanamaxConfig is the Schema for the panamaxconfigs API
// +operator-sdk:csv:customresourcedefinitions:displayName="Panamax Custom Implementation",resources={{PanamaxConfigs,v1beta1,""}}
type PanamaxConfig struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   PanamaxConfigSpec   `json:"spec,omitempty"`
	Status PanamaxConfigStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// PanamaxConfigList contains a list of PanamaxConfig
type PanamaxConfigList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []PanamaxConfig `json:"items"`
}

func init() {
	SchemeBuilder.Register(&PanamaxConfig{}, &PanamaxConfigList{})
}
