package main

import (
	"encoding/csv"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"os"
	"path"
	"strings"

	"github.com/ghodss/yaml"
	v1alpha1 "github.com/operator-framework/api/pkg/operators/v1alpha1"
	opregistry "github.com/operator-framework/operator-registry/pkg/registry"
	"github.ibm.com/CloudPakOpenContent/case-spec-cli/pkg/ibmcase"
	"github.ibm.com/CloudPakOpenContent/case-spec-cli/pkg/log"
	"k8s.io/apimachinery/pkg/util/intstr"
)

// fix things that could not be auto generated
// 1. add relatedImages
// 2. make sure all alm-examples have a "status: {}" block
// 3. make sure webhook ports are setup correctly
// 4. make sure panamax crd has accept enum and required elements setup correctly
// TODO: 5. add labels
// TODO: 6. fixup manifest file in deploy folder

//RelatedImage in csv
type RelatedImage struct {
	Name  string `json:"name"`
	Image string `json:"image"`
	Tag   string `json:"tag"`
}

//RelatedImages array in csv
type RelatedImages struct {
	RelatedImages []RelatedImage `json:"relatedImages"`
}

func readYAML(data []byte) (*v1alpha1.ClusterServiceVersion, error) {
	csv := &v1alpha1.ClusterServiceVersion{}
	err := yaml.Unmarshal(data, csv)
	if err != nil {
		return nil, err
	}
	return csv, nil
}

// GetRelatedImage returns the list of associated images for the operator
func getRelatedImages(csv *opregistry.ClusterServiceVersion) (imageSet map[string]struct{}, err error) {
	var objmap map[string]*json.RawMessage
	imageSet = make(map[string]struct{})

	if err = json.Unmarshal(csv.Spec, &objmap); err != nil {
		return
	}

	rawValue, ok := objmap["relatedImages"]
	if !ok || rawValue == nil {
		return
	}

	type relatedImage struct {
		Name string `json:"name"`
		Ref  string `json:"image"`
		Tag  string `json:"tag"`
	}
	var relatedImages []relatedImage
	if err = json.Unmarshal(*rawValue, &relatedImages); err != nil {
		return
	}

	for _, img := range relatedImages {
		imageSet[img.Ref] = struct{}{}
	}

	return
}

func genRelatedImagesFromFile(relatedImagesCSV string, baYamlFile []byte, arch string) (ba []byte, err error) {
	var objmap map[string]*json.RawMessage

	csvJSON, err := yaml.YAMLToJSON(baYamlFile)
	if err != nil {
		return nil, err
	}

	csvOpReg := &opregistry.ClusterServiceVersion{}
	err = json.Unmarshal(csvJSON, &csvOpReg)
	if err != nil {
		return nil, err
	}

	// get the spec section
	if err := json.Unmarshal(csvOpReg.Spec, &objmap); err != nil {
		fmt.Println(err)
		return nil, err
	}

	csvFile, err := os.Open(relatedImagesCSV)
	if err != nil {
		fmt.Println(err)
		return nil, err
	}

	defer csvFile.Close()

	r := csv.NewReader(csvFile)
	records, err := r.ReadAll()
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}

	var relatedImage RelatedImage
	var relatedImages []RelatedImage

	for _, rec := range records {
		relatedImage.Name = rec[0]
		relatedImage.Image = rec[1]
		relatedImage.Tag = rec[2]
		foundArch := ""
		if len(rec) > 3 {
			foundArch = rec[3]
		}
		if arch == "" || foundArch == arch {
			relatedImages = append(relatedImages, relatedImage)
			fmt.Println("adding image ->", rec)
		} else {
			fmt.Println("skipping image ->", rec)
		}
	}

	// Convert to JSON
	relatedImagesBA, err := json.Marshal(relatedImages)
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}

	var relateImagesRawJSON json.RawMessage
	relateImagesRawJSON = relatedImagesBA

	objmap["relatedImages"] = &relateImagesRawJSON

	//marshall just the spec section
	updatedSpecSectionBA, err := json.Marshal(&objmap)
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}

	csvOpReg.Spec = updatedSpecSectionBA

	newCSV, err := json.Marshal(csvOpReg)

	yamlout, err := yaml.JSONToYAML(newCSV)
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}

	//println(string(yamlout))

	return yamlout, nil
}

func updateCSVDigests(relatedImagesCSV string) error {
	csvFile, err := os.Open(relatedImagesCSV)
	if err != nil {
		fmt.Printf("Error opening related images CSV: %s\n", err)
		return err
	}

	r := csv.NewReader(csvFile)
	records, err := r.ReadAll()
	if err != nil {
		fmt.Printf("Error reading related images CSV: %s\n", err)
		return err
	}

	// Close the CSV file so we can write to it later
	csvFile.Close()

	type relatedImageType struct {
		Name  string
		Image string
		Tag   string
		Arch  string
	}
	var relatedImage relatedImageType
	var relatedImages []relatedImageType

	// Allow internal registries so that the ibmcase digest code won't ignore internal registries. Unset it when we exit the function.
	os.Setenv("CASECTL_ALLOW_INTERNAL_REGISTRIES", "true")
	defer os.Unsetenv("CASECTL_ALLOW_INTERNAL_REGISTRIES")
	log.InitLogs(log.DefaultLogDir, 2)

	for _, rec := range records {
		if len(rec) < 4 {
			fmt.Printf("Record is missing one or more entries. Appending without updating: %s\n", rec)
			relatedImage.Name = rec[0]
			relatedImage.Image = rec[1]
			relatedImage.Tag = rec[2]
			relatedImage.Arch = ""
			relatedImages = append(relatedImages, relatedImage)
			continue
		}

		relatedImage.Name = rec[0]
		relatedImage.Image = rec[1]
		relatedImage.Tag = rec[2]
		relatedImage.Arch = rec[3]

		imagePath := strings.Split(relatedImage.Image, "@sha256")[0]
		imageName := path.Base(imagePath)
		imageReg := path.Dir(imagePath)
		if relatedImage.Tag == "" {
			fmt.Printf("Tag is not specified for image %s. Will be using latest\n", relatedImage.Image)
			relatedImage.Tag = "latest"
		}
		imageRegObj := ibmcase.ImageRegistry{
			Host: imageReg,
		}
		mediaType := ibmcase.MediaTypeDockerImageManifestV2
		if relatedImage.Arch == "" || relatedImage.Arch == "list" {
			mediaType = ibmcase.MediaTypeDockerImageManifestListV2
		}
		fmt.Println("", imageName, relatedImage.Tag, mediaType, imageReg)
		newDigest, err := ibmcase.GetContainerImageDigest(imageName, relatedImage.Tag, mediaType, []*ibmcase.ImageRegistry{&imageRegObj})
		if err != nil {
			fmt.Printf("Could not find digest for image: %s, error: %s. Keeping image digest the same\n", relatedImage, err)
		} else {
			relatedImage.Image = fmt.Sprintf("%s@%s", imagePath, newDigest)
		}
		relatedImages = append(relatedImages, relatedImage)
	}

	// Re-open the CSV for writing
	csvFile, err = os.Create(fmt.Sprintf("%s", relatedImagesCSV))
	if err != nil {
		fmt.Printf("Error opening related images CS for writing: %s\n", err)
		return err
	}

	fmt.Printf("Attempting to write back to %s\n", csvFile.Name())

	//Write the file back out
	w := csv.NewWriter(csvFile)

	for _, image := range relatedImages {
		line := []string{image.Name, image.Image, image.Tag, image.Arch}
		if err := w.Write(line); err != nil {
			fmt.Printf("Error writing entry back to %s. Entry may need to be manually added back to the file. Error: %s\n", csvFile.Name(), err)
		}
	}

	w.Flush()
	csvFile.Close()
	return nil
}

// GetImages returns a list of images listed in CSV (spec and deployments)
func GetImages(csvYAML []byte) []string {
	var images []string

	csv := &opregistry.ClusterServiceVersion{}
	csvJSON, err := yaml.YAMLToJSON(csvYAML)
	if err != nil {
		return images
	}

	err = json.Unmarshal(csvJSON, &csv)
	if err != nil {
		return images
	}

	imageSet, err := csv.GetOperatorImages()
	if err != nil {
		return images
	}

	relatedImgSet, err := getRelatedImages(csv)
	if err != nil {
		return images
	}

	//relatedImgSet, err = addRelatedImages(csv)
	//if err != nil {
	//	return images
	//}

	for k := range relatedImgSet {
		imageSet[k] = struct{}{}
	}

	for k := range imageSet {
		images = append(images, k)
	}

	return images
}

// make sure there is a status block for all examples, needed by new scorecard
func fixALMExamples(csvfile string) error {
	data, err := ioutil.ReadFile(csvfile)
	if err != nil {
		fmt.Println("File reading error", err)
		return err
	}

	var clusterServiceVersion = &v1alpha1.ClusterServiceVersion{}
	clusterServiceVersion, err = readYAML(data)
	if err != nil {
		fmt.Println("Error parsing csv yaml file", err)
		return err
	}

	// make sure all alm-examples have a status block, new scorecard test was failing without one
	// could not figure out how to have it automatically generated
	var examples []map[string]interface{}
	s := make(map[string]struct{})
	err = json.Unmarshal([]byte(clusterServiceVersion.Annotations["alm-examples"]), &examples)
	if err != nil {
		fmt.Println("Error unmarshalling alm-examples", err)
		return err
	}

	for index, template := range examples {
		if template["status"] == nil {
			fmt.Println("Missing status block in example, adding one")
			examples[index]["status"] = s
		}
		//fmt.Println(examples[index])
	}

	jsonBA, err := json.Marshal(&examples)
	if err != nil {
		fmt.Println("Error marshalling alm-examples", err)
		return err
	}

	clusterServiceVersion.Annotations["alm-examples"] = string(jsonBA)

	ba, err := yaml.Marshal(clusterServiceVersion)
	if err != nil {
		fmt.Println("Marshal error", err)
		return err
	}

	err = ioutil.WriteFile(csvfile, ba, 0777)
	if err != nil {
		fmt.Println("Write error", err)
		return err
	}
	return nil
}

func fixCRD(crdfile string) error {

	data, err := ioutil.ReadFile(crdfile)
	if err != nil {
		fmt.Println("File reading error", err)
		return err
	}

	jsonBA, err := yaml.YAMLToJSON(data)
	if err != nil {
		return err
	}

	var crdJSON map[string]interface{}
	//s := make(map[string]struct{})

	err = json.Unmarshal(jsonBA, &crdJSON)
	if err != nil {
		fmt.Println("Error unmarshalling alm-examples", err)
		return err
	}

	var versions []interface{}

	versions = crdJSON["spec"].(map[string]interface{})["versions"].([]interface{})

	accept := versions[0].(map[string]interface{})["schema"].(map[string]interface{})["openAPIV3Schema"].(map[string]interface{})["properties"].(map[string]interface{})["spec"].(map[string]interface{})["properties"].(map[string]interface{})["license"].(map[string]interface{})["properties"].(map[string]interface{})["accept"].(map[string]interface{})
	if accept == nil {
		fmt.Println("No license accept present Abort")
		return err
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
		return err
	}

	ba2, err := yaml.JSONToYAML(ba)
	if err != nil {
		fmt.Println("yaml convert json to yaml error", err)
		return err
	}

	err = ioutil.WriteFile(crdfile, ba2, 0777)
	if err != nil {
		fmt.Println("Write error", err)
		return err
	}
	return nil
}

func fixWebhook(csvfile string) error {

	data, err := ioutil.ReadFile(csvfile)
	if err != nil {
		fmt.Println("File reading error", err)
		return err
	}

	var clusterServiceVersion = &v1alpha1.ClusterServiceVersion{}
	clusterServiceVersion, err = readYAML(data)
	if err != nil {
		fmt.Println("Error parsing csv yaml file", err)
		return err
	}
	//fix up target and container ports
	for index, webhook := range clusterServiceVersion.Spec.WebhookDefinitions {
		if webhook.TargetPort == nil || webhook.TargetPort.IntValue() != 9443 {
			fmt.Println("need initialize/set targetPort to 9443")
			i := intstr.FromInt(9443)
			clusterServiceVersion.Spec.WebhookDefinitions[index].TargetPort = &i
		}
		if webhook.ContainerPort != 9443 {
			fmt.Println("need initialize/set containerPort to 9443")
			clusterServiceVersion.Spec.WebhookDefinitions[index].ContainerPort = 9443
		}
	}

	ba, err := yaml.Marshal(clusterServiceVersion)
	if err != nil {
		fmt.Println("Marshal error", err)
		return err
	}

	err = ioutil.WriteFile(csvfile, ba, 0777)
	if err != nil {
		fmt.Println("Write error", err)
		return err
	}

	return nil
}

func addRelatedImages(csvfile, relatedImagesFile, arch string) error {

	data, err := ioutil.ReadFile(csvfile)
	if err != nil {
		fmt.Println("File reading error", err)
		return err
	}

	var clusterServiceVersion = &v1alpha1.ClusterServiceVersion{}
	clusterServiceVersion, err = readYAML(data)
	if err != nil {
		fmt.Println("Error parsing csv yaml file", err)
		return err
	}

	ba, err := yaml.Marshal(clusterServiceVersion)
	if err != nil {
		fmt.Println("Marshal error", err)
		return err
	}

	ba, err = genRelatedImagesFromFile(relatedImagesFile, data, arch)
	if err != nil {
		fmt.Println("File reading error", err)
		return err
	}

	//images := GetImages(ba)
	//if err != nil {
	//	fmt.Println("Error parsing csv yaml file", err)
	//	return err
	//}

	//for _, image := range images {
	//	fmt.Println("image is ->", image)
	//}

	err = ioutil.WriteFile(csvfile, ba, 0777)
	if err != nil {
		fmt.Println("Write error", err)
		return err
	}

	return nil

}
