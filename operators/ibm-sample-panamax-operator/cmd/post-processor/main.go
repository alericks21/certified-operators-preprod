package main

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

// fix things that could not be auto generated
// 1. add relatedImages
// 2. make sure all alm-examples have a "status: {}" block
// 3. make sure webhook ports are setup correctly
// 4. make sure panamax crd has accept enum and required elements setup correctly
// TODO: 5. add labels
// 6. fixup manifest file in deploy folder

var rootCommand = &cobra.Command{
	Use:       "post-processor",
	Short:     "Command line interface to fixup elements that cannot be automatically generated with SDK",
	Args:      cobra.OnlyValidArgs,
	ValidArgs: []string{"fixBundle", "fixDeploy"},
	PersistentPreRun: func(*cobra.Command, []string) {
		fmt.Println("add things that always run here")
	},
}

func init() {
	// add subcommands
	rootCommand.AddCommand(
		FixBundleCommand(),
		FixDeployCommand(),
		FixDigestsCommand(),
	)
}

var csvFile string
var relatedImagesFile string
var crdFile string
var arch string
var nativeDeployFile string

// FixBundleCommand updates the csv and panamax crd file for things that the sdk does not currently generate but that are required
func FixBundleCommand() *cobra.Command {
	fixBundleCmd := &cobra.Command{
		Use:   "fixBundle",
		Short: "Command to fixup the operator bundle directory files",
		Args: func(cmd *cobra.Command, args []string) error {
			return nil
		},
		Run: func(cmd *cobra.Command, args []string) {
			fmt.Println("this is the fixBundle cmd")
			// check if cli params match
			if csvFile == "" {
				fmt.Printf("Missing csv file")
				os.Exit(1)
			}

			// check if cli params match
			if relatedImagesFile == "" {
				fmt.Printf("Missing relatedImages comma sep val file")
				os.Exit(1)
			}

			// check if cli params match
			if crdFile == "" {
				fmt.Printf("Missing csv file")
				os.Exit(1)
			}

			err := fixALMExamples(csvFile)
			if err != nil {
				fmt.Println("fixALMExamples error", err)
				return
			}

			err = fixWebhook(csvFile)
			if err != nil {
				fmt.Println("fixWebhook error", err)
				return
			}

			err = addRelatedImages(csvFile, relatedImagesFile, arch)
			if err != nil {
				fmt.Println("fixWebhook error", err)
				return
			}

			err = fixCRD(crdFile)
			if err != nil {
				fmt.Println("fixALMExamples error", err)
				return
			}
		},
	}
	fixBundleCmd.Flags().StringVarP(&csvFile, "csvFile", "c", "", "CSV file in bundle")
	fixBundleCmd.Flags().StringVarP(&relatedImagesFile, "relatedImagesFile", "r", "", "File containing all the related images to add to csv")
	fixBundleCmd.Flags().StringVarP(&crdFile, "crdFile", "d", "", "CRD file in bundle to fix")
	fixBundleCmd.Flags().StringVarP(&arch, "arch", "a", "", "Related image architecture to add to CSV")

	//fixBundleCmd.MarkFlagRequired("repoPath")
	return fixBundleCmd
}

// FixDeployCommand updates the non-olm native yaml file
func FixDeployCommand() *cobra.Command {
	fixDeployCmd := &cobra.Command{
		Use:   "fixDeploy",
		Short: "Command to fixup the operator deploy directory files",
		Args: func(cmd *cobra.Command, args []string) error {
			return nil
		},
		Run: func(cmd *cobra.Command, args []string) {
			fmt.Println("this is the fixDeploy cmd")
			err := fixDeploy(nativeDeployFile)
			if err != nil {
				fmt.Println("fixALMExamples error", err)
				return
			}
		},
	}
	fixDeployCmd.Flags().StringVarP(&nativeDeployFile, "nativeDeployFile", "n", "", "manifestsNativeDeploy.yaml file in the deploy folder to fix up")
	return fixDeployCmd
}

func FixDigestsCommand() *cobra.Command {
	fixDigestsCmd := &cobra.Command{
		Use:   "fixDigests",
		Short: "Command to update the digests in your relatedImages.csv",
		Args: func(cmd *cobra.Command, args []string) error {
			return nil
		},
		Run: func(cmd *cobra.Command, args []string) {
			err := updateCSVDigests(relatedImagesFile)
			if err != nil {
				fmt.Printf("Error updating the related images CSV: %s\n", err)
				return
			}
		},
	}
	fixDigestsCmd.Flags().StringVarP(&relatedImagesFile, "relatedImagesFile", "r", "", "File containing all the related images to add to csv")
	return fixDigestsCmd
}

func main() {
	err := rootCommand.Execute()
	if err != nil {
		fmt.Println("error in main", err)
		return
	}
}
