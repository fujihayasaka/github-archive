package cmd

import (
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/assets"
	"github.com/github/migrations-vnext/internal/pkg/blobstore"
	v1 "github.com/github/migrations-vnext/internal/pkg/octoshift/imports/v1"
	"github.com/spf13/cobra"
)

//nolint:gochecknoinits // inits are standard when using cobra.
func init() {
	var repositoryID, size, actorID int64
	var name, contentType, filePath string
	var assetType int32
	var azureAccountKey, azureAccountName, azureContainerName, azureURL, azureBlobPath string
	var uploadFile, uploadAzure bool

	createAssetStoragePolicyCmd.Flags().Int64Var(&repositoryID, "repository_id", 0, "ID of the repository (required)")
	createAssetStoragePolicyCmd.Flags().StringVar(&name, "name", "", "File name of the asset (required)")
	createAssetStoragePolicyCmd.Flags().Int64Var(&size, "size", 0, "Size of the asset (required)")
	createAssetStoragePolicyCmd.Flags().StringVar(&contentType, "content_type", "", "Content type of the asset (required)")
	createAssetStoragePolicyCmd.Flags().Int64Var(&actorID, "actor_id", 0, "ID of the user uploading the asset (required)")
	createAssetStoragePolicyCmd.Flags().Int32Var(&assetType, "asset_type", 1, "Type of the asset being uploaded (default: auto)")

	// Optionally, upload a local file to the asset policy.
	createAssetStoragePolicyCmd.Flags().BoolVar(&uploadFile, "file", false, "Upload local file")
	createAssetStoragePolicyCmd.Flags().StringVar(&filePath, "filepath", "", "File path to upload")

	// Optionally, upload a file from an azure URL.
	createAssetStoragePolicyCmd.Flags().BoolVar(&uploadAzure, "azure", false, "Upload file from Azure Blob Storage")
	createAssetStoragePolicyCmd.Flags().StringVar(&azureAccountKey, "azure-account-key", "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==", "Azure account key")
	createAssetStoragePolicyCmd.Flags().StringVar(&azureAccountName, "azure-account-name", "devstoreaccount1", "Azure account name")
	createAssetStoragePolicyCmd.Flags().StringVar(&azureContainerName, "azure-container-name", "default", "Azure container name")
	createAssetStoragePolicyCmd.Flags().StringVar(&azureURL, "azure-url", "http://0.0.0.0:10000", "Azure blob storage address")
	createAssetStoragePolicyCmd.Flags().StringVar(&azureBlobPath, "blob-key", "", "Blob path suffix (eg.'/releases/some-blob')")

	createAssetStoragePolicyCmd.RunE = func(cmd *cobra.Command, args []string) error {
		resp, err := client.CreateAssetStoragePolicy(cmd.Context(), &v1.CreateAssetStoragePolicyRequest{
			RepositoryId: repositoryID,
			Name:         name,
			Size:         size,
			ContentType:  contentType,
			ActorId:      actorID,
			AssetType:    v1.AssetType(assetType),
		})
		if err != nil {
			return fmt.Errorf("unable to create asset storage policy: %w", err)
		}

		uc := assets.NewUploadClient()
		headers := map[string]string{}
		for _, d := range resp.Headers {
			headers[d.Key] = d.Value
		}
		formData := map[string]string{}
		for _, d := range resp.FormData {
			formData[d.Key] = d.Value
		}

		if !uploadFile && !uploadAzure {
			fmt.Println(resp)
			return nil
		}

		var r io.Reader
		var fileName string
		if uploadFile {
			fmt.Printf("Attempting to upload file '%s' to '%s'\n", filePath, resp.UploadUrl)
			file, err := os.Open(filePath)
			if err != nil {
				return fmt.Errorf("could not open file for upload: %w", err)
			}
			defer file.Close()
			fileName = filepath.Base(filePath)
			r = file
		} else if uploadAzure {
			fmt.Printf("Attempting to upload file '%s' to '%s'\n", azureBlobPath, resp.UploadUrl)
			s, err := blobstore.NewStore(context.Background(), azureURL, azureAccountName, azureAccountKey, azureContainerName, log.NewNullLogger())
			if err != nil {
				return fmt.Errorf("could not set up blob store: %w", err)
			}
			stream, err := s.GetBlobStream(context.Background(), azureBlobPath)
			if err != nil {
				return fmt.Errorf("could not get blob stream: %w", err)
			}
			defer stream.Close()
			fileName = azureBlobPath
			r = stream
		}

		uploadResp, err := uc.PostMultipart(context.Background(), headers, formData, r, resp.UploadUrl, fileName)
		if err != nil {
			return fmt.Errorf("unable to upload: %w", err)
		}
		fmt.Println(string(uploadResp))

		return nil
	}

	rootCmd.AddCommand(createAssetStoragePolicyCmd)
}

var createAssetStoragePolicyCmd = &cobra.Command{
	Use:   "create-asset-storage-policy",
	Short: "Create an asset storage policy",
}
