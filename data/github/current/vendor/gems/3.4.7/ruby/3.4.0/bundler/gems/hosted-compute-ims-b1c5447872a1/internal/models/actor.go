package models

import (
	"encoding/base64"
	"fmt"
	"strconv"
	"strings"

	"github.com/ugorji/go/codec"
)

var (
	encoding    = base64.StdEncoding
	encodingURL = base64.RawURLEncoding
)

type Actor struct {
	GlobalId string
	Stamp    string
}

type DotcomActor string

func (a DotcomActor) String() string {
	return string(a)
}

func (a DotcomActor) Type() string {
	parts := strings.Split(a.String(), ":")
	if len(parts) != 2 {
		return ""
	}

	return parts[0]
}

func (a DotcomActor) Id() string {
	parts := strings.Split(a.String(), ":")
	if len(parts) != 2 {
		return ""
	}

	return parts[1]
}

// decodeActor logic is borrowed from
// https://github.com/github/launch/blob/1061024891d21b64f81d7ac79985e23121235133/utils/graphqlid/graphqlid.go
func DotcomActorFromGlobalID(globalId string) (DotcomActor, error) {
	if strings.Contains(globalId, "_") {
		return decodeNextGlobalId(globalId)
	}
	return decodeLegacyGlobalId(globalId)
}

func decodeLegacyGlobalId(encoded string) (DotcomActor, error) {
	decoded, err := encoding.DecodeString(encoded)
	if err != nil {
		return "", newDecodeError("(Legacy) Invalid base64-encoding", encoded)
	}
	if len(decoded) == 0 {
		return "", newDecodeError("(Legacy) Empty GlobalID", "")
	}
	typeLenBytes, data := bifurcateBytes(decoded[1:], ':')
	if len(data) == 0 {
		return "", newDecodeError("(Legacy) No ':' found", encoded)
	}
	typeLen, err := strconv.ParseInt(string(typeLenBytes), 10, 64)
	if err != nil {
		return "", newDecodeError(fmt.Sprintf("(Legacy) Error parsing type name length: %q", err), encoded)
	}
	if typeLen >= int64(len(data)) {
		return "", newDecodeError("(Legacy) Type name length is too high", encoded)
	}

	typeName := string(data[:typeLen])
	id := string(data[typeLen:])

	return DotcomActor(fmt.Sprintf("%s:%s", typeName, id)), nil
}

// decodeNextGlobalID extracts the underlying type and ID for the given type and ID.
// / See the dotcom implementation for more details around implementation:
// / https://github.com/github/github/blob/3b21d005e78cf9f495f9f7c36ebdcc460db792aa/lib/platform/helpers/global_id.rb#L5
func decodeNextGlobalId(encoded string) (DotcomActor, error) {
	var msgpackHandle codec.MsgpackHandle
	parts := strings.SplitN(encoded, "_", 2)
	if len(parts) != 2 {
		return "", newDecodeError("Missing type separator '_'", encoded)
	}
	typeHint := parts[0]

	// Get typeName from prefix
	typeName, ok := prefixToTypeName[typeHint]
	if !ok {
		return "", newDecodeError("Invalid type prefix", encoded)
	}

	idPart := parts[1]

	idPartTrimmed := strings.TrimSpace(idPart)

	if len(idPartTrimmed) == 0 {
		return "", newDecodeError("Next generation global ids must have an ownership array encoding", encoded)
	}

	// Base64 URLEncoding decode
	packedMsg, err := encodingURL.DecodeString(idPartTrimmed)
	if err != nil {
		return "", newDecodeError("Invalid base64-UrlEncoding", encoded)
	}

	// MessagePack decode
	// The packed messages for the global id types Launch decodes contain only integers
	var decodedPackedPath []uint64
	dec := codec.NewDecoderBytes(packedMsg, &msgpackHandle)
	err = dec.Decode(&decodedPackedPath)
	if err != nil {
		return "", newDecodeError("Invalid MessagePack encoding", encoded)
	}

	if len(decodedPackedPath) < 2 {
		return "", newDecodeError("Next generation global ids must have at least two integers in the ownership array", encoded)
	}

	idInt := decodedPackedPath[len(decodedPackedPath)-1]
	id := fmt.Sprint(idInt)

	return DotcomActor(fmt.Sprintf("%s:%s", typeName, id)), nil
}

func newDecodeError(message, encoded string) error {
	return fmt.Errorf("error decoding global ID %s: %s", encoded, message)
}

// bifurcateBytes splits a byte slice into two parts, based on a first occurrence of a given separator.
func bifurcateBytes(data []byte, sep byte) ([]byte, []byte) {
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
	// Enterprise' type should be "Business" (class name in Rails)
	// https://github.com/github/launch/blob/ed4cb201f2a41e072af5aa5e92eca0efad1361ab/types/global_id.go#L102
	"E":  "Business",
	"EN": "Environment",
	"M":  "Mannequin",
	"A":  "App",
	"GA": "Gate",
}
