package main

import (
	"context"
	"errors"
	"fmt"
	"net/http"

	rpc "github.com/github/trust-metadata-api/pkg/rpc/v0"
	"github.com/spf13/cobra"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/encoding/protojson"
)

func runGetAttest(_ *cobra.Command, _ []string) error {
	if err := checkGetPackageAttestationsRequiredFlags(config); err != nil {
		return err
	}

	BaseURL := config.BaseURL
	httpClient, err := getHMACHTTPClient(config)
	if err != nil {
		return fmt.Errorf("Error creating HMAC HTTP Client: %w", err)
	}

	readClient := rpc.NewPackageInfoReadAPIProtobufClient(BaseURL, httpClient)

	// Add header
	headers := make(http.Header)
	headers.Set("X-HMAC-Client-Id", "npm/read")
	ctx := context.Background()
	ctx, err = twirp.WithHTTPRequestHeaders(ctx, headers)
	if err != nil {
		return err
	}
	msg, err := readClient.GetPackageAttestations(ctx, &rpc.GetPackageAttestationsRequest{
		Purl: config.Purl,
	})

	if err != nil {
		return fmt.Errorf("Error getting attestations: %w", err)
	}

	for _, attestation := range msg.Attestations {
		marshalled, err := protojson.MarshalOptions{Indent: "  "}.Marshal(attestation)
		if err != nil {
			return fmt.Errorf("Error marshalling attestation: %w", err)
		}
		fmt.Println(string(marshalled))
	}
	return nil
}

// parse command line flags and environment variables
func initGetPackageCommand(runFn func(*cobra.Command, []string) error) *cobra.Command {
	var cmdGetPackageAttestations = &cobra.Command{
		Use:              "get-package-attestations",
		Short:            "Get the attestations by purl",
		PersistentPreRun: initConfig,
		RunE:             runFn,
	}

	cmdGetPackageAttestations.PersistentFlags().StringP("hmac-key", "k", "", "HMAC key")
	cmdGetPackageAttestations.PersistentFlags().StringP("purl", "p", "", "purl")

	cmdGetPackageAttestations.Flags().String("base-url", DefaultBaseURL, "Endpoint Base URL")

	return cmdGetPackageAttestations
}

func checkGetPackageAttestationsRequiredFlags(c configStruct) error {
	if c.HMACKey == "" {
		return errors.New("Missing HMAC Key")
	}

	if c.Purl == "" {
		return errors.New("Missing Purl")
	}

	return nil
}
