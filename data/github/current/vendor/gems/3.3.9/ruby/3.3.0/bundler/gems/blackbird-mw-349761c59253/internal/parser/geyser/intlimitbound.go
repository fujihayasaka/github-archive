package geyser

import (
	"errors"
	"strconv"
	"strings"
)

// IntLimitBound is a data type encoding an integer limit boundary. This allows
// us to say things like "less than or equal to some value", or "greater than or
// equal to some value". More details about serialization are described on
// NewIntLimitBoundFromString.
type IntLimitBound struct {
	Value        int
	Inclusive    bool
	IsUpperBound bool
}

// NewIntLimitBound is a convenience function for creating IntLimitBounds
func NewIntLimitBound(v int, inc bool, upper bool) *IntLimitBound {
	return &IntLimitBound{v, inc, upper}
}

// NewIntLimitBoundFromString creates a IntLimitBound by parsing the string. This is useful from
// the query parser as we can just extract the tokens and then process them here.
//
// Valid prefixes are <=, <, >=, > and integers following without a space.
//
// Examples: >=0, <42, etc. Invalid examples are > 0 (with space), 42 (missing operator).
func NewIntLimitBoundFromString(v string) (*IntLimitBound, error) {
	var inclusive, upperBound bool
	switch {
	case strings.HasPrefix(v, "<="):
		inclusive = true
		upperBound = true
		v = v[2:]
	case strings.HasPrefix(v, "<"):
		inclusive = false
		upperBound = true
		v = v[1:]
	case strings.HasPrefix(v, ">="):
		inclusive = true
		upperBound = false
		v = v[2:]
	case strings.HasPrefix(v, ">"):
		inclusive = false
		upperBound = false
		v = v[1:]
	default:
		return nil, errors.New("input does not contain prefix (>, >=, <, or <=)")
	}

	value, err := strconv.Atoi(v)
	if err != nil {
		return nil, err
	}

	return NewIntLimitBound(value, inclusive, upperBound), nil
}

// only used for tests
func mustIntLimitBound(v string) *IntLimitBound {
	ilb, err := NewIntLimitBoundFromString(v)
	if err != nil {
		panic(err)
	}
	return ilb
}

func (ilb IntLimitBound) String() string {
	boundPrefix := ">"
	if ilb.IsUpperBound {
		boundPrefix = "<"
	}

	var prefix string
	if ilb.Inclusive {
		prefix = "="
	}

	return boundPrefix + prefix + strconv.Itoa(ilb.Value)
}
