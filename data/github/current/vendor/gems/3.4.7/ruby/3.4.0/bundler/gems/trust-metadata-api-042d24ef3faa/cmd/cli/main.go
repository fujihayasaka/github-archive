package main

import (
	"net/http"
	"strings"

	"github.com/spf13/cobra"
	"github.com/spf13/viper"

	twcauth "github.com/github/go-twirp/v2/client/auth"
)

const (
	// DefaultBaseURL is the default base URL for the TMA API
	DefaultBaseURL = "http://localhost:8080"
)

// configStruct is the struct that holds the configuration for the application
type configStruct struct {
	HMACKey string `mapstructure:"hmac-key"`
	BaseURL string `mapstructure:"base-url"`
	Purl    string `mapstructure:"purl"`
	Bundle  string `mapstructure:"bundle"`
}

var config configStruct

func initConfig(cmd *cobra.Command, _ []string) {
	viper.SetEnvPrefix("TMA")
	viper.AutomaticEnv()
	viper.SetEnvKeyReplacer(strings.NewReplacer("-", "_"))

	err := viper.BindPFlags(cmd.Flags())
	cobra.CheckErr(err)

	err = viper.Unmarshal(&config)
	cobra.CheckErr(err)
}

// generate the HMAC client based on the HMAC key
func getHMACHTTPClient(c configStruct) (*twcauth.BodyHMACSigner, error) {
	HMACkey := c.HMACKey
	return twcauth.NewBodyHMACSigner(HMACkey, http.DefaultClient)
}

func main() {
	rootCmd := &cobra.Command{Use: "tma-cli"}
	rootCmd.CompletionOptions.DisableDefaultCmd = true
	rootCmd.AddCommand(initGetPackageCommand(runGetAttest), initCreatePackageCommand(runCreateAttest))

	if err := rootCmd.Execute(); err != nil {
		cobra.CheckErr(err)
	}
}
