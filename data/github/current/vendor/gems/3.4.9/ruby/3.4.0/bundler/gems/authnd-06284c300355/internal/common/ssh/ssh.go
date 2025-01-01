package ssh

import (
	"crypto/sha256"
	"encoding/base64"
	"strings"

	"github.com/pkg/errors"
)

// RemoveOptionalComment removes optional comment on an SSH key.
// The public key must be in the OpenSSH authorized keys format, without options,
// specifically:
//
// algo base64 [optional comment]
//
// This format is enforced in the public_key table by virtue of
// https://github.com/github/ssh_data/blob/master/lib/ssh_data.rb#L14
func RemoveOptionalComment(publicKey string) (string, error) {
	algo, encodedKey, err := ParseSSHKey(publicKey)
	if err != nil {
		return "", err
	}
	return strings.Join([]string{algo, encodedKey}, " "), nil
}

// ParseSSHKey parses and validates the different segments of the SSH key.
// The public key must be in the OpenSSH authorized keys format, without options,
// specifically:
//
// algo base64 [optional comment]
//
// This format is enforced in the public_key table by virtue of
// https://github.com/github/ssh_data/blob/master/lib/ssh_data.rb#L14
func ParseSSHKey(publicKey string) (string, string, error) {
	fields := strings.Fields(publicKey)
	if len(fields) < 2 {
		return "", "", errors.Errorf("malformed public key: %q", publicKey)
	}
	return fields[0], fields[1], nil
}

// GenerateSHA256 returns the user presentation of the key's fingerprint.
// The public key must be in the OpenSSH authorized keys format, without options,
// specifically:
//
// algo base64 [optional comment]
//
// This format is enforced in the public_key table by virtue of
// https://github.com/github/ssh_data/blob/master/lib/ssh_data.rb#L14
func GenerateSHA256(publicKey string) (string, error) {
	_, encodedKey, err := ParseSSHKey(publicKey)
	if err != nil {
		return "", err
	}

	b64 := []byte(encodedKey)
	key := make([]byte, base64.StdEncoding.DecodedLen(len(b64)))
	n, err := base64.StdEncoding.Decode(key, b64)
	if err != nil {
		return "", errors.Wrapf(err, "cannot decode public key %q", encodedKey)
	}

	sha256sum := sha256.Sum256(key[:n])
	return base64.RawStdEncoding.EncodeToString(sha256sum[:]), nil
}

// MustGenerateSHA256 calls GenerateSHA256 and panics on error
func MustGenerateSHA256(publicKey string) string {
	str, err := GenerateSHA256(publicKey)
	if err != nil {
		panic(err)
	}
	return str
}
