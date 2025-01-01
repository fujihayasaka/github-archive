package zson

import (
	"bytes"
	"compress/gzip"
	"encoding/json"
	"io"

	"github.com/pkg/errors"
)

// Marshal converts the provided object to a ZSON-encoded byte array
//
// ZSON is just JSON that's gzipped. The same `json` struct tag applies for configuring how the value is marshalled.
func Marshal(a interface{}) ([]byte, error) {
	var buf bytes.Buffer
	j, err := json.Marshal(a)
	if err != nil {
		return nil, errors.WithStack(err)
	}
	gz := gzip.NewWriter(&buf)
	_, err = gz.Write(j)
	if err != nil {
		return nil, errors.WithStack(err)
	}

	// We don't need to `defer` Close because it's not holding any OS resources
	// But we do need to close before we have a valid buffer (to write the gzip footer)
	err = gz.Close()
	if err != nil {
		return nil, errors.WithStack(err)
	}

	return buf.Bytes(), nil
}

// Marshal decodes the provided ZSON-encoded byte array into the provided object.
//
// ZSON is just JSON that's gzipped. The same `json` struct tag applies for configuring how the value is unmarshalled.
func Unmarshal(b []byte, a interface{}) error {
	reader := bytes.NewReader(b)
	gz, err := gzip.NewReader(reader)
	if err != nil {
		return errors.WithStack(err)
	}
	buf, err := io.ReadAll(gz)
	if err != nil {
		return errors.WithStack(err)
	}
	return json.Unmarshal(buf, a)
}
