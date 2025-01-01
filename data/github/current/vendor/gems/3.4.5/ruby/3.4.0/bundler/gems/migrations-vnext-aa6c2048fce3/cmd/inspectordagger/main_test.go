package main

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"
)

func Test_traverseGraph(t *testing.T) {
	d := dag{
		Eligible: []string{"A"},
		Dependencies: map[string]int{
			"default:A:dependencies": 0,
			"default:B:dependencies": 1,
			"default:C:dependencies": 1,
			"default:D:dependencies": 1,
			"default:E:dependencies": 2,
			"default:F:dependencies": 2,
			"default:G:dependencies": 2,
			"default:H:dependencies": 2,
		},
		Dependants: map[string][]string{
			"default:A:dependants": {"B", "C", "D", "E"},
			"default:B:dependants": {"E"},
			"default:C:dependants": {"F", "G", "H"},
			"default:D:dependants": {"F", "G", "H"},
		},
	}

	r, err := traverseGraph(context.Background(), &d, "default", 3)
	require.NoError(t, err)

	expected := nodeDeps{
		"A": {"B": struct{}{}, "C": struct{}{}, "D": struct{}{}, "E": struct{}{}},
		"B": {"E": struct{}{}},
		"C": {"F": struct{}{}, "G": struct{}{}, "H": struct{}{}},
		"D": {"F": struct{}{}, "G": struct{}{}, "H": struct{}{}},
	}

	require.Equal(t, expected, r)
}
