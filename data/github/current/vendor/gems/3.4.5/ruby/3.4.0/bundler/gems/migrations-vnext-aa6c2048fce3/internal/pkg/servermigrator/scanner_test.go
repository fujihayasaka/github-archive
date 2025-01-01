package servermigrator

import (
	"fmt"
	"testing"

	"github.com/github/migrations-vnext/internal/pkg/github"
	ogithub "github.com/google/go-github/v65/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestScanner_Gather(t *testing.T) {
	tests := map[string]struct {
		getsListFunc   getterFunc[int]
		getsResultSet  [][]int
		wants          []int
		wantsErr       bool
		wantsErrSubstr string
	}{
		"should return an error when the listFunc returns an error": {
			getsListFunc: func(client *github.Client, options ogithub.ListOptions) ([]int, *ogithub.Response, error) {
				return nil, nil, fmt.Errorf("test")
			},
			wantsErr:       true,
			wantsErrSubstr: "error while scanning for resources",
		},
		"should paginate and return all resources": {
			getsResultSet: [][]int{{1, 2}, {3, 4}, {5, 6}},
			wants:         []int{1, 2, 3, 4, 5, 6},
		},
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			var f getterFunc[int]
			if test.getsListFunc != nil {
				f = test.getsListFunc
			} else {
				f = func(c *github.Client, o ogithub.ListOptions) ([]int, *ogithub.Response, error) {
					resp := &ogithub.Response{}

					// The first request is always 0. It gets translated to
					// "first page" behind the scenes. Forcing it here makes
					// the slicing easier.
					if o.Page == 0 {
						o.Page = 1
					}

					resp.NextPage = o.Page + 1
					if o.Page >= len(test.getsResultSet) {
						resp.NextPage = 0
					}
					resources := test.getsResultSet[o.Page-1]
					return resources, resp, nil
				}
			}

			scanner := &Scanner[int]{}
			var resources []int
			for r := range scanner.All(f) {
				resources = append(resources, r)
			}

			require.Equal(t, test.wantsErr, scanner.Err() != nil)
			if test.wantsErr {
				assert.Contains(t, scanner.Err().Error(), test.wantsErrSubstr)
			} else {
				assert.Equal(t, test.wants, resources)
			}
		})
	}
}
