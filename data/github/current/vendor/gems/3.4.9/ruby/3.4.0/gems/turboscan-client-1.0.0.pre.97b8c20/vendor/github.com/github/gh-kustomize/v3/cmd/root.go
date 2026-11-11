package cmd

import (
	"bytes"
	"fmt"
	"log"
	"os"

	"github.com/spf13/cobra"
)

const (
	SuccessExitCode      = 0
	FailureExitCode      = 1
	PanicRecoveryMessage = "An error occurred while running kustomize-cli command. " +
		"Please report this error along with the error message below to the #runtime-platform-team slack channel\n%s\n"
)

var RootCmd = &cobra.Command{
	Use:     "kustomize",
	Example: "kustomize build\nkustomize build DIR",
	Short:   "A set of commands for interacting with Kustomize",
	Long: "A set of commands for interacting with Kustomize in local environments or remotely.\n" +
		"Kustomize on TheHub:	https://thehub.github.com/epd/engineering/products-and-services/internal/moda/kustomize/\n" +
		"Kustomize homepage:	https://kustomize.io",
	Run: func(cmd *cobra.Command, args []string) {
		if len(args) == 0 {
			_ = cmd.Help()
		}
	},
}

// Execute the root command.
func Execute() (exitCode int, err error) {
	defer func() {
		if recoveredErr := recover(); recoveredErr != nil {
			errMsg := fmt.Sprintf(PanicRecoveryMessage, recoveredErr)
			fmt.Print(errMsg)
			err = fmt.Errorf("%s", errMsg)
			exitCode = FailureExitCode
		}
	}()

	if executionErr := RootCmd.Execute(); executionErr != nil {
		return FailureExitCode, executionErr
	}
	return SuccessExitCode, nil
}

// CompareFiles compares two files.
func CompareFiles(path1, path2 string) bool {
	file1, err1 := os.ReadFile(path1)

	if err1 != nil {
		log.Fatal(err1)
	}

	file2, err2 := os.ReadFile(path2)

	if err2 != nil {
		log.Fatal(err2)
	}

	return bytes.Equal(file1, file2)
}
