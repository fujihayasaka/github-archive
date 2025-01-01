package shared

import (
	"fmt"

	"github.com/github/authnd/client"
	"github.com/pkg/errors"
	"github.com/spf13/cobra"
)

type ConnectionInfo struct {
	addr           string
	environment    string
	hmacKey        string
	hmacValue      string
	catalogService string
	cmd            *cobra.Command
}

func RegisterConnectionFlags(info *ConnectionInfo, cmd *cobra.Command) {
	cmd.Flags().StringVar(&info.addr, "addr", "", "Service address. Overrides the environment default.")
	cmd.Flags().StringVarP(&info.environment, "environment", "E", "", "An environment name to connect to. Defaults to 'development'.")
	cmd.Flags().StringVar(&info.hmacKey, "hmac-key", "octocat", "HMAC secret key.")
	cmd.Flags().StringVarP(&info.hmacValue, "request-hmac", "H", "", "[required for PROD connection] The literal Request-HMAC value, which can be acquired through the '.authnd hmac' chatop.")
	cmd.Flags().StringVar(&info.catalogService, "catalog-service", "authnd", "The catalog service to associate the call with. Defaults to 'authnd'.")
	info.cmd = cmd
}

func (c *ConnectionInfo) getConnectionInfo() ([]client.Option, error) {
	verbose, err := c.cmd.Flags().GetBool("verbose")
	if err != nil {
		return nil, err
	}

	envConfig, ok := GetEnvConfig(c.environment)
	if !ok {
		return nil, errors.Errorf("unknown environment '%s'", c.environment)
	}

	if c.addr == "" {
		c.addr = envConfig.AuthndBaseUrl
	}

	if verbose {
		fmt.Println("Using endpoint: ", c.addr)
	}

	options := []client.Option{}
	if c.hmacValue != "" {
		options = append(options, client.WithHMAC(c.hmacValue))
	} else if c.hmacKey != "" {
		options = append(options, client.WithHMACKey(c.hmacKey))
	}

	if verbose {
		options = append(options, client.WithVerboseRequestLogging())
	}

	return options, nil
}

func (c *ConnectionInfo) NewAuthenticator() (client.Authenticator, error) {
	options, err := c.getConnectionInfo()
	if err != nil {
		return nil, err
	}

	authenticator, err := client.NewAuthenticator(c.addr, c.catalogService, options...)
	if err != nil {
		return nil, err
	}
	return authenticator, nil
}

func (c *ConnectionInfo) NewExchanger() (client.TokenExchanger, error) {
	options, err := c.getConnectionInfo()
	if err != nil {
		return nil, err
	}

	exchanger, err := client.NewTokenExchanger(c.addr, c.catalogService, options...)
	if err != nil {
		return nil, err
	}
	return exchanger, nil
}

func (c *ConnectionInfo) NewCredentialManager() (client.CredentialManager, error) {
	options, err := c.getConnectionInfo()
	if err != nil {
		return nil, err
	}

	cm, err := client.NewCredentialManager(c.addr, c.catalogService, options...)
	if err != nil {
		return nil, err
	}
	return cm, nil
}

func (c *ConnectionInfo) NewMobileDeviceManager() (client.MobileDeviceManager, error) {
	options, err := c.getConnectionInfo()
	if err != nil {
		return nil, err
	}

	cm, err := client.NewMobileDeviceManager(c.addr, c.catalogService, options...)
	if err != nil {
		return nil, err
	}
	return cm, nil
}
