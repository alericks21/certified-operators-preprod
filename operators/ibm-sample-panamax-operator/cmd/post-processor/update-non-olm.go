package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"strings"

	"sigs.k8s.io/yaml"
)

func fixNativeCRD(crdstring string) (string, error) {

	jsonBA, err := yaml.YAMLToJSON([]byte(crdstring))
	if err != nil {
		return "", err
	}

	var crdJSON map[string]interface{}
	//s := make(map[string]struct{})

	err = json.Unmarshal(jsonBA, &crdJSON)
	if err != nil {
		fmt.Println("Error unmarshalling alm-examples", err)
		return "", err
	}

	var versions []interface{}

	versions = crdJSON["spec"].(map[string]interface{})["versions"].([]interface{})

	accept := versions[0].(map[string]interface{})["schema"].(map[string]interface{})["openAPIV3Schema"].(map[string]interface{})["properties"].(map[string]interface{})["spec"].(map[string]interface{})["properties"].(map[string]interface{})["license"].(map[string]interface{})["properties"].(map[string]interface{})["accept"].(map[string]interface{})
	if accept == nil {
		fmt.Println("No license accept present Abort")
		return "", err
	}

	licAcceptEnum := versions[0].(map[string]interface{})["schema"].(map[string]interface{})["openAPIV3Schema"].(map[string]interface{})["properties"].(map[string]interface{})["spec"].(map[string]interface{})["properties"].(map[string]interface{})["license"].(map[string]interface{})["properties"].(map[string]interface{})["accept"].(map[string]interface{})["enum"]
	if licAcceptEnum == nil {
		fmt.Println("license accept enum is missing, need to add and set to true")
		accept["enum"] = []bool{true}

	}

	lic := versions[0].(map[string]interface{})["schema"].(map[string]interface{})["openAPIV3Schema"].(map[string]interface{})["properties"].(map[string]interface{})["spec"].(map[string]interface{})["properties"].(map[string]interface{})["license"].(map[string]interface{})
	required := versions[0].(map[string]interface{})["schema"].(map[string]interface{})["openAPIV3Schema"].(map[string]interface{})["properties"].(map[string]interface{})["spec"].(map[string]interface{})["properties"].(map[string]interface{})["license"].(map[string]interface{})["required"]
	if required == nil {
		fmt.Println("Required value of accept not set")
		lic["required"] = []string{"accept"}

	}

	ba, err := json.Marshal(crdJSON)
	if err != nil {
		fmt.Println("json marshall error", err)
		return "", err
	}

	ba2, err := yaml.JSONToYAML(ba)
	if err != nil {
		fmt.Println("yaml convert json to yaml error", err)
		return "", err
	}

	return string(ba2), nil
}

func fixDeploy(nativeFileName string) error {
	data, err := ioutil.ReadFile(nativeFileName)
	if err != nil {
		fmt.Println("File reading error", err)
		return err
	}

	// Split on ---
	result := strings.Split(string(data), "---")

	// Find the panamax CRD
	fixedUp := false
	var index int
	for i := range result {
		if strings.Contains(result[i], "panamaxes.sample.ibm.com") {
			newstring, err := fixNativeCRD(result[i])
			if err != nil {
				fmt.Println("error fixing up crd", err)
				return err
			}
			fixedUp = true
			index = i
			result[i] = newstring
			break
		}

	}

	var sb strings.Builder
	size := len(result)
	first := true
	if fixedUp {
		for i := range result {
			if first {
				sb.WriteString(result[i])
				first = false
			} else {
				if size != i {
					if index == i {
						sb.WriteString("---\n")
					} else {
						sb.WriteString("---")
					}
				}
				sb.WriteString(result[i])
			}
		}
	}

	err = ioutil.WriteFile(nativeFileName, []byte(sb.String()), 0777)
	if err != nil {
		fmt.Println("Write error", err)
		return err
	}

	return nil
}
