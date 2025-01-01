// Package zlib package is a wrapper about the standard compress/zlib.
// It exposes the Inflate and Deflate functions that simplify how to compress
// a given set of bytes
//
// Some tips to understand the inflate/deflate terminology:
// If you imagine a given payload as a full-blown balloon, you can reduce its size
// by removing its air, that is, by deflating it.
// To recover the balloon original form, you need to put air on it,
// that is you need to inflate it.
//
// So in general inflate means to decompress and deflate means to compress.
// This terminology is used because of the original algorithm used, and it
// is present in almost every implementation, like in Ruby zlib lib and Go package.
package zlib

import (
	"bytes"
	"compress/zlib"
	"io"

	"github.com/github/notifyd/internal/pkg/errors"
)

// Inflate takes a set of bytes and decompresses them
func Inflate(deflated []byte) ([]byte, error) {
	input := bytes.NewBuffer(deflated)
	reader, err := zlib.NewReader(input)
	if err != nil {
		return nil, errors.Wrap(err, "error creating zlib reader")
	}

	output := new(bytes.Buffer)
	for {
		if _, err := io.CopyN(output, reader, 1024); err != nil {
			if errors.Is(err, io.EOF) {
				break
			}
			return nil, errors.Wrap(err, "error decompressing zlib contents")
		}
	}

	_ = reader.Close()

	return output.Bytes(), nil
}

// Deflate takes a set of bytes and compresses them
func Deflate(inflated []byte) ([]byte, error) {
	output := new(bytes.Buffer)
	writer := zlib.NewWriter(output)
	if _, err := writer.Write(inflated); err != nil {
		return nil, errors.Wrap(err, "error compressing bytes")
	}
	_ = writer.Close()

	return output.Bytes(), nil
}
