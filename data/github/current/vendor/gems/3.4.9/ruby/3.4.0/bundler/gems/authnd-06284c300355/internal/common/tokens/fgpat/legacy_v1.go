package fgpat

import (
	"crypto/sha256"
	"encoding/base32"
	"fmt"
	"io"
	"strings"

	"github.com/pkg/errors"
)

const (
	legacyV1TokenLength = 85
)

func newLegacyV1Token(header interface{}, randomSource io.Reader) (*Token, error) {
	v1Header, ok := header.(*V1Header)
	if !ok {
		return nil, errors.New("header must be a V1Header")
	}

	// Generate the random value
	random, err := randomString(v1RandomLength, alphanumeric, randomSource)
	if err != nil {
		return nil, err
	}

	// Encode the header
	headerString, err := v1Header.marshal(randomSource)
	if err != nil {
		return nil, err
	}

	// Compute the first portion of the token (prefix, header, random)
	// since that's what the checksum is computed over

	value := fmt.Sprintf("%s_%s_%s", string(LegacyV1Prefix), headerString, random)

	// Compute the checksum
	hash := sha256.Sum256([]byte(value))
	encoded := base32.StdEncoding.EncodeToString(hash[:])
	checksum := encoded[:v1ChecksumLength]

	// Generate the suffix
	suffix, err := randomString(v1SuffixLength, alphanumeric, randomSource)
	if err != nil {
		return nil, err
	}

	// Tack on the checksum and suffix
	value = value + checksum + suffix

	return &Token{
		Prefix:   LegacyV1Prefix,
		Type:     ProgrammaticAccessTokenType,
		Header:   v1Header,
		Checksum: checksum,
		Value:    value,
	}, nil
}

func parseLegacyV1Token(value string) (*Token, error) {
	if len(value) != legacyV1TokenLength {
		return nil, errors.Errorf("token must be exactly %d characters long", legacyV1TokenLength)
	}
	token := value

	// Trim off the prefix
	idx := strings.Index(token, "_")
	token = token[idx+1:]

	// The second underscore separates header from the rest
	idx = strings.Index(token, "_")
	encodedHeader := token[:idx]

	header, err := UnmarshalV1Header(encodedHeader)
	if err != nil {
		return nil, err
	}

	token = token[idx+1:]

	// Grab the checksum off the back
	// The checksum is the set of characters immediately preceeding the suffix.
	checksum := token[len(token)-(v1SuffixLength+v1ChecksumLength) : len(token)-(v1SuffixLength)]

	return &Token{
		Prefix:   LegacyV1Prefix,
		Type:     ProgrammaticAccessTokenType,
		Header:   header,
		Checksum: checksum,
		Value:    value,
	}, nil
}
