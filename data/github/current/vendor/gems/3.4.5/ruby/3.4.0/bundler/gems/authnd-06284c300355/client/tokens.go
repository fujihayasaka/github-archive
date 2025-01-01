package client

import (
	"crypto/sha256"
	"encoding/base32"
	"regexp"
)

// TokenRegex regular expression pattern which matches all tokens issued by authnd.
const TokenRegex = "(" +
	"gh1_[A-Za-z0-9]{21}_[A-Za-z0-9]{59}" + // legacy v1 token format (i.e. PATv2)
	"|" +
	"github_pat_[0-9][A-Za-z0-9]{21}_[A-Za-z0-9]{59}" + // v1 token format (i.e. PATv2)
	")"

// compile this once at startup
var tokenRe = regexp.MustCompile(TokenRegex)

// Yes, this list is effectively duplicated from 'internal/common/tokens/token.go'.
// Unfortunately, we're caught between a rock and an hard place.
// The server references the client, so we can't reference something from the server in the client.
// We _also_ don't want the token processing logic to live in the client code, since it's not something a client should ever do.
// All we care about here is the list of valid prefixes, so the easiest thing to do here is to just duplicate that list here.

const (
	v1ChecksumLength = 8
	v1SuffixLength   = 8
)

// IsAuthndToken returns a boolean indicating if the given token was issued directly by authnd.
// If this function returns true, the token _must_ be authenticated by authnd and cannot be authenticated against any other source.
// If this function returns false, the token _may_ be authenticated by authnd, but isn't owned by authnd, so it could also be authenticated via whatever token issuer owns the token (i.e. the Monolith)
func IsAuthndToken(token string) bool {
	return tokenRe.MatchString(token)
}

// IsChecksumValid returns a boolean indicating whether the given token has a valid checksum.  If the token was not issued by authnd, this function
// returns false.
func IsChecksumValid(token string) bool {
	if !IsAuthndToken(token) {
		return false
	}

	computeChecksum := computeV1Checksum
	checksumLength, suffixLength := v1ChecksumLength, v1SuffixLength

	if len(token) <= checksumLength+suffixLength {
		// token is too short
		return false
	}

	// trim off the random suffix
	token = token[0 : len(token)-suffixLength]
	bodyLen := len(token) - checksumLength
	// split the token body and checksum
	body, checksum := token[0:bodyLen], token[bodyLen:]

	// compute the checksum from the token body
	return checksum == computeChecksum(body)

}

func computeV1Checksum(value string) string {
	hash := sha256.Sum256([]byte(value))
	encoded := base32.StdEncoding.EncodeToString(hash[:])
	return encoded[:v1ChecksumLength]

}
