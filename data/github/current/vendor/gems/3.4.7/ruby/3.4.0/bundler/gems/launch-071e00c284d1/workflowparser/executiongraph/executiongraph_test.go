package executiongraph

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"os/exec"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/pkg/browser"

	"github.com/github/launch/observability"
	"github.com/github/launch/types"
	launchutils "github.com/github/launch/utils"
	"github.com/github/launch/workflowparser"
)

func TestBuildExecutionGraph(t *testing.T) {
	ctx := context.Background()
	type args struct {
		workflow             string
		featureFlags         types.WorkflowFeatureFlags
		wfSource             workflowparser.WorkflowSource
		parseCalledWorkflows bool
	}
	var (
		name1  = "a / b"
		name2  = "a / c"
		name3  = "a / a"
		name4  = "B / c"
		name5  = "B / d"
		name6  = "b / c"
		name7  = "b / d"
		name8  = "callerJob1 / calledJob1"
		name9  = "callerJob1 / calledJob2"
		name10 = "callerJob2 / calledJob1"
		name11 = "callerJob2 / calledJob2"
		name12 = "Job C"
	)
	tests := []struct {
		name string
		args args
		want ExecutionGraph
		json string
		err  string

		printDot bool // helper to debug the graph output. set to `true` to get a browser open with an SVG of the graph
	}{
		{
			name: "Group single job",
			args: args{
				workflow: `on: push
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: echo 1`,
			},
			want: ExecutionGraph{
				[]Stage{{
					Groups: []Group{{
						ID:   "|",
						Type: GroupTypeDefault,
						Jobs: []*Job{{
							ID: "a",
						}},
					}},
				}},
			},
			json: "{\"stages\":[{\"groups\":[{\"id\":\"|\",\"type\":0,\"jobs\":[{\"id\":\"a\"}]}]}]}",
		},
		{
			name: "Group multiple jobs with the same environment",
			args: args{
				workflow: `on: push
jobs:
  a:
    environment:
      name: environment 1
    runs-on: ubuntu-latest
    steps:
      - run: echo 1
  b:
    environment:
      name: environment 1
    runs-on: ubuntu-latest
    steps:
      - run: echo 1`,
			},
			want: ExecutionGraph{
				[]Stage{{
					Groups: []Group{{
						ID:   "|env:environment 1|",
						Type: GroupTypeDefault,
						Jobs: []*Job{
							{
								ID:            "a",
								environmentID: "env:environment 1",
							},
							{
								ID:            "b",
								environmentID: "env:environment 1",
							},
						},
					}},
				}},
			},
			json: "{\"stages\":[{\"groups\":[{\"id\":\"|env:environment 1|\",\"type\":0,\"jobs\":[{\"id\":\"a\"},{\"id\":\"b\"}]}]}]}",
		},
		{
			name: "Group multiple jobs together with the different dynamic environment",
			args: args{
				workflow: `on: push
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: echo 1
  b:
    environment:
      name: my ${{ secrets.ENVIRONMENT_NAME }} environment
    runs-on: ubuntu-latest
    steps:
      - run: echo 2
  c:
    environment:
      name: my different ${{ secrets.ENVIRONMENT_NAME }} environment
    runs-on: ubuntu-latest
    steps:
      - run: echo 3`,
			},
			want: ExecutionGraph{
				[]Stage{{
					Groups: []Group{{
						ID:   "|",
						Type: GroupTypeDefault,
						Jobs: []*Job{
							{
								ID: "a",
							},
							{
								ID: "b",
							},
							{
								ID: "c",
							},
						},
					}},
				}},
			},
			json: "{\"stages\":[{\"groups\":[{\"id\":\"|\",\"type\":0,\"jobs\":[{\"id\":\"a\"},{\"id\":\"b\"},{\"id\":\"c\"}]}]}]}",
		},
		{
			name: "Group jobs separately with the static and dynamic environment",
			args: args{
				workflow: `on: push
jobs:
  a:
    environment:
      name: my environment
    runs-on: ubuntu-latest
    steps:
      - run: echo 1
  b:
    environment:
      name: my dynamic ${{ secrets.ENVIRONMENT_NAME }} environment
    runs-on: ubuntu-latest
    steps:
      - run: echo 1`,
			},
			want: ExecutionGraph{
				[]Stage{
					{
						Groups: []Group{
							{
								ID:   "|",
								Type: GroupTypeDefault,
								Jobs: []*Job{{
									ID: "b",
								}},
							},
							{
								ID:   "|env:my environment|",
								Type: GroupTypeDefault,
								Jobs: []*Job{{
									ID:            "a",
									environmentID: "env:my environment",
								}},
							},
						},
					},
				},
			},
			json: "{\"stages\":[{\"groups\":[{\"id\":\"|\",\"type\":0,\"jobs\":[{\"id\":\"b\"}]},{\"id\":\"|env:my environment|\",\"type\":0,\"jobs\":[{\"id\":\"a\"}]}]}]}",
		},
		{
			name: "Environments group separately despite same needs",
			args: args{
				workflow: `on: push
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: echo 1
  g1:
    runs-on: ubuntu-latest
    needs: a
    environment:
      name: env1
    steps:
      - run: echo 2
  g2:
    runs-on: ubuntu-latest
    needs: a
    environment:
      name: env2
    steps:
      - run: echo 3`,
			},
			want: ExecutionGraph{
				[]Stage{{
					Groups: []Group{{
						ID:   "|g1&g2",
						Type: GroupTypeDefault,
						Jobs: []*Job{{
							ID:      "a",
							outputs: []string{"g1", "g2"},
						}},
						Outputs: []string{"a|env:env1|", "a|env:env2|"},
					}},
				}, {
					Groups: []Group{{
						ID:   "a|env:env1|",
						Type: GroupTypeDefault,
						Jobs: []*Job{{
							ID:            "g1",
							environmentID: "env:env1",
							inputs:        []string{"a"},
						}},
						Inputs: []string{"|g1&g2"},
					}, {
						ID:   "a|env:env2|",
						Type: GroupTypeDefault,
						Jobs: []*Job{{
							ID:            "g2",
							environmentID: "env:env2",
							inputs:        []string{"a"},
						}},
						Inputs: []string{"|g1&g2"},
					}},
				}},
			},
			json: "{\"stages\":[{\"groups\":[{\"id\":\"|g1&g2\",\"type\":0,\"jobs\":[{\"id\":\"a\"}],\"outputs\":[\"a|env:env1|\",\"a|env:env2|\"]}]},{\"groups\":[{\"id\":\"a|env:env1|\",\"type\":0,\"jobs\":[{\"id\":\"g1\"}],\"inputs\":[\"|g1&g2\"]},{\"id\":\"a|env:env2|\",\"type\":0,\"jobs\":[{\"id\":\"g2\"}],\"inputs\":[\"|g1&g2\"]}]}]}",
		},
		{
			name: "Sequential jobs",
			args: args{
				workflow: `on: push
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: echo 1
  b:
    runs-on: ubuntu-latest
    needs: a
    steps:
      - run: echo 2
  c:
    runs-on: ubuntu-latest
    needs: b
    steps:
      - run: echo 3`,
			},
			want: ExecutionGraph{
				[]Stage{
					{
						Groups: []Group{
							{
								ID:   "|b",
								Type: GroupTypeDefault,
								Jobs: []*Job{{
									ID:      "a",
									outputs: []string{"b"},
								}},
								Outputs: []string{"a|c"},
							},
						},
					},
					{
						Groups: []Group{
							{
								ID:   "a|c",
								Type: GroupTypeDefault,
								Jobs: []*Job{{
									ID:      "b",
									inputs:  []string{"a"},
									outputs: []string{"c"},
								}},
								Inputs:  []string{"|b"},
								Outputs: []string{"b|"},
							},
						},
					},
					{
						Groups: []Group{
							{
								ID:   "b|",
								Type: GroupTypeDefault,
								Jobs: []*Job{{
									ID:     "c",
									inputs: []string{"b"},
								}},
								Inputs: []string{"a|c"},
							},
						},
					},
				},
			},
			json: "{\"stages\":[{\"groups\":[{\"id\":\"|b\",\"type\":0,\"jobs\":[{\"id\":\"a\"}],\"outputs\":[\"a|c\"]}]},{\"groups\":[{\"id\":\"a|c\",\"type\":0,\"jobs\":[{\"id\":\"b\"}],\"inputs\":[\"|b\"],\"outputs\":[\"b|\"]}]},{\"groups\":[{\"id\":\"b|\",\"type\":0,\"jobs\":[{\"id\":\"c\"}],\"inputs\":[\"a|c\"]}]}]}",
		},
		{
			name: "Fan out and in",
			args: args{
				workflow: `on: push
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: echo 1
  b:
    runs-on: ubuntu-latest
    needs: a
    steps:
      - run: echo 2
  c:
    runs-on: ubuntu-latest
    needs: a
    steps:
      - run: echo 3
  d:
    runs-on: ubuntu-latest
    needs: [b, c]
    steps:
      - run: echo 4`,
			},
			want: ExecutionGraph{
				[]Stage{
					{
						Groups: []Group{
							{
								ID:   "|b&c",
								Type: GroupTypeDefault,
								Jobs: []*Job{{
									ID:      "a",
									outputs: []string{"b", "c"},
								}},
								Outputs: []string{"a|d"},
							},
						},
					},
					{
						Groups: []Group{
							{
								ID:   "a|d",
								Type: GroupTypeDefault,
								Jobs: []*Job{{
									ID:      "b",
									inputs:  []string{"a"},
									outputs: []string{"d"},
								}, {
									ID:      "c",
									inputs:  []string{"a"},
									outputs: []string{"d"},
								}},
								Inputs:  []string{"|b&c"},
								Outputs: []string{"b&c|"},
							},
						},
					},
					{
						Groups: []Group{
							{
								ID:   "b&c|",
								Type: GroupTypeDefault,
								Jobs: []*Job{{
									ID:     "d",
									inputs: []string{"b", "c"},
								}},
								Inputs: []string{"a|d"},
							},
						},
					},
				},
			},
			json: "{\"stages\":[{\"groups\":[{\"id\":\"|b&c\",\"type\":0,\"jobs\":[{\"id\":\"a\"}],\"outputs\":[\"a|d\"]}]},{\"groups\":[{\"id\":\"a|d\",\"type\":0,\"jobs\":[{\"id\":\"b\"},{\"id\":\"c\"}],\"inputs\":[\"|b&c\"],\"outputs\":[\"b&c|\"]}]},{\"groups\":[{\"id\":\"b&c|\",\"type\":0,\"jobs\":[{\"id\":\"d\"}],\"inputs\":[\"a|d\"]}]}]}",
		},
		{
			name: "Dangling job",
			args: args{
				workflow: `on: push
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: echo 1
  b:
    runs-on: ubuntu-latest
    needs: a
    steps:
      - run: echo 2
  c:
    runs-on: ubuntu-latest
    steps:
      - run: echo 3`,
			},
			want: ExecutionGraph{
				[]Stage{
					{
						Groups: []Group{
							{
								ID:   "|b",
								Type: GroupTypeDefault,
								Jobs: []*Job{{
									ID:      "a",
									outputs: []string{"b"},
								}},
								Outputs: []string{"a|"},
							},
							{
								ID:   "|",
								Type: GroupTypeDefault,
								Jobs: []*Job{{
									ID: "c",
								}},
							},
						},
					},
					{
						Groups: []Group{
							{
								ID:   "a|",
								Type: GroupTypeDefault,
								Jobs: []*Job{{
									ID:     "b",
									inputs: []string{"a"},
								}},
								Inputs: []string{"|b"},
							},
						},
					},
				},
			},
			json: "{\"stages\":[{\"groups\":[{\"id\":\"|b\",\"type\":0,\"jobs\":[{\"id\":\"a\"}],\"outputs\":[\"a|\"]},{\"id\":\"|\",\"type\":0,\"jobs\":[{\"id\":\"c\"}]}]},{\"groups\":[{\"id\":\"a|\",\"type\":0,\"jobs\":[{\"id\":\"b\"}],\"inputs\":[\"|b\"]}]}]}",
		},
		{
			name: "More complexity, out of order in workflow, multi-stage",
			args: args{
				workflow: `on: push
jobs:
  c:
    runs-on: ubuntu-latest
    needs: a
    steps:
      - run: echo 1
  d:
    runs-on: ubuntu-latest
    needs: a
    steps:
      - run: echo 2
  a:
    runs-on: ubuntu-latest
    steps:
      - run: echo 3
  f:
    runs-on: ubuntu-latest
    needs: b
    steps:
      - run: echo 4
  b:
    runs-on: ubuntu-latest
    needs: a
    steps:
      - run: echo 5
  e:
    runs-on: ubuntu-latest
    needs: [c, d]
    steps:
      - run: echo 6`,
			},
			want: ExecutionGraph{
				[]Stage{
					{
						Groups: []Group{
							{
								ID:   "|b&c&d",
								Type: GroupTypeDefault,
								Jobs: []*Job{{
									ID:      "a",
									outputs: []string{"b", "c", "d"},
								}},
								Outputs: []string{"a|e", "a|f"},
							},
						},
					},
					{
						Groups: []Group{
							{
								ID:   "a|e",
								Type: GroupTypeDefault,
								Jobs: []*Job{{
									ID:      "c",
									inputs:  []string{"a"},
									outputs: []string{"e"},
								}, {
									ID:      "d",
									inputs:  []string{"a"},
									outputs: []string{"e"},
								}},
								Inputs:  []string{"|b&c&d"},
								Outputs: []string{"c&d|"},
							},
							{
								ID:   "a|f",
								Type: GroupTypeDefault,
								Jobs: []*Job{{
									ID:      "b",
									inputs:  []string{"a"},
									outputs: []string{"f"},
								}},
								Inputs:  []string{"|b&c&d"},
								Outputs: []string{"b|"},
							},
						},
					},
					{
						Groups: []Group{
							{
								ID:   "c&d|",
								Type: GroupTypeDefault,
								Jobs: []*Job{{
									ID:     "e",
									inputs: []string{"c", "d"},
								}},
								Inputs: []string{"a|e"},
							},
							{
								ID:   "b|",
								Type: GroupTypeDefault,
								Jobs: []*Job{{
									ID:     "f",
									inputs: []string{"b"},
								}},
								Inputs: []string{"a|f"},
							},
						},
					},
				},
			},
			json: "{\"stages\":[{\"groups\":[{\"id\":\"|b&c&d\",\"type\":0,\"jobs\":[{\"id\":\"a\"}],\"outputs\":[\"a|e\",\"a|f\"]}]},{\"groups\":[{\"id\":\"a|e\",\"type\":0,\"jobs\":[{\"id\":\"c\"},{\"id\":\"d\"}],\"inputs\":[\"|b&c&d\"],\"outputs\":[\"c&d|\"]},{\"id\":\"a|f\",\"type\":0,\"jobs\":[{\"id\":\"b\"}],\"inputs\":[\"|b&c&d\"],\"outputs\":[\"b|\"]}]},{\"groups\":[{\"id\":\"c&d|\",\"type\":0,\"jobs\":[{\"id\":\"e\"}],\"inputs\":[\"a|e\"]},{\"id\":\"b|\",\"type\":0,\"jobs\":[{\"id\":\"f\"}],\"inputs\":[\"a|f\"]}]}]}",
		},
		{
			name: "Matrixes group separately despite same needs",
			args: args{
				workflow: `on: push
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: echo 1
  m1:
    name: My Matrix
    runs-on: ubuntu-latest
    needs: a
    strategy:
      matrix:
        node: [6, 8, 10]
    steps:
      - uses: actions/setup-node@v1
        with:
          node-version: ${{ matrix.node }}
  b:
    runs-on: ubuntu-latest
    needs: a
    steps:
      - run: echo 1`,
			},
			want: ExecutionGraph{
				[]Stage{{
					Groups: []Group{{
						ID:   "|b&m1",
						Type: GroupTypeDefault,
						Jobs: []*Job{{
							ID:      "a",
							outputs: []string{"b", "m1"},
						}},
						Outputs: []string{"a|", "a|-m1-|"},
					}},
				}, {
					Groups: []Group{{
						ID:   "a|",
						Type: GroupTypeDefault,
						Jobs: []*Job{{
							ID:     "b",
							inputs: []string{"a"},
						}},
						Inputs: []string{"|b&m1"},
					}, {
						ID:   "a|-m1-|",
						Name: "My Matrix",
						Type: GroupTypeMatrix,
						Jobs: []*Job{{
							ID:       "m1",
							Name:     makeString("My Matrix"),
							isMatrix: true,
							inputs:   []string{"a"},
						}},
						Inputs: []string{"|b&m1"},
					}},
				}},
			},
			json: "{\"stages\":[{\"groups\":[{\"id\":\"|b&m1\",\"type\":0,\"jobs\":[{\"id\":\"a\"}],\"outputs\":[\"a|\",\"a|-m1-|\"]}]},{\"groups\":[{\"id\":\"a|\",\"type\":0,\"jobs\":[{\"id\":\"b\"}],\"inputs\":[\"|b&m1\"]},{\"id\":\"a|-m1-|\",\"name\":\"My Matrix\",\"type\":1,\"jobs\":[{\"id\":\"m1\",\"name\":\"My Matrix\"}],\"inputs\":[\"|b&m1\"]}]}]}",
		},
		{
			name: "Strategy with expression syntax groups separately like a matrix",
			args: args{
				workflow: `on: push
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: echo 1
  s1:
    runs-on: ubuntu-latest
    needs: a
    strategy: ${{fromJson(needs.job1.outputs.strategy)}}
    steps:
      - uses: actions/setup-node@v1
        with:
          node-version: ${{ matrix.node }}
  b:
    runs-on: ubuntu-latest
    needs: a
    steps:
      - run: echo 1`,
			},
			want: ExecutionGraph{
				[]Stage{{
					Groups: []Group{{
						ID:   "|b&s1",
						Type: GroupTypeDefault,
						Jobs: []*Job{{
							ID:      "a",
							outputs: []string{"b", "s1"},
						}},
						Outputs: []string{"a|", "a|-s1-|"},
					}},
				}, {
					Groups: []Group{{
						ID:   "a|",
						Type: GroupTypeDefault,
						Jobs: []*Job{{
							ID:     "b",
							inputs: []string{"a"},
						}},
						Inputs: []string{"|b&s1"},
					}, {
						ID:   "a|-s1-|",
						Type: GroupTypeStrategyExpression,
						Jobs: []*Job{{
							ID:                   "s1",
							isStrategyExpression: true,
							inputs:               []string{"a"},
						}},
						Inputs: []string{"|b&s1"},
					}},
				}},
			},
			json: "{\"stages\":[{\"groups\":[{\"id\":\"|b&s1\",\"type\":0,\"jobs\":[{\"id\":\"a\"}],\"outputs\":[\"a|\",\"a|-s1-|\"]}]},{\"groups\":[{\"id\":\"a|\",\"type\":0,\"jobs\":[{\"id\":\"b\"}],\"inputs\":[\"|b&s1\"]},{\"id\":\"a|-s1-|\",\"type\":2,\"jobs\":[{\"id\":\"s1\"}],\"inputs\":[\"|b&s1\"]}]}]}",
		},
		{
			name: "Group jobs with environments with strategy or matrix",
			args: args{
				workflow: `on: push
jobs:
  m1:
    runs-on: ubuntu-latest
    environment:
      name: env1
    strategy:
      matrix:
        node: [6, 8, 10]
    steps:
      - uses: actions/setup-node@v1
        with:
          node-version: ${{ matrix.node }}
  s1:
    runs-on: ubuntu-latest
    environment:
      name: env2
    strategy: ${{fromJson(needs.job1.outputs.strategy)}}
    steps:
      - uses: actions/setup-node@v1
        with:
          node-version: ${{ matrix.node }}`,
			},
			want: ExecutionGraph{
				[]Stage{{
					Groups: []Group{{
						ID:   "|env:env1|-m1-|",
						Name: "m1",
						Type: GroupTypeMatrix,
						Jobs: []*Job{{
							ID:            "m1",
							isMatrix:      true,
							environmentID: "env:env1",
						}},
					}, {
						ID:   "|env:env2|-s1-|",
						Type: GroupTypeStrategyExpression,
						Jobs: []*Job{{
							ID:                   "s1",
							isStrategyExpression: true,
							environmentID:        "env:env2",
						}},
					}},
				}},
			},
			json: "{\"stages\":[{\"groups\":[{\"id\":\"|env:env1|-m1-|\",\"name\":\"m1\",\"type\":1,\"jobs\":[{\"id\":\"m1\"}]},{\"id\":\"|env:env2|-s1-|\",\"type\":2,\"jobs\":[{\"id\":\"s1\"}]}]}]}",
		},
		{
			name: "Handle a cycle",
			args: args{
				workflow: `on: push
jobs:
  a:
    runs-on: ubuntu-latest
    needs: c
    steps:
      - run: echo 1
  b:
    runs-on: ubuntu-latest
    needs: a
    steps:
      - run: echo 2
  c:
    runs-on: ubuntu-latest
    needs: b
    steps:
      - run: echo 3`,
			},
			err: "Some jobs are unreachable",
		},
		{
			name: "Handle a self-referential job",
			args: args{
				workflow: `on: push
jobs:
  a:
    runs-on: ubuntu-latest
    needs: a
    steps:
      - run: echo 1`,
			},
			err: "self-referential job.needs",
		},
		{
			name: "Handle a non-existent needs",
			args: args{
				workflow: `on: push
jobs:
  a:
    runs-on: ubuntu-latest
    needs: b
    steps:
      - run: echo 1`,
			},
			err: "job.needs points to non-existent job key",
		},
		{
			name: "Handle explicit job name",
			args: args{
				workflow: `on: push
jobs:
  a:
    runs-on: ubuntu-latest
    name: Custom Name
    steps:
    - run: echo 1`,
			},
			want: ExecutionGraph{
				[]Stage{{
					Groups: []Group{{
						ID:   "|",
						Type: GroupTypeDefault,
						Jobs: []*Job{{
							ID:   "a",
							Name: makeString("Custom Name"),
						}},
					},
					}},
				},
			},
			json: "{\"stages\":[{\"groups\":[{\"id\":\"|\",\"type\":0,\"jobs\":[{\"id\":\"a\",\"name\":\"Custom Name\"}]}]}]}",
		},
		{
			name: "Handle dynamic job name",
			args: args{
				workflow: `on: push
jobs:
  a:
    runs-on: ubuntu-latest
    name: Custom ${{ matrix.test }} Name
    steps:
    - run: echo 1`,
			},
			want: ExecutionGraph{
				[]Stage{{
					Groups: []Group{{
						ID:   "|",
						Type: GroupTypeDefault,
						Jobs: []*Job{{
							ID: "a",
						}},
					},
					}},
				},
			},
			json: "{\"stages\":[{\"groups\":[{\"id\":\"|\",\"type\":0,\"jobs\":[{\"id\":\"a\"}]}]}]}",
		},
		{
			name: "Handles jobs with case insensitive needs",
			args: args{
				workflow: `on: push
jobs:
  A:
    runs-on: ubuntu-latest
    steps:
      - run: echo 1
  b:
    runs-on: ubuntu-latest
    steps:
      - run: echo 1
  c:
    runs-on: ubuntu-latest
    needs: [a, B]
    steps:
      - run: echo 1`,
			},
			want: ExecutionGraph{
				[]Stage{
					{
						Groups: []Group{{
							ID:   "|c",
							Type: GroupTypeDefault,
							Jobs: []*Job{
								{
									ID:      "A",
									outputs: []string{"c"},
								},
								{
									ID:      "b",
									outputs: []string{"c"},
								},
							},
							Outputs: []string{"a&b|"},
						}},
					},
					{
						Groups: []Group{{
							ID:   "a&b|",
							Type: GroupTypeDefault,
							Jobs: []*Job{
								{
									ID:     "c",
									inputs: []string{"a", "B"},
								},
							},
							Inputs: []string{"|c"},
						}},
					},
				},
			},
			json: "{\"stages\":[{\"groups\":[{\"id\":\"|c\",\"type\":0,\"jobs\":[{\"id\":\"A\"},{\"id\":\"b\"}],\"outputs\":[\"a&b|\"]}]},{\"groups\":[{\"id\":\"a&b|\",\"type\":0,\"jobs\":[{\"id\":\"c\"}],\"inputs\":[\"|c\"]}]}]}",
		},
		{
			name: "uses another workflow",
			args: args{
				workflow: `on: push
jobs:
  a:
    uses: some/repo/.github/workflows/another.yml@main`,
				featureFlags:         types.WorkflowFeatureFlags{},
				parseCalledWorkflows: true,
				wfSource: &workflowparser.StubWorkflowSource{
					SourceMap: map[string]workflowparser.WorkflowDetails{
						"some/repo/.github/workflows/another.yml@main": {
							Content: `
name: Called Workflow
on:
  workflow_call:
jobs:
  b:
    runs-on: ubuntu-latest
    steps:
      - run: echo hello world`,
							RefType: "refs/heads/",
						},
					}},
			},
			want: ExecutionGraph{
				[]Stage{
					{
						Groups: []Group{{
							ID:   "|",
							Type: GroupTypeDefault,
							Jobs: []*Job{
								{
									ID:   "a.b",
									Name: &name1, // "a / b"
								},
							},
						}},
					},
				},
			},
			json: "{\"stages\":[{\"groups\":[{\"id\":\"|\",\"type\":0,\"jobs\":[{\"id\":\"a.b\",\"name\":\"a / b\"}]}]}]}",
		},
		{
			name: "uses another workflow with needs",
			args: args{
				workflow: `
on: push
jobs:
  a:
    uses: some/repo/.github/workflows/another.yml@main`,
				featureFlags:         types.WorkflowFeatureFlags{},
				parseCalledWorkflows: true,
				wfSource: &workflowparser.StubWorkflowSource{
					SourceMap: map[string]workflowparser.WorkflowDetails{
						"some/repo/.github/workflows/another.yml@main": {
							Content: `
on:
  workflow_call:
jobs:
  b:
    runs-on: ubuntu-latest
    steps:
      - run: echo 1
  c:
    runs-on: ubuntu-latest
    needs: b
    steps:
      - run: echo 2`,
							RefType: "refs/heads/",
						},
					}},
			},
			want: ExecutionGraph{
				[]Stage{
					{
						Groups: []Group{{
							ID:   "|a.c",
							Type: GroupTypeDefault,
							Jobs: []*Job{
								{
									ID:      "a.b",
									Name:    &name1, // "a / b"
									outputs: []string{"a.c"},
								},
							},
							Outputs: []string{"a.b|"},
						}},
					},
					{
						Groups: []Group{{
							ID:   "a.b|",
							Type: GroupTypeDefault,
							Jobs: []*Job{
								{
									ID:     "a.c",
									Name:   &name2, // "a / c"
									inputs: []string{"a.b"},
								},
							},
							Inputs: []string{"|a.c"},
						}},
					},
				},
			},
			json: "{\"stages\":[{\"groups\":[{\"id\":\"|a.c\",\"type\":0,\"jobs\":[{\"id\":\"a.b\",\"name\":\"a / b\"}],\"outputs\":[\"a.b|\"]}]},{\"groups\":[{\"id\":\"a.b|\",\"type\":0,\"jobs\":[{\"id\":\"a.c\",\"name\":\"a / c\"}],\"inputs\":[\"|a.c\"]}]}]}",
		},
		{
			name: "uses multiple workflows",
			args: args{
				workflow: `
on: push
jobs:
  a:
    uses: some/repo/.github/workflows/another.yml@main
  b:
    name: B
    needs: a
    uses: some/repo/.github/workflows/another2.yml@main`,
				featureFlags:         types.WorkflowFeatureFlags{},
				parseCalledWorkflows: true,
				wfSource: &workflowparser.StubWorkflowSource{
					SourceMap: map[string]workflowparser.WorkflowDetails{
						"some/repo/.github/workflows/another.yml@main": {
							Content: `
on:
  workflow_call:
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: echo 1
  b:
    runs-on: ubuntu-latest
    needs: a
    steps:
      - run: echo 2`,
							RefType: "refs/heads/",
						},
						"some/repo/.github/workflows/another2.yml@main": {
							Content: `
on:
  workflow_call:
jobs:
  c:
    runs-on: ubuntu-latest
    steps:
    - run: echo 1
  d:
    runs-on: ubuntu-latest
    needs: c
    steps:
    - run: echo 2`,
							RefType: "refs/heads/",
						},
					}},
			},
			want: ExecutionGraph{
				[]Stage{
					{
						Groups: []Group{{
							ID:   "|a.b",
							Type: GroupTypeDefault,
							Jobs: []*Job{
								{
									ID:      "a.a",
									Name:    &name3, // "a / a"
									outputs: []string{"a.b"},
								},
							},
							Outputs: []string{"a.a|b.c"},
						}},
					},
					{
						Groups: []Group{{
							ID:   "a.a|b.c",
							Type: GroupTypeDefault,
							Jobs: []*Job{
								{
									ID:      "a.b",
									Name:    &name1, // "a / b"
									inputs:  []string{"a.a"},
									outputs: []string{"b.c"},
								},
							},
							Inputs:  []string{"|a.b"},
							Outputs: []string{"a.b|b.d"},
						}},
					},
					{
						Groups: []Group{{
							ID:   "a.b|b.d",
							Type: GroupTypeDefault,
							Jobs: []*Job{
								{
									ID:      "b.c",
									Name:    &name4, // "B / c"
									inputs:  []string{"a.b"},
									outputs: []string{"b.d"},
								},
							},
							Inputs:  []string{"a.a|b.c"},
							Outputs: []string{"b.c|"},
						}},
					},
					{
						Groups: []Group{{
							ID:   "b.c|",
							Type: GroupTypeDefault,
							Jobs: []*Job{
								{
									ID:     "b.d",
									Name:   &name5, // "B / d"
									inputs: []string{"b.c"},
								},
							},
							Inputs: []string{"a.b|b.d"},
						}},
					},
				},
			},
			json: "{\"stages\":[{\"groups\":[{\"id\":\"|a.b\",\"type\":0,\"jobs\":[{\"id\":\"a.a\",\"name\":\"a / a\"}],\"outputs\":[\"a.a|b.c\"]}]},{\"groups\":[{\"id\":\"a.a|b.c\",\"type\":0,\"jobs\":[{\"id\":\"a.b\",\"name\":\"a / b\"}],\"inputs\":[\"|a.b\"],\"outputs\":[\"a.b|b.d\"]}]},{\"groups\":[{\"id\":\"a.b|b.d\",\"type\":0,\"jobs\":[{\"id\":\"b.c\",\"name\":\"B / c\"}],\"inputs\":[\"a.a|b.c\"],\"outputs\":[\"b.c|\"]}]},{\"groups\":[{\"id\":\"b.c|\",\"type\":0,\"jobs\":[{\"id\":\"b.d\",\"name\":\"B / d\"}],\"inputs\":[\"a.b|b.d\"]}]}]}",
		},
		{
			name: "has needs and uses another workflow with needs",
			args: args{
				workflow: `on: push
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: echo 1
  b:
    needs: a
    uses: some/repo/.github/workflows/another.yml@main`,
				featureFlags:         types.WorkflowFeatureFlags{},
				parseCalledWorkflows: true,
				wfSource: &workflowparser.StubWorkflowSource{
					SourceMap: map[string]workflowparser.WorkflowDetails{
						"some/repo/.github/workflows/another.yml@main": {
							Content: `
on:
  workflow_call:
jobs:
  c:
    runs-on: ubuntu-latest
    steps:
      - run: echo 1
  d:
    runs-on: ubuntu-latest
    needs: c
    steps:
      - run: echo 2`,
							RefType: "refs/heads/",
						},
					}},
			},
			want: ExecutionGraph{
				[]Stage{
					{
						Groups: []Group{{
							ID:   "|b.c",
							Type: GroupTypeDefault,
							Jobs: []*Job{
								{
									ID:      "a",
									outputs: []string{"b.c"},
								},
							},
							Outputs: []string{"a|b.d"},
						}},
					}, {
						Groups: []Group{{
							ID:   "a|b.d",
							Type: GroupTypeDefault,
							Jobs: []*Job{
								{
									ID:      "b.c",
									Name:    &name6, // "b / c"
									inputs:  []string{"a"},
									outputs: []string{"b.d"},
								},
							},
							Inputs:  []string{"|b.c"},
							Outputs: []string{"b.c|"},
						}},
					}, {
						Groups: []Group{{
							ID:   "b.c|",
							Type: GroupTypeDefault,
							Jobs: []*Job{
								{
									ID:     "b.d",
									Name:   &name7, // "b / d"
									inputs: []string{"b.c"},
								},
							},
							Inputs: []string{"a|b.d"},
						}},
					},
				},
			},
			json: "{\"stages\":[{\"groups\":[{\"id\":\"|b.c\",\"type\":0,\"jobs\":[{\"id\":\"a\"}],\"outputs\":[\"a|b.d\"]}]},{\"groups\":[{\"id\":\"a|b.d\",\"type\":0,\"jobs\":[{\"id\":\"b.c\",\"name\":\"b / c\"}],\"inputs\":[\"|b.c\"],\"outputs\":[\"b.c|\"]}]},{\"groups\":[{\"id\":\"b.c|\",\"type\":0,\"jobs\":[{\"id\":\"b.d\",\"name\":\"b / d\"}],\"inputs\":[\"a|b.d\"]}]}]}",
		},
		{
			name: "uses another workflow with case sensitive jobIDs",
			args: args{
				workflow: `on: push
jobs:
  callerJob1:
    uses: some/repo/.github/workflows/another.yml@main
  callerJob2:
    needs: CallerJob1
    uses: some/repo/.github/workflows/another.yml@main`,
				featureFlags:         types.WorkflowFeatureFlags{},
				parseCalledWorkflows: true,
				wfSource: &workflowparser.StubWorkflowSource{
					SourceMap: map[string]workflowparser.WorkflowDetails{
						"some/repo/.github/workflows/another.yml@main": {
							Content: `
name: Called Workflow
on:
  workflow_call:
jobs:
  calledJob1:
    runs-on: ubuntu-latest
    steps:
      - run: echo hello world
  calledJob2:
    needs: CalledJob1
    runs-on: ubuntu-latest
    steps:
      - run: echo hello world`,
							RefType: "refs/heads/",
						},
					}},
			},
			want: ExecutionGraph{
				[]Stage{
					{
						Groups: []Group{{
							ID:   "|callerjob1.calledjob2",
							Type: GroupTypeDefault,
							Jobs: []*Job{
								{
									ID:      "callerJob1.calledJob1",
									Name:    &name8, // "callerJob1 / calledJob1"
									outputs: []string{"callerjob1.calledjob2"},
								},
							},
							Outputs: []string{"callerjob1.calledjob1|callerjob2.calledjob1"},
						}},
					},
					{
						Groups: []Group{{
							ID:   "callerjob1.calledjob1|callerjob2.calledjob1",
							Type: GroupTypeDefault,
							Jobs: []*Job{
								{
									ID:      "callerJob1.calledJob2",
									Name:    &name9, // "callerJob1 / calledJob2"
									inputs:  []string{"callerJob1.CalledJob1"},
									outputs: []string{"callerJob2.calledJob1"},
								},
							},
							Inputs:  []string{"|callerjob1.calledjob2"},
							Outputs: []string{"callerjob1.calledjob2|callerjob2.calledjob2"},
						}},
					},
					{
						Groups: []Group{{
							ID:   "callerjob1.calledjob2|callerjob2.calledjob2",
							Type: GroupTypeDefault,
							Jobs: []*Job{
								{
									ID:      "callerJob2.calledJob1",
									Name:    &name10, // "callerJob2 / calledJob1"
									inputs:  []string{"callerJob1.calledJob2"},
									outputs: []string{"callerjob2.calledjob2"},
								},
							},
							Inputs:  []string{"callerjob1.calledjob1|callerjob2.calledjob1"},
							Outputs: []string{"callerjob2.calledjob1|"},
						}},
					},
					{
						Groups: []Group{{
							ID:   "callerjob2.calledjob1|",
							Type: GroupTypeDefault,
							Jobs: []*Job{
								{
									ID:     "callerJob2.calledJob2",
									Name:   &name11, // "callerJob2 / calledJob2"
									inputs: []string{"callerJob2.CalledJob1"},
								},
							},
							Inputs: []string{"callerjob1.calledjob2|callerjob2.calledjob2"},
						}},
					},
				},
			},
			json: "{\"stages\":[{\"groups\":[{\"id\":\"|callerjob1.calledjob2\",\"type\":0,\"jobs\":[{\"id\":\"callerJob1.calledJob1\",\"name\":\"callerJob1 / calledJob1\"}],\"outputs\":[\"callerjob1.calledjob1|callerjob2.calledjob1\"]}]},{\"groups\":[{\"id\":\"callerjob1.calledjob1|callerjob2.calledjob1\",\"type\":0,\"jobs\":[{\"id\":\"callerJob1.calledJob2\",\"name\":\"callerJob1 / calledJob2\"}],\"inputs\":[\"|callerjob1.calledjob2\"],\"outputs\":[\"callerjob1.calledjob2|callerjob2.calledjob2\"]}]},{\"groups\":[{\"id\":\"callerjob1.calledjob2|callerjob2.calledjob2\",\"type\":0,\"jobs\":[{\"id\":\"callerJob2.calledJob1\",\"name\":\"callerJob2 / calledJob1\"}],\"inputs\":[\"callerjob1.calledjob1|callerjob2.calledjob1\"],\"outputs\":[\"callerjob2.calledjob1|\"]}]},{\"groups\":[{\"id\":\"callerjob2.calledjob1|\",\"type\":0,\"jobs\":[{\"id\":\"callerJob2.calledJob2\",\"name\":\"callerJob2 / calledJob2\"}],\"inputs\":[\"callerjob1.calledjob2|callerjob2.calledjob2\"]}]}]}",
		},
		{
			name: "uses local workflow",
			args: args{
				workflow: `on: push
jobs:
  callerJob1:
    uses: ./.github/workflows/another.yml
  callerJob2:
    needs: CallerJob1
    uses: ./.github/workflows/another.yml`,
				featureFlags:         types.WorkflowFeatureFlags{},
				parseCalledWorkflows: true,
				wfSource: &workflowparser.StubWorkflowSource{
					SourceMap: map[string]workflowparser.WorkflowDetails{
						"github/caller/.github/workflows/another.yml@f905316836ccc4a64d02f752f51ae47c4cb7c049": {
							Content: `
name: Called Workflow
on:
  workflow_call:
jobs:
  calledJob1:
    runs-on: ubuntu-latest
    steps:
      - run: echo hello world
  calledJob2:
    needs: CalledJob1
    runs-on: ubuntu-latest
    steps:
      - run: echo hello world`,
						},
					},
					CallerRepoID: "R_kgAw", // [0, 48]
					CallerRepoNWO: types.RepositoryFullName{
						Owner: "github",
						Name:  "caller",
					},
					CallerRepoSHA: "f905316836ccc4a64d02f752f51ae47c4cb7c049",
				},
			},
			want: ExecutionGraph{
				[]Stage{
					{
						Groups: []Group{{
							ID:   "|callerjob1.calledjob2",
							Type: GroupTypeDefault,
							Jobs: []*Job{
								{
									ID:      "callerJob1.calledJob1",
									Name:    &name8, // "callerJob1 / calledJob1"
									outputs: []string{"callerjob1.calledjob2"},
								},
							},
							Outputs: []string{"callerjob1.calledjob1|callerjob2.calledjob1"},
						}},
					},
					{
						Groups: []Group{{
							ID:   "callerjob1.calledjob1|callerjob2.calledjob1",
							Type: GroupTypeDefault,
							Jobs: []*Job{
								{
									ID:      "callerJob1.calledJob2",
									Name:    &name9, // "callerJob1 / calledJob2"
									inputs:  []string{"callerJob1.CalledJob1"},
									outputs: []string{"callerJob2.calledJob1"},
								},
							},
							Inputs:  []string{"|callerjob1.calledjob2"},
							Outputs: []string{"callerjob1.calledjob2|callerjob2.calledjob2"},
						}},
					},
					{
						Groups: []Group{{
							ID:   "callerjob1.calledjob2|callerjob2.calledjob2",
							Type: GroupTypeDefault,
							Jobs: []*Job{
								{
									ID:      "callerJob2.calledJob1",
									Name:    &name10, // "callerJob2 / calledJob1"
									inputs:  []string{"callerJob1.calledJob2"},
									outputs: []string{"callerjob2.calledjob2"},
								},
							},
							Inputs:  []string{"callerjob1.calledjob1|callerjob2.calledjob1"},
							Outputs: []string{"callerjob2.calledjob1|"},
						}},
					},
					{
						Groups: []Group{{
							ID:   "callerjob2.calledjob1|",
							Type: GroupTypeDefault,
							Jobs: []*Job{
								{
									ID:     "callerJob2.calledJob2",
									Name:   &name11, // "callerJob2 / calledJob2"
									inputs: []string{"callerJob2.CalledJob1"},
								},
							},
							Inputs: []string{"callerjob1.calledjob2|callerjob2.calledjob2"},
						}},
					},
				},
			},
			json: "{\"stages\":[{\"groups\":[{\"id\":\"|callerjob1.calledjob2\",\"type\":0,\"jobs\":[{\"id\":\"callerJob1.calledJob1\",\"name\":\"callerJob1 / calledJob1\"}],\"outputs\":[\"callerjob1.calledjob1|callerjob2.calledjob1\"]}]},{\"groups\":[{\"id\":\"callerjob1.calledjob1|callerjob2.calledjob1\",\"type\":0,\"jobs\":[{\"id\":\"callerJob1.calledJob2\",\"name\":\"callerJob1 / calledJob2\"}],\"inputs\":[\"|callerjob1.calledjob2\"],\"outputs\":[\"callerjob1.calledjob2|callerjob2.calledjob2\"]}]},{\"groups\":[{\"id\":\"callerjob1.calledjob2|callerjob2.calledjob2\",\"type\":0,\"jobs\":[{\"id\":\"callerJob2.calledJob1\",\"name\":\"callerJob2 / calledJob1\"}],\"inputs\":[\"callerjob1.calledjob1|callerjob2.calledjob1\"],\"outputs\":[\"callerjob2.calledjob1|\"]}]},{\"groups\":[{\"id\":\"callerjob2.calledjob1|\",\"type\":0,\"jobs\":[{\"id\":\"callerJob2.calledJob2\",\"name\":\"callerJob2 / calledJob2\"}],\"inputs\":[\"callerjob1.calledjob2|callerjob2.calledjob2\"]}]}]}",
		},
		{
			name: "uses another workflow with matrix",
			args: args{
				workflow: `on: push
jobs:
  a:
    runs-on: ubuntu-latest
    uses: some/repo/.github/workflows/another.yml@main
    strategy:
      matrix:
        val: [1, 2]
    with:
      input1: ${{ matrix.val }}`,
				featureFlags:         types.WorkflowFeatureFlags{},
				parseCalledWorkflows: true,
				wfSource: &workflowparser.StubWorkflowSource{
					SourceMap: map[string]workflowparser.WorkflowDetails{
						"some/repo/.github/workflows/another.yml@main": {
							Content: `
name: Called Workflow
on:
  workflow_call:
    inputs:
      input1:
        type: string
jobs:
  b:
    runs-on: ubuntu-latest
    steps:
      - run: echo ${{ inputs.input1 }}`,
							RefType: "refs/heads/",
						},
					}},
			},
			want: ExecutionGraph{
				[]Stage{{
					Groups: []Group{{
						ID:   "|-a-|",
						Name: "a",
						Type: GroupTypeWorkflowMatrix,
						Jobs: []*Job{{
							ID:               "a",
							isMatrix:         true,
							isWorkflowMatrix: true,
						}},
					}},
				}},
			},
			json: "{\"stages\":[{\"groups\":[{\"id\":\"|-a-|\",\"name\":\"a\",\"type\":3,\"jobs\":[{\"id\":\"a\"}]}]}]}",
		},
		{
			name: "uses multiple workflows with matrices",
			args: args{
				workflow: `on: push
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: echo hello world
  b:
    runs-on: ubuntu-latest
    needs: a
    uses: some/repo/.github/workflows/another.yml@main
    strategy:
      matrix:
        val: [1, 2]
    with:
      input1: ${{ matrix.val }}
  c:
    name: Job C
    runs-on: ubuntu-latest
    needs: a
    uses: some/repo/.github/workflows/another.yml@main
    strategy:
      matrix:
        val: [1, 2]
    with:
      input1: ${{ matrix.val }}
  d:
    needs: [b, c]
    runs-on: ubuntu-latest
    uses: some/repo/.github/workflows/another.yml@main
    strategy:
      matrix:
        val: [1, 2]
    with:
      input1: ${{ matrix.val }}`,
				featureFlags:         types.WorkflowFeatureFlags{},
				parseCalledWorkflows: true,
				wfSource: &workflowparser.StubWorkflowSource{
					SourceMap: map[string]workflowparser.WorkflowDetails{
						"some/repo/.github/workflows/another.yml@main": {
							Content: `
name: Called Workflow
on:
  workflow_call:
    inputs:
      input1:
        type: string
jobs:
  job:
    runs-on: ubuntu-latest
    steps:
      - run: echo ${{ inputs.input1 }}`,
							RefType: "refs/heads/",
						},
					}},
			},
			want: ExecutionGraph{
				[]Stage{{
					Groups: []Group{{
						ID:   "|b&c",
						Type: GroupTypeDefault,
						Jobs: []*Job{{
							ID:      "a",
							outputs: []string{"b", "c"},
						}},
						Outputs: []string{"a|-b-|d", "a|-c-|d"},
					}},
				}, {
					Groups: []Group{{
						ID:   "a|-b-|d",
						Name: "b",
						Type: GroupTypeWorkflowMatrix,
						Jobs: []*Job{{
							ID:               "b",
							isMatrix:         true,
							isWorkflowMatrix: true,
							inputs:           []string{"a"},
							outputs:          []string{"d"},
						}},
						Inputs:  []string{"|b&c"},
						Outputs: []string{"b&c|-d-|"},
					}, {
						ID:   "a|-c-|d",
						Name: "Job C",
						Type: GroupTypeWorkflowMatrix,
						Jobs: []*Job{{
							ID:               "c",
							Name:             &name12, // "Job C"
							isMatrix:         true,
							isWorkflowMatrix: true,
							inputs:           []string{"a"},
							outputs:          []string{"d"},
						}},
						Inputs:  []string{"|b&c"},
						Outputs: []string{"b&c|-d-|"},
					}},
				}, {
					Groups: []Group{{
						ID:   "b&c|-d-|",
						Name: "d",
						Type: GroupTypeWorkflowMatrix,
						Jobs: []*Job{{
							ID:               "d",
							isMatrix:         true,
							isWorkflowMatrix: true,
							inputs:           []string{"b", "c"},
						}},
						Inputs: []string{"a|-b-|d", "a|-c-|d"},
					}},
				}},
			},
			json: "{\"stages\":[{\"groups\":[{\"id\":\"|b&c\",\"type\":0,\"jobs\":[{\"id\":\"a\"}],\"outputs\":[\"a|-b-|d\",\"a|-c-|d\"]}]},{\"groups\":[{\"id\":\"a|-b-|d\",\"name\":\"b\",\"type\":3,\"jobs\":[{\"id\":\"b\"}],\"inputs\":[\"|b&c\"],\"outputs\":[\"b&c|-d-|\"]},{\"id\":\"a|-c-|d\",\"name\":\"Job C\",\"type\":3,\"jobs\":[{\"id\":\"c\",\"name\":\"Job C\"}],\"inputs\":[\"|b&c\"],\"outputs\":[\"b&c|-d-|\"]}]},{\"groups\":[{\"id\":\"b&c|-d-|\",\"name\":\"d\",\"type\":3,\"jobs\":[{\"id\":\"d\"}],\"inputs\":[\"a|-b-|d\",\"a|-c-|d\"]}]}]}",
		},
		{
			name: "uses a workflow with strategy expression",
			args: args{
				workflow: `on: push
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: echo 1
  b:
    runs-on: ubuntu-latest
    needs: a
    uses: some/repo/.github/workflows/another.yml@main
    strategy: ${{fromJson(needs.job1.outputs.strategy)}}
    with:
      input1: ${{ matrix.val }}`,
				featureFlags:         types.WorkflowFeatureFlags{},
				parseCalledWorkflows: true,
				wfSource: &workflowparser.StubWorkflowSource{
					SourceMap: map[string]workflowparser.WorkflowDetails{
						"some/repo/.github/workflows/another.yml@main": {
							Content: `
name: Called Workflow
on:
  workflow_call:
    inputs:
      input1:
        type: string
jobs:
  c:
    runs-on: ubuntu-latest
    steps:
      - run: echo ${{ inputs.input1 }}`,
							RefType: "refs/heads/",
						},
					}},
			},
			want: ExecutionGraph{
				[]Stage{{
					Groups: []Group{{
						ID:   "|b",
						Type: GroupTypeDefault,
						Jobs: []*Job{{
							ID:      "a",
							outputs: []string{"b"},
						}},
						Outputs: []string{"a|-b-|"},
					}},
				}, {
					Groups: []Group{{
						ID:   "a|-b-|",
						Type: GroupTypeWorkflowMatrix,
						Jobs: []*Job{{
							ID:                   "b",
							isStrategyExpression: true,
							isWorkflowMatrix:     true,
							inputs:               []string{"a"},
						}},
						Inputs: []string{"|b"},
					}},
				}},
			},
			json: "{\"stages\":[{\"groups\":[{\"id\":\"|b\",\"type\":0,\"jobs\":[{\"id\":\"a\"}],\"outputs\":[\"a|-b-|\"]}]},{\"groups\":[{\"id\":\"a|-b-|\",\"type\":3,\"jobs\":[{\"id\":\"b\"}],\"inputs\":[\"|b\"]}]}]}",
		},
		{
			name: "uses two workflows, first one has two jobs in a group",
			args: args{
				workflow: `on: push
jobs:
  callerJob1:
    uses: some/repo/.github/workflows/called1.yml@main
  callerJob2:
    needs: callerJob1
    uses: some/repo/.github/workflows/called2.yml@main`,
				parseCalledWorkflows: true,
				wfSource: &workflowparser.StubWorkflowSource{
					SourceMap: map[string]workflowparser.WorkflowDetails{
						"some/repo/.github/workflows/called1.yml@main": {
							Content: `
name: calledWorkflow1
on:
  workflow_call:
jobs:
  calledJob1:
    runs-on: ubuntu-latest
    steps:
      - run: echo hello world
  calledJob2:
    runs-on: ubuntu-latest
    steps:
      - run: echo hello world`,
							RefType: "refs/heads/",
						},
						"some/repo/.github/workflows/called2.yml@main": {
							Content: `
name: calledWorkflow2
on:
  workflow_call:
jobs:
  calledJob1:
    runs-on: ubuntu-latest
    steps:
      - run: echo hello world`,
							RefType: "refs/heads/",
						},
					},
				},
			},
			want: ExecutionGraph{
				Stages: []Stage{
					{
						Groups: []Group{{
							ID:   "|callerjob2.calledjob1",
							Name: "",
							Type: 0,
							Jobs: []*Job{
								{
									ID:      "callerJob1.calledJob1",
									Name:    &name8, // "callerJob1 / calledJob1"
									outputs: []string{"callerJob2.calledJob1"},
								},
								{
									ID:      "callerJob1.calledJob2",
									Name:    &name9, // "callerJob1 / calledJob2"
									outputs: []string{"callerJob2.calledJob1"},
								},
							},
							Outputs: []string{"callerjob1.calledjob1&callerjob1.calledjob2|"},
						}},
					},
					{
						Groups: []Group{{
							ID:   "callerjob1.calledjob1&callerjob1.calledjob2|",
							Name: "",
							Type: 0,
							Jobs: []*Job{
								{
									ID:     "callerJob2.calledJob1",
									Name:   &name10, // "callerJob2 / calledJob1"
									inputs: []string{"callerJob1.calledJob1", "callerJob1.calledJob2"},
								},
							},
							Inputs: []string{"|callerjob2.calledjob1"},
						}},
					},
				},
			},
			json: "{\"stages\":[{\"groups\":[{\"id\":\"|callerjob2.calledjob1\",\"type\":0,\"jobs\":[{\"id\":\"callerJob1.calledJob1\",\"name\":\"callerJob1 / calledJob1\"},{\"id\":\"callerJob1.calledJob2\",\"name\":\"callerJob1 / calledJob2\"}],\"outputs\":[\"callerjob1.calledjob1&callerjob1.calledjob2|\"]}]},{\"groups\":[{\"id\":\"callerjob1.calledjob1&callerjob1.calledjob2|\",\"type\":0,\"jobs\":[{\"id\":\"callerJob2.calledJob1\",\"name\":\"callerJob2 / calledJob1\"}],\"inputs\":[\"|callerjob2.calledjob1\"]}]}]}",
		},
		{
			name: "uses two workflows, second one has two jobs in a group",
			args: args{
				workflow: `on: push
jobs:
  callerJob1:
    uses: some/repo/.github/workflows/called1.yml@main
  callerJob2:
    needs: callerJob1
    uses: some/repo/.github/workflows/called2.yml@main`,
				parseCalledWorkflows: true,
				wfSource: &workflowparser.StubWorkflowSource{
					SourceMap: map[string]workflowparser.WorkflowDetails{
						"some/repo/.github/workflows/called1.yml@main": {
							Content: `
name: calledWorkflow1
on:
  workflow_call:
jobs:
  calledJob1:
    runs-on: ubuntu-latest
    steps:
      - run: echo hello world`,
							RefType: "refs/heads/",
						},
						"some/repo/.github/workflows/called2.yml@main": {
							Content: `
name: calledWorkflow2
on:
  workflow_call:
jobs:
  calledJob1:
    runs-on: ubuntu-latest
    steps:
      - run: echo hello world
  calledJob2:
    runs-on: ubuntu-latest
    steps:
      - run: echo hello world`,
							RefType: "refs/heads/",
						},
					},
				},
			},
			want: ExecutionGraph{
				Stages: []Stage{
					{
						Groups: []Group{{
							ID:   "|callerjob2.calledjob1&callerjob2.calledjob2",
							Name: "",
							Type: 0,
							Jobs: []*Job{
								{
									ID:      "callerJob1.calledJob1",
									Name:    &name8, // "callerJob1 / calledJob1"
									outputs: []string{"callerJob2.calledJob1", "callerJob2.calledJob2"},
								},
							},
							Outputs: []string{"callerjob1.calledjob1|"},
						}},
					},
					{
						Groups: []Group{{
							ID:   "callerjob1.calledjob1|",
							Name: "",
							Type: 0,
							Jobs: []*Job{
								{
									ID:     "callerJob2.calledJob1",
									Name:   &name10, // "callerJob2 / calledJob1"
									inputs: []string{"callerJob1.calledJob1"},
								},
								{
									ID:     "callerJob2.calledJob2",
									Name:   &name11, // "callerJob2 / calledJob2"
									inputs: []string{"callerJob1.calledJob1"},
								},
							},
							Inputs: []string{"|callerjob2.calledjob1&callerjob2.calledjob2"},
						}},
					},
				},
			},
			json: "{\"stages\":[{\"groups\":[{\"id\":\"|callerjob2.calledjob1&callerjob2.calledjob2\",\"type\":0,\"jobs\":[{\"id\":\"callerJob1.calledJob1\",\"name\":\"callerJob1 / calledJob1\"}],\"outputs\":[\"callerjob1.calledjob1|\"]}]},{\"groups\":[{\"id\":\"callerjob1.calledjob1|\",\"type\":0,\"jobs\":[{\"id\":\"callerJob2.calledJob1\",\"name\":\"callerJob2 / calledJob1\"},{\"id\":\"callerJob2.calledJob2\",\"name\":\"callerJob2 / calledJob2\"}],\"inputs\":[\"|callerjob2.calledjob1&callerjob2.calledjob2\"]}]}]}",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var w *workflowparser.Workflow
			if tt.args.parseCalledWorkflows {
				w, _ = workflowparser.ParseWithCalledWorkflows(ctx, types.ResolvedFile{Text: tt.args.workflow, Path: "some/repo/.github/workflows/w.yml"}, tt.args.featureFlags, tt.args.wfSource, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewTestObservability())
			} else {
				w, _ = workflowparser.Parse(ctx, types.ResolvedFile{Text: tt.args.workflow, Path: "some/repo/.github/workflows/w.yml"}, tt.args.featureFlags, tt.args.wfSource, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewTestObservability())
			}
			got, err := BuildExecutionGraph(w)

			if tt.err != "" {
				assert.EqualError(t, err, tt.err)
			} else {
				if tt.printDot {
					dotGraph := makeDotGraph(got, tt.name)
					openDot(dotGraph)
				}

				require.NoError(t, err)
				assert.Equal(t, tt.want, got)

				json, err := got.ToJSON()
				assert.Nil(t, err, "failed to serialize json: %v", err)
				assert.Equal(t, tt.json, json)
			}
		})
	}
}

// Simpler test to just focus on group ordering, not yaml, etc
func TestOrderedStages(t *testing.T) {
	type groupShorthand struct {
		name string
		in   string
		out  string
	}
	tests := []struct {
		name string
		in   []groupShorthand
		want string
	}{
		{
			name: "Within a stage order by num outgoing connections",
			in: []groupShorthand{
				{"a", "", "bc"},
				{"b", "a", ""},
				{"c", "a", ""},
				{"d", "", ""},
			},
			want: "[ad][bc]", // `a` has 2 outgoing connections, `d` none
		},
		{
			name: "Num outgoing trumps alphabetization",
			in: []groupShorthand{
				{"a", "", "b"},
				{"b", "a", ""},
				{"c", "", "de"},
				{"d", "c", ""},
				{"e", "c", ""},
			},
			want: "[ca][deb]", // `c` has 2 outgoing ("de"), `a` only `b`
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			groups := map[string]*Group{}

			// Build groups from []groupShorthand
			for _, g := range tt.in {
				group := Group{ID: g.name}
				for _, c := range g.in {
					group.addInput(string(c))
				}
				for _, c := range g.out {
					group.addOutput(string(c))
				}
				groups[g.name] = &group
			}

			got, err := orderedStages(groups)
			require.NoError(t, err)

			// Build string output to test against
			var sb strings.Builder
			for _, s := range got {
				sb.WriteString("[")
				for _, g := range s.Groups {
					sb.WriteString(g.ID)
				}
				sb.WriteString("]")
			}
			assert.Equal(t, tt.want, sb.String())
		})
	}
}

func makeString(input string) *string {
	return &input
}

func makeDotGraph(exgraph ExecutionGraph, name string) *bytes.Buffer {
	dotGraph := bytes.NewBuffer(nil)
	fmt.Fprintf(dotGraph, "digraph %q {\n", name)
	fmt.Fprintf(dotGraph, "\tcompound=true\n")
	fmt.Fprintf(dotGraph, "\trankdir=LR\n")
	fmt.Fprintf(dotGraph, "\tnewrank=true\n")
	groupMap := map[string]Group{}
	for _, stage := range exgraph.Stages {
		for _, group := range stage.Groups {
			groupMap[group.ID] = group
		}
	}
	for _, stage := range exgraph.Stages {
		for _, group := range stage.Groups {
			fmt.Fprintf(dotGraph, "\tsubgraph \"cluster_%s\" {\n", group.ID)
			for _, job := range group.Jobs {
				fmt.Fprintf(dotGraph, "\t\t\"%s\"\n", job.ID)
			}
			fmt.Fprintf(dotGraph, "\t\trank=same\n\t}\n")
			for _, output := range group.Outputs {
				fmt.Fprintf(dotGraph, "\t\"%s\" -> \"%s\" [lhead=\"cluster_%s\", ltail=\"cluster_%s\"]\n", group.Jobs[0].ID, groupMap[output].Jobs[0].ID, output, group.ID)
			}
		}
	}
	fmt.Fprint(dotGraph, "}\n")
	return dotGraph
}

func openDot(r io.Reader) {
	cmd := exec.Command("dot", "-Tsvg")
	cmd.Stdin = r
	data, err := cmd.CombinedOutput()
	if err != nil {
		panic(string(data))
	}
	svg := bytes.NewBuffer(data)
	if err := browser.OpenReader(svg); err != nil {
		panic(err)
	}
}
