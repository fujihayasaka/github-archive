package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"os"

	"github.com/github/dependency-snapshots-api/internal/storage/blob"
)

// Usage:
//
//	$ bin/dev/upload-blob <docs/production-github-samples/sample-snapshot.json
//	$ bin/dev/upload-blob -container some-container-name <some-file.json
func main() {
	azureURL := os.Getenv("AZURE_STORAGE_BLOB_ENDPOINT")
	if azureURL == "" {
		azureURL = "http://127.0.0.1:20100/devstoreaccount1"
	}

	containerName := flag.String("container", "snapshot-blobs", "Azure Storage container name")

	flag.Parse()

	stat, _ := os.Stdin.Stat()
	if (stat.Mode() & os.ModeCharDevice) != 0 {
		fmt.Fprintf(os.Stderr, "You must pipe something to stdin to upload as a blob.\n")
		os.Exit(1)
	}

	ctx := context.Background()

	// read stdin to byte array (should be JSON)
	blobPayload, _ := io.ReadAll(os.Stdin)

	client, err := blob.CreateDevelopmentAzureBlobClient(context.Background(), azureURL, *containerName)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error creating blob client: %v\n", err)
		os.Exit(1)
	}

	blobURL, err := client.CreateBlob(ctx, "", blobPayload)

	if err != nil {
		fmt.Fprintf(os.Stderr, "Error uploading blob: %v\n", err)
		os.Exit(1)
	}

	fmt.Fprintf(os.Stderr, "Uploaded successfully!\n")
	fmt.Printf("%s\n", blobURL)
}
