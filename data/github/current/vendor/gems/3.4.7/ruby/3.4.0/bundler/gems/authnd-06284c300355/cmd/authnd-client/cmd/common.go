package cmd

import (
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/fatih/color"
	"github.com/pkg/errors"

	pb "github.com/github/authnd/client/proto/authentication/v0"
)

var warning = color.New(color.FgCyan, color.Bold)

func isDNSError(err error) bool {
	return strings.Contains(err.Error(), "no such host")
}

func printDNSWarning() {
	warning.Fprintln(os.Stderr, "\nA DNS error has likely occurred:")
	warning.Fprintln(os.Stderr, "- Ensure you are connected to the appropriate VPN.")
	warning.Fprintln(os.Stderr, "- If you are targetting canary, ensure there is a canary deployment live.")
}

var knownAttributeTypes = map[string]string{
	"actor.id":                  "int",
	"actor.type":                "string",
	"access.id":                 "int",
	"credential.expires_at_utc": "time",
}

var attributeParsers = map[string]func(id, value string) (*pb.Attribute, error){
	"int": func(id, s string) (*pb.Attribute, error) {
		i, err := strconv.ParseInt(s, 10, 64)
		if err != nil {
			return nil, errors.Wrapf(err, "invalid attribute (int) value '%s'", s)
		}

		return &pb.Attribute{
			Id:    id,
			Value: pb.NewInt64Value(i),
		}, nil
	},
	"string": func(id, s string) (*pb.Attribute, error) {
		return &pb.Attribute{
			Id:    id,
			Value: pb.NewStringValue(s),
		}, nil
	},
	"bool": func(id, s string) (*pb.Attribute, error) {
		b, err := strconv.ParseBool(s)
		if err != nil {
			return nil, errors.Wrapf(err, "invalid attribute (bool) value '%s'", s)
		}
		return &pb.Attribute{
			Id:    id,
			Value: pb.NewBoolValue(b),
		}, nil
	},
	"float": func(id, s string) (*pb.Attribute, error) {
		f, err := strconv.ParseFloat(s, 64)
		if err != nil {
			return nil, errors.Wrapf(err, "invalid attribute (float) value '%s'", s)
		}
		return &pb.Attribute{
			Id:    id,
			Value: pb.NewDoubleValue(f),
		}, nil
	},
	"time": func(id, s string) (*pb.Attribute, error) {
		exp, err := time.Parse(time.RFC3339, s)
		if err != nil {
			return nil, errors.Wrapf(err, "invalid attribute (time) value '%s'", s)
		}
		return &pb.Attribute{
			Id:    id,
			Value: pb.NewTimeValue(exp),
		}, nil
	},
}

func parseAttribute(attr string) (*pb.Attribute, error) {
	// Attribute format
	//  <id>[:<type>]=<value>
	// The "<type>" can be omitted for certain attributes with a well-known type, e.g.
	//		actor.id=1   		  (known/promoted attribute)
	//		foo.bar:string=baz    (unknown attribute)

	splat := strings.Split(attr, "=")
	if len(splat) != 2 {
		return nil, errors.New(invalidAttributeErrorMessage)
	}

	value := splat[1]
	if len(value) == 0 {
		return nil, errors.New(invalidAttributeErrorMessage)
	}

	splat = strings.Split(splat[0], ":")
	id := splat[0]
	if len(id) == 0 {
		return nil, errors.New(invalidAttributeErrorMessage)
	}

	typ := ""
	if len(splat) > 1 {
		typ = splat[1]
	} else if _, ok := knownAttributeTypes[id]; ok {
		typ = knownAttributeTypes[id]
	} else {
		return nil, errors.Errorf("unknown attribute type for '%s'", id)
	}
	if len(typ) == 0 {
		return nil, errors.New(invalidAttributeErrorMessage)
	}
	typ = strings.ToLower(typ)

	parser, ok := attributeParsers[typ]
	if !ok {
		return nil, errors.Errorf("unknown attribute type '%s'", typ)
	}

	parsed, err := parser(id, value)
	if err != nil {
		return nil, errors.Wrapf(err, "error parsing '%s'", value)
	}

	return parsed, nil
}

func getKnownTokenType(tokenType string) (string, error) {
	switch tokenType {
	case "programmatic_access_token", "prat":
		return pb.ProgrammaticAccessTokenType, nil
	default:
		return "", errors.Errorf("invalid token type: %s. expected 'programmatic_access_token'.", tokenType)
	}
}
