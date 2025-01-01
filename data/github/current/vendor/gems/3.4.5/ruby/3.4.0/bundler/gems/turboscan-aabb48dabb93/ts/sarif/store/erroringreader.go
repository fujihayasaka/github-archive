package store

import (
	"io"

	"github.com/pkg/errors"
)

// erroringReader will store the last error that occurred when calling Read
type erroringReader struct {
	io.Reader
	error
}

func (r *erroringReader) Read(data []byte) (int, error) {
	count, err := r.Reader.Read(data)
	if err != nil {
		r.error = err
	}
	return count, err
}

// Error returns the last non-EOF error that occurred when calling Read
func (r *erroringReader) Error() error {
	if r.error != nil && !errors.Is(r.error, io.EOF) {
		return r.error
	}
	return nil
}
