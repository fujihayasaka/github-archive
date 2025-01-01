package model

import (
	"fmt"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestOnStringer(t *testing.T) {
	cases := []struct {
		on       fmt.Stringer
		expected string
	}{
		{
			on:       &OnEvent{Event: "push"},
			expected: "push",
		},
		{
			on:       &OnSchedule{Expression: "* * * * *"},
			expected: "schedule",
		},
		{
			on:       &OnInvalid{},
			expected: "",
		},
		{
			on:       &OnInvalid{Raw: "foo"},
			expected: "foo",
		},
	}

	for _, tc := range cases {
		assert.Equal(t, tc.expected, tc.on.String())
	}
}
