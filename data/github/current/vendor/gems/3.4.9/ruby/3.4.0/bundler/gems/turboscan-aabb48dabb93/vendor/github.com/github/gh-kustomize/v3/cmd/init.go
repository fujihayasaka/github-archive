package cmd

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"syscall"

	"github.com/spf13/cobra"
)

const (
	kustomizeBaseDir        = "base"
	kustomizationFile       = "kustomization.yaml"
	kustomizationFilePrefix = "apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\n\nresources:\n"
)

var InitCmd = setupInitCmd()

type InitCmdArgs struct {
	Override bool
	NoBuild  bool
}

var initCmdArgs = InitCmdArgs{}

// setupInitCmd returns a cobra command that initializes a kustomize project.
func setupInitCmd() *cobra.Command {
	initCmd := &cobra.Command{
		Use: "init [path/to/repo]",
		Example: "init\n" +
			"init path/to/repo",
		Short:        "Initialize a kustomize project",
		Long:         "Initialize a kustomize project with existing kubernetes configuration files",
		RunE:         getKustomizeInitCmd(),
		SilenceUsage: true,
	}

	initCmd.Flags().BoolVarP(
		&initCmdArgs.Override,
		"override",
		"o",
		false,
		"Override existing kustomize configuration files",
	)

	initCmd.Flags().BoolVar(
		&initCmdArgs.NoBuild,
		"no-build",
		false,
		"Do not build kubernetes resources after initialization",
	)

	RootCmd.AddCommand(initCmd)

	return initCmd
}

// getKustomizeInitCmd returns a cobra command that initializes a kustomize project.
func getKustomizeInitCmd() func(cmd *cobra.Command, args []string) error {
	return func(cmd *cobra.Command, args []string) error {
		kubernetesPath, kustPath, err := getAbsPaths(args, "")
		if err != nil {
			return err
		}

		if !initCmdArgs.Override {
			if _, err := os.Stat(kustPath); !os.IsNotExist(err) && !isDirEmpty(kustPath) {
				return fmt.Errorf("kustomize files already exist in %s, use --override to override them", kustPath)
			}
		}

		envs, err := getDirsFromPath(kubernetesPath)
		if err != nil {
			return err
		}

		if len(envs) == 0 {
			return fmt.Errorf("no environments found in %s", kubernetesPath)
		}

		kustOverlaysPath := fmt.Sprintf("%s/%s", kustPath, overlaysDir)
		if err := os.MkdirAll(kustOverlaysPath, 0o750); err != nil {
			return err
		}

		for _, env := range envs {
			cmd.Printf("★ Creating overlay for environment '%s'... ", env)
			kustBaseEnvPath := fmt.Sprintf("%s/%s/%s", kustPath, kustomizeBaseDir, env)
			if err := moveK8sToKustomize(kubernetesPath, env, kustBaseEnvPath); err != nil {
				cleanUpDirectory(cmd, kubernetesPath)

				return err
			}

			if err := createOverlay(kustOverlaysPath, env); err != nil {
				cleanUpDirectory(cmd, kubernetesPath)

				return err
			}
			cmd.Println("done")
		}
		cmd.Printf("✓ Successfully created kustomize files in %s\n", kustPath)

		if !initCmdArgs.NoBuild {
			if err := BuildCmd.RunE(cmd, args); err != nil {
				return err
			}
			cmd.Printf("✓ Successfully built kubernetes resources in %s\n", kubernetesPath)
		}

		return nil
	}
}

// createOverlay creates the overlay for the given environment.
func createOverlay(overlaysPath, env string) error {
	resources := []string{fmt.Sprintf("../../%s/%s", kustomizeBaseDir, env)}
	overlayPath := fmt.Sprintf("%s/%s", overlaysPath, env)

	if err := createKustomizationFile(overlayPath, resources); err != nil {
		return err
	}

	return nil
}

// moveK8sToKustomize moves the kubernetes configuration files from the given path to the given kustomize path.
func moveK8sToKustomize(kubernetesPath, env, kustomizeBaseEnvPath string) error {
	kubernetesEnvPath := fmt.Sprintf("%s/%s", kubernetesPath, env)
	if err := moveDirectory(kubernetesEnvPath, kustomizeBaseEnvPath); err != nil {
		return err
	}

	var resources []string
	if err := filepath.WalkDir(kustomizeBaseEnvPath, func(currPath string, d os.DirEntry, err error) error {
		if !d.IsDir() && d.Name() != kustomizationFile && isYAML(d.Name()) {
			relativePath := strings.Replace(currPath, kustomizeBaseEnvPath+"/", "", 1)
			resources = append(resources, relativePath)
		}

		return nil
	}); err != nil {
		return err
	}

	if err := createKustomizationFile(kustomizeBaseEnvPath, resources); err != nil {
		return err
	}

	return nil
}

// isYAML returns true if the given file is a YAML file.
func isYAML(name string) bool {
	return strings.HasSuffix(name, ".yaml") || strings.HasSuffix(name, ".yml")
}

// createKustomizationFile creates the kustomize file structure in the given path with the given resources.
func createKustomizationFile(path string, resources []string) error {
	if err := os.MkdirAll(path, 0o750); err != nil {
		return err
	}

	kustomizationPath := fmt.Sprintf("%s/%s", path, kustomizationFile)
	file, err := os.Create(kustomizationPath)
	if err != nil {
		return err
	}

	defer func(file *os.File) {
		_ = file.Close()
	}(file)

	if _, err := file.WriteString(kustomizationFilePrefix); err != nil {
		return err
	}

	for _, relativePath := range resources {
		if _, err := file.WriteString(fmt.Sprintf("  - %s\n", relativePath)); err != nil {
			return err
		}
	}

	return nil
}

// moveDirectory moves a directory from one path to another.
func moveDirectory(source, dest string) error {
	if err := os.MkdirAll(dest, os.ModePerm); err != nil {
		return err
	}

	sourceFiles, err := os.ReadDir(source)
	if err != nil {
		return err
	}

	for _, file := range sourceFiles {
		sourceFile := fmt.Sprintf("%s/%s", source, file.Name())
		destFile := fmt.Sprintf("%s/%s", dest, file.Name())

		if err := os.Rename(sourceFile, destFile); err != nil {
			if errors.Is(err, syscall.EEXIST) && initCmdArgs.Override {
				if err := removeDirectory(destFile); err != nil {
					return err
				}

				if err := os.Rename(sourceFile, destFile); err != nil {
					return err
				}
			} else {
				return err
			}

		}
	}

	if err := os.Remove(source); err != nil {
		return err
	}

	return nil
}

// getDirsFromPath returns a list of directories from a given path.
func getDirsFromPath(path string) ([]string, error) {
	var directories []string

	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer func(file *os.File) {
		_ = file.Close()
	}(file)

	fileInfo, err := file.Readdir(-1)
	if err != nil {
		return nil, err
	}

	for _, file := range fileInfo {
		if file.IsDir() {
			directories = append(directories, file.Name())
		}
	}

	return directories, nil
}

// isDirEmpty returns true if the directory is empty.
func isDirEmpty(dir string) bool {
	f, err := os.Open(dir)
	if err != nil {
		return false
	}

	defer func(f *os.File) {
		_ = f.Close()
	}(f)

	if _, err = f.Readdir(1); errors.Is(err, io.EOF) {
		return true
	}

	return false
}

// removeDirectory removes a directory and all its contents.
func removeDirectory(path string) error {
	dirRef, err := os.Open(path)
	if err != nil {
		return err
	}
	defer func(dirRef *os.File) {
		_ = dirRef.Close()
	}(dirRef)

	names, err := dirRef.Readdirnames(-1)
	if err != nil {
		return err
	}

	for _, name := range names {
		err = os.RemoveAll(filepath.Join(path, name))
		if err != nil {
			return err
		}
	}

	return os.Remove(path)
}
