package store

import (
	"io"
)

// errorLimitReader is a limit reader that emits an error after count
// bytes rather than returning a io.EOF
type errorLimitReader struct {
	io.Reader
	count int64
	err   error
}

// NewErrorLimitReader will return err when count bytes have been read
// if count is zero or negative then no limit will be applied
func NewErrorLimitReader(r io.Reader, maxSize int64, err error) io.Reader {
	if maxSize > 0 {
		return &errorLimitReader{Reader: r, count: maxSize, err: err}
	}
	return r
}

func (r *errorLimitReader) Read(p []byte) (n int, err error) {
	n, err = r.Reader.Read(p)
	r.count -= int64(n)
	if r.count <= 0 {
		return n, r.err
	}
	return
}
