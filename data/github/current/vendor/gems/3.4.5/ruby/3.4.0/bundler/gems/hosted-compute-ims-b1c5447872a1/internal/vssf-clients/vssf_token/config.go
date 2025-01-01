package vssf_token

import (
	"io"
	"os"
	"path/filepath"

	"github.com/github/go-config"
)

type Config struct {
	ImageManagementServicePEM             string `config:",env=TOKEN_PEM"`
	ImageManagementServicePEMFAllBackFile string `config:"token.pem,env=IMS_PEM_Fallback_File"`
	TokenUrl                              string `config:"http://vstoken.codedev.ms/,env=TOKEN_URL"`
}

func (c *Config) Load() error {
	err := config.Load(c)
	if err != nil {
		return err
	}

	if c.ImageManagementServicePEM == "" {
		exePath, err := os.Executable()
		if err != nil {
			return err
		}
		exeDir := filepath.Dir(exePath)

		filePath := filepath.Join(exeDir, c.ImageManagementServicePEMFAllBackFile)

		file, err := os.Open(filePath)
		if err != nil {
			// If the file doesn't exist we're going to ignore it and continue.
			// This should only be the case on test runs and the ims specific codespace.
			// We would log here, but we initialize the logger after this is called.
			return nil
		}
		defer file.Close()

		fileContents, err := io.ReadAll(file)
		if err != nil {
			return err
		}

		c.ImageManagementServicePEM = string(fileContents)
	}

	return nil
}
