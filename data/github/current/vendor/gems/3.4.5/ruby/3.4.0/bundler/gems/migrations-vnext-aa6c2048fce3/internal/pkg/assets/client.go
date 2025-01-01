// Package assets contains clients to upload asset files.
package assets

import (
	"context"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
)

// Uploader defines asset upload client capabilities.
type Uploader interface {
	PostMultipart(ctx context.Context, headers, formData map[string]string, r io.Reader, uploadURL, fileName string) ([]byte, error)
}

// UploadClient has methods to upload to the uploadURL using the set client.
type UploadClient struct {
	httpClient *http.Client
}

// NewUploadClient returns a configured UploadClient.
func NewUploadClient() *UploadClient {
	return &UploadClient{
		httpClient: &http.Client{},
	}
}

// PostMultipart uploads data from the Reader to the uploadURL efficiently.
func (c UploadClient) PostMultipart(ctx context.Context, headers, formData map[string]string, r io.Reader, uploadURL, fileName string) ([]byte, error) {
	pr, pw := io.Pipe()
	writer := multipart.NewWriter(pw)

	go func() {
		defer func() {
			// We must close the writer before the pipe writer.
			if err := writer.Close(); err != nil {
				_ = pw.CloseWithError(fmt.Errorf("failed to close multipart writer: %w", err))
				return
			}
			_ = pw.Close()
		}()

		for k, v := range formData {
			if err := writer.WriteField(k, v); err != nil {
				_ = pw.CloseWithError(err)
				return
			}
		}

		part, err := writer.CreateFormFile("file", fileName)
		if err != nil {
			_ = pw.CloseWithError(err)
			return
		}

		if _, err := io.Copy(part, r); err != nil {
			_ = pw.CloseWithError(err)
			return
		}
	}()

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, uploadURL, pr)
	if err != nil {
		return nil, err
	}

	req.Header.Set("Content-Type", writer.FormDataContentType())

	for k, v := range headers {
		req.Header.Set(k, v)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, err
	}

	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("asset upload failed with status '%d' body '%s'", resp.StatusCode, string(body))
	}

	return io.ReadAll(resp.Body)
}
