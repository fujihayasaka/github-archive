package geyser

import (
	"errors"
	"fmt"
	"strconv"
	"strings"
)

// IntRange represents an interval between limits. A nil limit is treated as infinity.
type IntRange struct {
	UpperLimit *IntLimitBound
	LowerLimit *IntLimitBound
}

// NewIntRange creates a new integer range with some validations on upper and
// lower limits. Ranges like (5, 5] are impossible as are limits where the
// upper limit is less than the lower limit.
func NewIntRange(lower *IntLimitBound, upper *IntLimitBound) (*IntRange, error) {
	if lower != nil && lower.IsUpperBound {
		return nil, errors.New("lower bound is incorrectly marked as an upper bound")
	}
	if upper != nil && !upper.IsUpperBound {
		return nil, errors.New("upper bound is incorrectly marked as a lower bound")
	}
	if lower != nil && upper != nil {
		if lower.Value > upper.Value {
			return nil, errors.New("lower is greater than upper limit")
		}
		if lower.Value == upper.Value && !(lower.Inclusive && upper.Inclusive) {
			return nil, errors.New("zero-width interval must have both ends inclusive")
		}
	}
	return &IntRange{
		UpperLimit: upper,
		LowerLimit: lower,
	}, nil
}

// NewIntRangeFromString creates a new IntRange using the github syntax X..Y,
// *..X, and X..* for X and Y integers. Ranges are inclusive. Also this will
// fallback to try to parse IntLimitBound strings, such as >=X, >X, <X, and <=X.
//
// Parsing includes validation (ie, lower is less than upper, etc).
func NewIntRangeFromString(text string) (*IntRange, error) {
	if !strings.Contains(text, "..") {
		return tryAsIntLimitBound(text)
	}

	parts := strings.SplitN(text, "..", 2)

	lower, err := parseIntLimitBound(parts[0], false)
	if err != nil {
		return nil, fmt.Errorf("failed to parser lower limit: %w", err)
	}

	upper, err := parseIntLimitBound(parts[1], true)
	if err != nil {
		return nil, fmt.Errorf("failed to parser upper limit: %w", err)
	}

	return NewIntRange(lower, upper)
}

func tryAsIntLimitBound(text string) (*IntRange, error) {
	ilb, err := NewIntLimitBoundFromString(text)
	if err != nil {
		return nil, fmt.Errorf("cannot parse range from %q", text)
	}
	if ilb.IsUpperBound {
		return &IntRange{UpperLimit: ilb}, nil
	}
	return &IntRange{LowerLimit: ilb}, nil
}

func parseIntLimitBound(text string, isUpper bool) (*IntLimitBound, error) {
	if text == "*" {
		return nil, nil
	}
	v, err := strconv.Atoi(text)
	if err != nil {
		return nil, err
	}
	return &IntLimitBound{v, true, isUpper}, nil
}

// String serializes an IntRange as an IntLimitBound if one endpoint is missing.
// Otherwise, it removes inclusiveness and just prints X..Y for both endpoints
// X and Y.
func (ir IntRange) String() string {
	switch {
	case ir.UpperLimit == nil && ir.LowerLimit == nil:
		return "*..*" // this seems like a sane default
	case ir.UpperLimit == nil:
		return ir.LowerLimit.String()
	case ir.LowerLimit == nil:
		return ir.UpperLimit.String()
	default:
		return fmt.Sprintf("%d..%d", ir.LowerLimit.Value, ir.UpperLimit.Value)
	}
}
