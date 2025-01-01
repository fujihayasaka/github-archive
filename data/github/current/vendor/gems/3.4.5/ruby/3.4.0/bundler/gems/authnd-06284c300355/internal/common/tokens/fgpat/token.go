package fgpat

import (
	"crypto/rand"
	"io"
	"math/big"
	"strings"

	"github.com/github/authnd/internal/common/tokens"
	"github.com/pkg/errors"
)

type TokenPrefix string

// Currently supported token "versions" under Project Mint:
//
// v1 - token version that supports user-facing token types, including Programmatic Access
// 		tokens (aka PATv2). May support additional token types in the future.

const (
	UnknownPrefix  TokenPrefix = ""
	LegacyV1Prefix TokenPrefix = "gh1"
	V1Prefix       TokenPrefix = "github"
)

const alphanumeric = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

type Token struct {
	Prefix   TokenPrefix
	Type     TokenType
	Header   interface{}
	Checksum string

	// Value is the entire content of the token, including prefix, header, secret value, checksum and unique identifier
	Value string
}

// GenerateToken generates a new token using the provided prefix.
// If the type indicated by the prefix supports header data, the provided header data will be encoded in the token.
func GenerateToken(prefix TokenPrefix, header interface{}) (*Token, error) {
	switch prefix {
	case V1Prefix:
		return newV1Token(header, rand.Reader)
	default:
		return nil, errors.Errorf("unknown token prefix: %s", prefix)
	}
}

// ParseToken reads the provided token string and returns a Token struct.
func ParseToken(value string) (*Token, error) {
	prefix_end := strings.Index(value, "_")
	if prefix_end == -1 {
		return &Token{
			Prefix: UnknownPrefix,
			Value:  value,
		}, nil
	}

	prefix := TokenPrefix(value[:prefix_end])
	switch prefix {
	case LegacyV1Prefix:
		return parseLegacyV1Token(value)
	case V1Prefix:
		return parseV1Token(value)
	}

	return &Token{Prefix: UnknownPrefix, Value: value}, nil
}

// Hash generates a hash suitable for storing/querying hashed_identifier.
func (t *Token) Hash() string {
	return tokens.Hash(t.Value)
}

// GetSuffix returns the plaintext suffix used to identify the token in logs and for support.
func (t *Token) GetSuffix() string {
	return tokens.LastEight(t.Value)
}

// randomString generates a random string of the provided length by selecting characters from the characterSet randomly.
// characterSet must only contain ASCII characters (<= 127)
func randomString(length int, characterSet string, randomSource io.Reader) (string, error) {
	var builder strings.Builder
	builder.Grow(length)

	characterSetLength := big.NewInt(int64(len(characterSet)))

	for i := 0; i < length; i++ {
		index, err := rand.Int(randomSource, characterSetLength)
		if err != nil {
			return "", err
		}
		c := characterSet[index.Int64()]
		builder.WriteByte(c)
	}

	return builder.String(), nil
}
