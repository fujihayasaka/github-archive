package common

import (
	"bytes"
	"compress/gzip"
	"io"
)

// Compress compresses a byte slice using gzip
func Compress(in []byte) ([]byte, error) {
	var b bytes.Buffer
	gz := gzip.NewWriter(&b)
	defer gz.Close()
	if _, err := gz.Write(in); err != nil {
		return nil, err
	}
	gz.Close()
	return b.Bytes(), nil
}

// Uncompress takes in a gzip'd byte slice, uncompresses it, and returns the uncompressed byte slice
func Uncompress(in []byte) ([]byte, error) {
	buf := bytes.NewBuffer(in)
	reader, err := gzip.NewReader(buf)
	if err != nil {
		return nil, err
	}
	defer reader.Close()
	unzipped, err := io.ReadAll(reader)
	if err != nil {
		return nil, err
	}
	return unzipped, nil
}
