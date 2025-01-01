package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"

	"google.golang.org/protobuf/encoding/protojson"

	"github.com/spf13/cobra"

	rpc "github.com/github/trust-metadata-api/pkg/rpc/v0"
	v1 "github.com/sigstore/protobuf-specs/gen/pb-go/bundle/v1"
	"github.com/twitchtv/twirp"
)

func runCreateAttest(_ *cobra.Command, _ []string) error {
	if err := checkCreatePackageAttestation(config); err != nil {
		return err
	}

	BaseURL := config.BaseURL
	httpClient, err := getHMACHTTPClient(config)
	if err != nil {
		return fmt.Errorf("Error creating HMAC HTTP Client: %w", err)
	}

	writeClient := rpc.NewPackageInfoWriteAPIProtobufClient(BaseURL, httpClient)

	var bundle *v1.Bundle
	if config.Bundle == "-" {
		// Read from stdin
		bundle, err = getBundleFromReader()
	} else {
		bundle, err = getBundleFromFilename(config.Bundle)
	}

	if err != nil {
		return fmt.Errorf("Error getting bundle: %w", err)
	}

	// Add header
	headers := make(http.Header)
	headers.Set("X-HMAC-Client-Id", "uploading-worker")
	ctx := context.Background()
	ctx, err = twirp.WithHTTPRequestHeaders(ctx, headers)
	if err != nil {
		return err
	}
	_, err = writeClient.CreatePackageAttestation(ctx, &rpc.CreatePackageAttestationRequest{
		Purl:   config.Purl,
		Bundle: bundle,
	})

	if err != nil {
		return fmt.Errorf("Error creating attestation: %w", err)
	}
	fmt.Println("Created ", config.Purl)

	return nil
}

// parse command line flags and environment variables
func initCreatePackageCommand(runFn func(*cobra.Command, []string) error) *cobra.Command {
	var cmdCreatePackageAttestation = &cobra.Command{
		Use:              "create-package-attestation",
		Short:            "Create the attestation",
		PersistentPreRun: initConfig,
		RunE:             runFn,
	}

	cmdCreatePackageAttestation.PersistentFlags().StringP("hmac-key", "k", "", "HMAC key")
	cmdCreatePackageAttestation.PersistentFlags().StringP("purl", "p", "", "Purl")
	cmdCreatePackageAttestation.PersistentFlags().StringP("bundle", "b", "", "Bundle")

	cmdCreatePackageAttestation.Flags().String("base-url", DefaultBaseURL, "Endpoint Base URL")

	return cmdCreatePackageAttestation
}

func getBundleFromFilename(filename string) (*v1.Bundle, error) {
	bundle := &v1.Bundle{}

	bundleBytes, err := os.ReadFile(filename)
	if err != nil {
		return bundle, err
	}

	err = protojson.Unmarshal(bundleBytes, bundle)
	if err != nil {
		return bundle, err
	}

	return bundle, nil
}

func getBundleFromReader() (*v1.Bundle, error) {
	bundle := &v1.Bundle{}

	var b json.RawMessage
	dec := json.NewDecoder(os.Stdin)
	err := dec.Decode(&b)
	// Read stdin as raw JSON
	if err != nil {
		return bundle, err
	}

	// Unmarshal the raw JSON into a bundle
	err = protojson.Unmarshal(b, bundle)
	if err != nil {
		return bundle, err
	}

	return bundle, nil
}

func checkCreatePackageAttestation(c configStruct) error {
	if c.HMACKey == "" {
		return errors.New("Missing HMAC Key")
	}

	if c.Purl == "" {
		return errors.New("Missing Purl")
	}

	if c.Bundle == "" {
		return errors.New("Missing Bundle")
	}

	return nil
}
