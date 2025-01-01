package ts

import (
	"crypto/sha1" // nolint:gosec // G505 this is just of matching file contents
	"database/sql/driver"

	"github.com/pkg/errors"
)

const (
	FileChecksumSize = sha1.Size
)

type Sha1Checksum [FileChecksumSize]byte

func (h Sha1Checksum) Value() (driver.Value, error) {
	b := make([]byte, FileChecksumSize)
	copy(b, h[:FileChecksumSize])
	return b, nil
}

func (h *Sha1Checksum) Scan(val interface{}) error {
	v, ok := val.([]byte)
	if !ok {
		return errors.Errorf("Unsupported type: %T", v)
	}
	copy(h[:], v[:FileChecksumSize])
	return nil
}

func BuildFileChecksum(content []byte) Sha1Checksum {
	h := sha1.New() // nolint:gosec // G401 this does not have to be cryptographically secure
	h.Write(content)
	var checksum Sha1Checksum
	copy(checksum[:], h.Sum(nil)[:FileChecksumSize])
	return checksum
}
