package utils

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	yaml "gopkg.in/yaml.v3"
)

const (
	SharedDevImagesSubscriptionId = "9ed6f940-4ca4-4512-a8f8-a08f8d151201" // GitHub - NonProd - Compute Products - Actions Platform
	SharedDevImagesErrorMessage   = "failed to perform operation. It is not allowed to access shared azure subscription because it is read-only"
)

func getScriptOutput(scriptPath string, args ...string) (string, error) {
	_, utilsDir, _, _ := runtime.Caller(1) // <root>/internal/utils/test_utils.go
	fullScriptPath := filepath.Join(utilsDir, "../../..", scriptPath)

	cmd := exec.Command(fullScriptPath, args...)

	var stdoutBuffer, stderrBuffer bytes.Buffer
	cmd.Stdout = &stdoutBuffer
	cmd.Stderr = &stderrBuffer

	err := cmd.Run()
	scriptOutput := strings.Trim(stdoutBuffer.String(), "\n")
	scriptError := strings.Trim(stderrBuffer.String(), "\n")
	if err != nil {
		return "", fmt.Errorf("script '%s' failed with error '%s'.\n Stdout: %s \n Stderr: %s", fullScriptPath, err.Error(), scriptOutput, scriptError)
	}

	if scriptError != "" {
		return "", fmt.Errorf("script '%s' finished but stderr is not empty.\n Stdout: %s \n Stderr: %s", fullScriptPath, scriptOutput, scriptError)
	}

	return scriptOutput, nil
}

func getDevConfigsDirectory() (string, error) {
	if testing.Testing() {
		_, currentFilePath, _, _ := runtime.Caller(0)
		return path.Join(currentFilePath, "../../..", "config/kustomize/devoverlays"), nil
	}

	exePath, err := os.Executable()
	if err != nil {
		return "", fmt.Errorf("failed to get executable path: %w", err)
	}

	exeDir := filepath.Dir(exePath)
	return filepath.Join(exeDir, "config"), nil
}

func GetMinikubeIp() (string, error) {
	output, err := getScriptOutput("script/helpers/kube-ip")
	if err != nil {
		return "", fmt.Errorf("failed to retrieve minikube ip: %w", err)
	}

	return output, nil
}

func GenerateImageVhdUrl(imageName string) (string, error) {
	output, err := getScriptOutput("script/generate-vhd-url", "--image", imageName)
	if err != nil {
		return "", fmt.Errorf("failed to generate image vhd url: %w", err)
	}

	return output, nil
}

func GetDevConfig[T any](configName string) (*T, error) {
	configDir, err := getDevConfigsDirectory()
	if err != nil {
		return nil, fmt.Errorf("failed to locate dev config: %w", err)
	}

	configPath := filepath.Join(configDir, configName)
	configContentRaw, err := os.ReadFile(configPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read config file on path '%s': %w", configPath, err)
	}

	var parsedConfig T
	err = yaml.Unmarshal(configContentRaw, &parsedConfig)
	if err != nil {
		return nil, fmt.Errorf("failed to parse config file on path '%s': %w", configPath, err)
	}

	return &parsedConfig, nil
}
