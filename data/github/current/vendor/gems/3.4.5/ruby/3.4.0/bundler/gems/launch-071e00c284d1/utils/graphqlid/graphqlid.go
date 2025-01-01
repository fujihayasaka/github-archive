package graphqlid

import (
	"encoding/base64"
	"fmt"
	"strconv"
	"strings"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"
	"github.com/ugorji/go/codec"

	"github.com/github/launch/observability/kvperrors"
)

var encoding = base64.StdEncoding
var encodingURL = base64.RawURLEncoding

// Decode extracts the underlying type and ID for the given type and ID.
// Supports both encoding formats
func Decode(encoded string) (typeName string, id string, err error) {
	if strings.Contains(encoded, "_") {
		return decodeNextGlobalID(encoded)
	}
	return decodeLegacyGlobalID(encoded)
}

// DecodeTypeIntID extracts the underlying type and ID as an int64 for the given
// type and IDs
func DecodeTypeIntID(encoded string) (typeName string, id int64, err error) {
	typeName, idString, err := Decode(encoded)
	if err != nil {
		return "", 0, err
	}

	idInt64, err := strconv.ParseInt(idString, 10, 64)
	if err != nil {
		return "", 0, errors.Errorf("Relay ID id part `%s' was not an int", idString)
	}

	return typeName, idInt64, nil
}

func DecodeInt64ID(encoded string) (int64, error) {
	_, idString, err := Decode(encoded)
	if err != nil {
		return 0, err
	}

	idInt, err := strconv.ParseInt(idString, 10, 64)
	if err != nil {
		return 0, errors.Errorf("Relay ID id part `%s' was not an int", idString)
	}

	return idInt, nil
}

// Decode extracts the underlying type and ID for the given type and ID.
func decodeLegacyGlobalID(encoded string) (typeName string, id string, err error) {
	decoded, err := encoding.DecodeString(encoded)
	if err != nil {
		return "", "", newDecodeError("(Legacy) Invalid base64-encoding", encoded)
	}
	if len(decoded) == 0 {
		return "", "", newDecodeError("(Legacy) Empty GlobalID", "")
	}
	typeLenBytes, data := divideBytes(decoded[1:], ':')
	if len(data) == 0 {
		return "", "", newDecodeError("(Legacy) No ':' found", encoded)
	}
	typeLen, err := strconv.ParseInt(string(typeLenBytes), 10, 64)
	if err != nil {
		return "", "", newDecodeError(fmt.Sprintf("(Legacy) Error parsing type name length: %q", err), encoded)
	}
	if typeLen >= int64(len(data)) {
		return "", "", newDecodeError("(Legacy) Type name length is too high", encoded)
	}

	typeName = string(data[:typeLen])
	id = string(data[typeLen:])
	err = nil

	return
}

// Decode extracts the underlying type and ID for the given type and ID.
// / See the dotcom implementation for more details around implementation:
// / https://github.com/github/github/blob/3b21d005e78cf9f495f9f7c36ebdcc460db792aa/lib/platform/helpers/global_id.rb#L5
func decodeNextGlobalID(encoded string) (typeName string, id string, err error) {
	var msgpackHandle codec.MsgpackHandle
	parts := strings.SplitN(encoded, "_", 2)
	if len(parts) != 2 {
		return "", "", newDecodeError("Missing type separator '_'", encoded)
	}
	typeHint := parts[0]

	// Get typeName from prefix
	typeName, ok := prefixToTypeName[typeHint]
	if !ok {
		return "", "", newDecodeError("Invalid type prefix", encoded)
	}

	idPart := parts[1]

	idPartTrimmed := strings.TrimSpace(idPart)

	if len(idPartTrimmed) == 0 {
		return "", "", newDecodeError("Next generation global ids must have an ownership array encoding", encoded)
	}

	// Base64 URLEncoding decode
	packedMsg, err := encodingURL.DecodeString(idPartTrimmed)
	if err != nil {
		return "", "", newDecodeError("Invalid base64-UrlEncoding", encoded)
	}

	// MessagePack decode
	// The packed messages for the global id types Launch decodes contain only integers
	var decodedPackedPath []uint64
	dec := codec.NewDecoderBytes(packedMsg, &msgpackHandle)
	err = dec.Decode(&decodedPackedPath)
	if err != nil {
		return "", "", newDecodeError("Invalid MessagePack encoding", encoded)
	}

	if len(decodedPackedPath) < 2 {
		return "", "", newDecodeError("Next generation global ids must have at least two integers in the ownership array", encoded)
	}

	idInt := decodedPackedPath[len(decodedPackedPath)-1]
	id = fmt.Sprint(idInt)

	err = nil

	return typeName, id, err
}

func newDecodeError(message, encoded string) error {
	return kvperrors.With(message, kvp.String("graphql.operation.name", "GraphQLIDDecodeError"), kvp.String("encoded", encoded))
}

// divideBytes splits a byte slice into two parts, based on a given separator.
func divideBytes(data []byte, sep byte) ([]byte, []byte) {
	for i, c := range data {
		if c == sep {
			return data[:i], data[i+1:]
		}
	}
	return data, []byte{}
}

var prefixToTypeName = map[string]string{
	"R":   "Repository",
	"U":   "User",
	"O":   "Organization",
	"CR":  "CheckRun",
	"CS":  "CheckSuite",
	"BOT": "Bot",
	"E":   "Enterprise",
	"EN":  "Environment",
	"M":   "Mannequin",
	"A":   "App",
	"GA":  "Gate",
}
