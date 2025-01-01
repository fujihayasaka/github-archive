package fgpat

import (
	"crypto/sha256"
	"encoding/base32"
	"encoding/binary"
	"fmt"
	"io"
	"strconv"
	"strings"

	"github.com/pkg/errors"
)

// V1 token header
// Right now, we know we _need_ to encode the actor identity because we expect to need it for sharding somewhere down the line.
// Since V1's current target is Programatic Access Tokens, which are always held by a user, we can use a 32-bit actor identity.
// As of July 2021, we had ~85 Million user IDs.
// That represents just under 2% of the 32-bit space.
//
// In base32, a 32-bit user ID requires 8 characters.
// Which gives us 13 characters remaining.
// Since we have space, let's add a single character prefix as a "version" for the header, just in case.
// Then fill the remaining 12 characters with randomness.
//
// So, the header format is:
// * 1 character "version" (limited to alphanumeric characters)
// * 8 character base32-encoded big-endian 32-bit user ID
// * Random padding to fill to 21 characters
//
// Unfortunately, base32 uses `=` as a padding character, so we need to replace it with something that's not in the base32 character set but is still an alphanumeric character.
// Instead, we'll use `0`

type TokenType string

func (tt TokenType) Descriptor() string {
	switch tt {
	case ProgrammaticAccessTokenType:
		return "pat"
	default:
		// unknown token type
		panic(errors.Errorf("unknown token type: %s", string(tt)))
	}
}

const (
	v1TokenLength    = 93
	v1HeaderLength   = 21
	v1RandomLength   = 43
	v1SuffixLength   = 8
	v1ChecksumLength = 8

	// The only token type supported in v1 of the token header is ProgrammaticAccessTokenType, so a v1 header version implies that token type.
	ProgrammaticAccessTokenType TokenType = "1"
)

type V1Header struct {
	TokenType TokenType
	UserID    uint32
}

// We have to use a custom padding character because '=' is the default and that would break "double-clickability"
var base32ZeroPadded = base32.StdEncoding.WithPadding('0')

// NewV1Header creates a new v1 token header specifying the provided user ID.
func NewV1Header(tokenType TokenType, userID uint32) *V1Header {
	return &V1Header{
		TokenType: tokenType,
		UserID:    userID,
	}
}

// UnmarshallV1Header takes a string encoding of a V1 Token header and returns a V1Header.
func UnmarshalV1Header(payload string) (*V1Header, error) {
	if len(payload) != v1HeaderLength {
		// Invalid payload
		return nil, errors.Errorf("payload must be %d characters long, but it was %d characters long", v1HeaderLength, len(payload))
	}

	// First character is the "token type" identifier
	tokenType := payload[0:1]
	if tokenType != string(ProgrammaticAccessTokenType) {
		return nil, errors.Errorf("unsupported gh1 token header version: %s", tokenType)
	}

	// The next 8 characters are the base32-encoded user ID
	encodedUserID := payload[1:9]
	decodedUserID := make([]byte, 5)
	n, err := base32ZeroPadded.Decode(decodedUserID, []byte(encodedUserID))
	if err != nil {
		return nil, errors.WithStack(err)
	}
	if n != 4 {
		return nil, errors.Errorf("expected 4 bytes of decoded user ID, but got %d bytes decoding user ID '%d' from '%s'", n, decodedUserID, encodedUserID)
	}
	// We're using big endian just because it's what "network byte order" uses and it seems to make some sense.
	// All that matters is that it matches with the endianness of the encoding routine.
	userId := binary.BigEndian.Uint32(decodedUserID)

	// The rest doesn't matter! We can return here because the rest is just random padding to fill to 21 characters.
	return &V1Header{
		TokenType: ProgrammaticAccessTokenType,
		UserID:    userId,
	}, nil
}

func (h *V1Header) marshal(randomSource io.Reader) (string, error) {
	if h.TokenType != ProgrammaticAccessTokenType {
		return "", errors.Errorf("unsupported token type: %s", h.TokenType)
	}

	// Encode the user ID
	encodedUserID := make([]byte, 4)

	// Make sure we use the same endianness as the decoder.
	binary.BigEndian.PutUint32(encodedUserID, h.UserID)

	// We're encoding 4 bytes of data in base32
	// Base32, per RFC4648 (https://datatracker.ietf.org/doc/html/rfc4648#section-6) processes input in 40-bit chunks, turning each chunk in to 8 characters.
	// So, a 32-bit number will always encode to 8 characters.
	// A 32-bit value can be encoded in base32 using 7 characters, so there will always be a padding character at the end.
	encoded := base32ZeroPadded.EncodeToString(encodedUserID)

	// Write up the header values
	header := string(ProgrammaticAccessTokenType) + encoded

	// Fill the rest with random data
	random, err := randomString(v1HeaderLength-len(header), alphanumeric, randomSource)
	if err != nil {
		return "", errors.WithStack(err)
	}

	return header + random, nil
}

func NewV1Token(header interface{}, randomSource io.Reader) *Token {
	tk, err := newV1Token(header, randomSource)
	if err != nil {
		panic(err)
	}
	return tk
}

func newV1Token(header interface{}, randomSource io.Reader) (*Token, error) {
	v1Header, ok := header.(*V1Header)
	if !ok {
		return nil, errors.New("header must be a V1Header")
	}
	tokenVersion := 1
	tokenType := v1Header.TokenType.Descriptor()

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

	value := fmt.Sprintf("%s_%s_%d%s_%s", string(V1Prefix), tokenType, tokenVersion, headerString, random)

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
		Prefix:   V1Prefix,
		Type:     ProgrammaticAccessTokenType,
		Header:   v1Header,
		Checksum: checksum,
		Value:    value,
	}, nil
}

func parseV1Token(value string) (*Token, error) {
	if len(value) != v1TokenLength {
		return nil, errors.Errorf("token must be exactly %d characters long", v1TokenLength)
	}

	token := value

	// Trim off the prefix
	idx := strings.Index(token, "_")
	token = token[idx+1:]

	// Trim off the type
	if tt := token[0:3]; tt != ProgrammaticAccessTokenType.Descriptor() {
		return nil, errors.Errorf("unsupported type for v1 token: '%s'", tt)
	}
	token = token[4:]

	// The third underscore separates header from the rest.
	version, err := strconv.Atoi(string(token[0]))
	if err != nil {
		return nil, errors.Errorf("invalid version for v1 token: '%s'", string(token[0]))
	} else if version != 1 {
		return nil, errors.Errorf("unsupport version for v1 token: '%d'", version)
	}
	idx = strings.Index(token, "_")
	encodedHeader := token[1:idx]

	header, err := UnmarshalV1Header(encodedHeader)
	if err != nil {
		return nil, err
	}

	token = token[idx+1:]

	// Grab the checksum off the back
	// The checksum is the set of characters immediately preceeding the suffix.
	checksum := token[len(token)-(v1SuffixLength+v1ChecksumLength) : len(token)-(v1SuffixLength)]

	return &Token{
		Prefix:   V1Prefix,
		Header:   header,
		Checksum: checksum,
		Value:    value,
	}, nil
}
