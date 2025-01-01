package azureblob

import "fmt"

// ErrBlobDownloadFailed represents an error created when the service cannot
// download a blob from Azure Blob Storage successfully.
type ErrBlobDownloadFailed struct {
	wrapped error
}

func (e *ErrBlobDownloadFailed) Error() string {
	msg := "failed to download blob"
	if e.wrapped == nil {
		return msg
	}
	return fmt.Sprintf("%s: %s", msg, e.wrapped.Error())
}

func (e *ErrBlobDownloadFailed) Unwrap() error {
	return e.wrapped
}

// ErrBlobUploadFailed represents an error created when the service cannot
// upload a blob to Azure Blob Storage successfully.
type ErrBlobUploadFailed struct {
	wrapped error
}

func (e *ErrBlobUploadFailed) Error() string {
	msg := "failed to upload blob"
	if e.wrapped == nil {
		return msg
	}
	return fmt.Sprintf("%s: %s", msg, e.wrapped.Error())
}

func (e *ErrBlobUploadFailed) Unwrap() error {
	return e.wrapped
}
