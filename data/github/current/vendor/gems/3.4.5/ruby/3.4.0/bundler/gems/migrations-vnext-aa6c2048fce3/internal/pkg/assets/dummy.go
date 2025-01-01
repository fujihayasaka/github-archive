package assets

import (
	"context"
	"io"
)

// DummyUploadClient implements Uploader and is used for testing.
type DummyUploadClient struct{}

// PostMultipart uploads data from the Reader to the uploadURL efficiently.
func (d DummyUploadClient) PostMultipart(ctx context.Context, headers, formData map[string]string, r io.Reader, uploadURL, fileName string) ([]byte, error) {
	return []byte{}, nil
}
