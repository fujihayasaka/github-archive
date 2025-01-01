// Package main for spokes-check command-line tool.
package main

import (
	"context"
	"fmt"
	"os"
	"strings"

	"github.com/github/migrations-vnext/internal/pkg/spokes"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

var root = &cobra.Command{
	Use:   "spoke-check",
	Short: "Check if an object exists in Spokes",
	RunE:  run,
}

//nolint:gochecknoinits // Using an `init` function to add flags is standard for spf13/cobra
func init() {
	viper.AutomaticEnv()
	viper.SetEnvKeyReplacer(strings.NewReplacer("-", "_"))

	root.PersistentFlags().String("spokes-url", "", "Base URL for the Spokes API")
	viper.BindPFlag("spokes-url", root.PersistentFlags().Lookup("spokes-url")) // #nosec

	root.PersistentFlags().String("client-cert", "", "Path to client certificate for Spokes")
	viper.BindPFlag("client-cert", root.PersistentFlags().Lookup("client-cert")) // #nosec

	root.PersistentFlags().String("client-key", "", "Path to client key for Spokes")
	viper.BindPFlag("client-key", root.PersistentFlags().Lookup("client-key")) // #nosec

	root.PersistentFlags().String("ca-chain", "", "Path to CA certificate chain for Spokes")
	viper.BindPFlag("ca-chain", root.PersistentFlags().Lookup("ca-chain")) // #nosec

	root.PersistentFlags().String("hmac-key", "", "HMAC key for request authentication")
	viper.BindPFlag("hmac-key", root.PersistentFlags().Lookup("hmac-key")) // #nosec

	root.PersistentFlags().String("repo-id", "", "Repository ID to check the object in")
	viper.BindPFlag("repo-id", root.PersistentFlags().Lookup("repo-id")) // #nosec

	root.PersistentFlags().String("oid", "", "Object ID to check in the repository")
	viper.BindPFlag("oid", root.PersistentFlags().Lookup("oid")) // #nosec

	root.MarkPersistentFlagRequired("spokes-url")  // #nosec
	root.MarkPersistentFlagRequired("client-cert") // #nosec
	root.MarkPersistentFlagRequired("client-key")  // #nosec
	root.MarkPersistentFlagRequired("ca-chain")    // #nosec
	root.MarkPersistentFlagRequired("hmac-key")    // #nosec
	root.MarkPersistentFlagRequired("repo-id")     // #nosec
	root.MarkPersistentFlagRequired("oid")         // #nosec
}

func main() {
	if err := root.Execute(); err != nil {
		fmt.Println("Error:", err)
		os.Exit(1)
	}
}

func run(cmd *cobra.Command, args []string) error {
	spokesURL := viper.GetString("spokes-url")
	clientCert := viper.GetString("client-cert")
	clientKey := viper.GetString("client-key")
	caChain := viper.GetString("ca-chain")
	hmacKey := viper.GetString("hmac-key")
	repoID := viper.GetUint64("repo-id")
	oid := viper.GetString("oid")

	client, err := spokes.NewSpokesClient(spokesURL, clientCert, clientKey, caChain, hmacKey)
	if err != nil {
		fmt.Printf("Error initializing Spokes client: %v\n", err)
	}

	exists, err := client.OIDExists(context.Background(), repoID, oid)
	if err != nil {
		fmt.Printf("Error checking object existence: %v\n", err)
	}

	if exists {
		fmt.Printf("Object %s exists in repository %d\n", oid, repoID)
	} else {
		fmt.Printf("Object %s does NOT exist in repository %d\n", oid, repoID)
	}
	return nil
}
