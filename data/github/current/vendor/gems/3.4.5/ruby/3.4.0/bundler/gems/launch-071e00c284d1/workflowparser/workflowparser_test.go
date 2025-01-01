package workflowparser

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"
	"unicode/utf8"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
	"gopkg.in/yaml.v3"

	"github.com/github/launch/model"
	"github.com/github/launch/observability"
	"github.com/github/launch/types"
	launcherror "github.com/github/launch/types/errors"
	launchutils "github.com/github/launch/utils"
)

func TestParse(t *testing.T) {
	snapshotVersion := "1.2.*"
	tests := []struct {
		desc         string
		workflow     string
		parsed       *parseTarget
		path         string
		truncated    bool
		featureFlags types.WorkflowFeatureFlags
		wfSrc        WorkflowSource
		error        error
	}{
		{
			desc:     "invalid YAML",
			workflow: "{",
			error:    ParseError{line: 1},
		},
		{
			desc:     "tab ",
			workflow: "\n\nthing\t",
			error:    ParseError{line: 3},
		},
		{
			desc:     "incorrect type ",
			workflow: "<not yaml>",
			error:    ParseError{line: 1},
		},
		{
			desc:     "unescaped star",
			workflow: "on: *",
			error:    ParseError{},
		},
		{
			desc: "a simple workflow with name",
			workflow: `
on: push
name: "simple"
jobs:
  thing:
    steps:
    - uses: owner/repo@master`,
			parsed: &parseTarget{
				Name: "simple",
				On:   workflowOnValue{EventConfig{Event: "push"}},
				Jobs: map[string]job{
					"thing": {
						Steps: []parsedStep{
							{
								Uses: &model.UsesRepository{
									Repository: "owner/repo",
									Path:       "",
									Ref:        "master",
								},
							},
						},
					},
				},
			},
			path: "workflow.yml",
		}, {
			desc: "a simple workflow with no name",
			workflow: `
on: push
jobs:
  thing:
    steps:
    - uses: owner/repo@master`,
			parsed: &parseTarget{
				Name: "workflow.yml",
				On:   workflowOnValue{EventConfig{Event: "push"}},
				Jobs: map[string]job{
					"thing": {
						Steps: []parsedStep{
							{
								Uses: &model.UsesRepository{
									Repository: "owner/repo",
									Path:       "",
									Ref:        "master",
								},
							},
						},
					},
				},
			},
			path: "workflow.yml",
		}, {
			desc: "a list of event strings",
			workflow: `
on: [push, issue_comment]
jobs:
  thing:
    steps:
    - uses: owner/repo@master`,
			parsed: &parseTarget{
				Name: "",
				On:   workflowOnValue{EventConfig{Event: "push"}, EventConfig{Event: "issue_comment"}},
				Jobs: map[string]job{
					"thing": {
						Steps: []parsedStep{
							{
								Uses: &model.UsesRepository{
									Repository: "owner/repo",
									Path:       "",
									Ref:        "master",
								},
							},
						},
					},
				},
			},
		}, {
			desc:     "invalid type in `on` list",
			workflow: "on: [{}]",
			error:    errors.New("Invalid type for `on`"),
		}, {
			desc:     "invalid type in `on` map",
			workflow: "on: {push: {branches: {}}}",
			error:    errors.New("Invalid type for `on`"),
		}, {
			desc:     "missing `on`",
			workflow: "",
			error:    errors.New("No event triggers defined in `on`"),
		}, {
			desc:     "missing `jobs`",
			workflow: "on: push",
			error:    errors.New("No jobs defined in `jobs`"),
		}, {
			desc: "jobs defined but no keys",
			workflow: `
on: push
jobs:
`,
			error: errors.New("No jobs defined in `jobs`"),
		}, {
			desc: "jobs defined but missing steps",
			workflow: `
on:
  push:
    branches: master
    tags: [v1.0.0]
jobs:
  thing1:
  thing2:
`,
			error: newParseError("No steps defined in `steps` and no workflow called in `uses` for the following jobs: thing1, thing2"),
		}, {
			desc: "jobs defined but steps misspelled",
			workflow: `
on:
  push:
    branches: master
    tags: [v1.0.0]
jobs:
  thing1:
    stepss:
    - uses: owner/repo@master
`,
			error: newParseError("No steps defined in `steps` and no workflow called in `uses` for the following jobs: thing1"),
		}, {
			desc: "jobs defined but wrong type for steps",
			workflow: `
on:
  push:
    branches: master
    tags: [v1.0.0]
jobs:
  thing1:
    steps:
      steps:
      - uses: owner/repo@master
`,
			error: newParseError("Invalid `steps` value - steps should be list of `uses` or `run` items"),
		}, {
			desc: "a map of events",
			workflow: `
on:
  push:
    branches: master
    tags: [v1.0.0]
jobs:
  thing:
    steps:
    - uses: owner/repo@master
`,
			parsed: &parseTarget{
				Name: "",
				On: workflowOnValue{
					EventConfig{Event: "push", Branches: &stringList{"master"}, Tags: &stringList{"v1.0.0"}},
				},
				Jobs: map[string]job{
					"thing": {
						Steps: []parsedStep{
							{
								Uses: &model.UsesRepository{
									Repository: "owner/repo",
									Path:       "",
									Ref:        "master",
								},
							},
						},
					},
				},
			},
			error: nil,
		}, {
			desc: "a map of events with cron schedules",
			workflow: `
on:
  push:
    branches: master
  schedule:
  - cron: "* * * 1 *"
    branches: master
  - cron: "* * * 2 *"
    branches: [master]
jobs:
  thing:
    steps:
    - uses: owner/repo@master
`,
			parsed: &parseTarget{Name: "", On: workflowOnValue{
				EventConfig{Event: "push", Branches: &stringList{"master"}},
				EventConfig{Event: "schedule", Cron: "* * * 1 *", Branches: &stringList{"master"}},
				EventConfig{Event: "schedule", Cron: "* * * 2 *", Branches: &stringList{"master"}},
			},
				Jobs: map[string]job{
					"thing": {
						Steps: []parsedStep{
							{
								Uses: &model.UsesRepository{
									Repository: "owner/repo",
									Path:       "",
									Ref:        "master",
								},
							},
						},
					},
				},
			},
			error: nil,
		},
		{
			desc: "more than 10 workflow_dispatch inputs",
			workflow: `
on:
  workflow_dispatch:
    inputs:
      1:
      2:
      3:
      4:
      5:
      6:
      7:
      8:
      9:
      10:
      11:
jobs:
  build:
    steps:
    - uses: owner/repo@master`,
			error: newParseError("you may only define up to 10 `inputs` for a `workflow_dispatch` event"),
		},
		{
			// see https://github.com/github/c2c-actions-policy/issues/205
			desc: "no limit on workflow_call inputs amount",
			workflow: `
on:
  workflow_call:
    inputs:
      1:
      2:
      3:
      4:
      5:
      6:
      7:
      8:
      9:
      10:
      11:
jobs:
  build:
    steps:
    - uses: owner/repo@master`,
			parsed: &parseTarget{
				On: workflowOnValue{
					EventConfig{
						Event: "workflow_call",
						Inputs: &inputsMap{
							"1": {
								Required: false,
							},
							"2": {
								Required: false,
							},
							"3": {
								Required: false,
							},
							"4": {
								Required: false,
							},
							"5": {
								Required: false,
							},
							"6": {
								Required: false,
							},
							"7": {
								Required: false,
							},
							"8": {
								Required: false,
							},
							"9": {
								Required: false,
							},
							"10": {
								Required: false,
							},
							"11": {
								Required: false,
							},
						},
					},
				},
				Name: "",
				Jobs: map[string]job{
					"build": {
						Steps: []parsedStep{
							{
								Uses: &model.UsesRepository{
									Repository: "owner/repo",
									Path:       "",
									Ref:        "master",
								},
							},
						},
					},
				},
			},
			error: nil,
		},
		{
			desc: "valid workflow_dispatch inputs",
			workflow: `
on:
  workflow_dispatch:
    inputs:
      name:
        required: true
      count:
        description: A number field
        default: 42
jobs:
  build:
    steps:
    - uses: owner/repo@master`,
			parsed: &parseTarget{
				On: workflowOnValue{
					EventConfig{
						Event: "workflow_dispatch",
						Inputs: &inputsMap{
							"name": {
								Required: true,
							},
							"count": {
								Required:    false,
								Description: "A number field",
								Default:     "42",
							},
						},
					},
				},
				Name: "",
				Jobs: map[string]job{
					"build": {
						Steps: []parsedStep{
							{
								Uses: &model.UsesRepository{
									Repository: "owner/repo",
									Path:       "",
									Ref:        "master",
								},
							},
						},
					},
				},
			},
			error: nil,
		},
		{
			desc: "invalid workflow_dispatch inputs",
			workflow: `
on:
  workflow_dispatch:
    inputs: [name, count]
jobs:
  build:
    steps:
    - uses: owner/repo@master`,
			parsed: nil,
			error:  errors.New("Invalid type for `on`"),
		},
		{
			desc: "steps parsing",
			workflow: `
on: push
jobs:
  thing:
    steps:
    - uses: owner/repo@master`,
			parsed: &parseTarget{
				On:   workflowOnValue{EventConfig{Event: "push"}},
				Name: "",
				Jobs: map[string]job{
					"thing": {
						Steps: []parsedStep{
							{
								Uses: &model.UsesRepository{
									Repository: "owner/repo",
									Path:       "",
									Ref:        "master",
								},
							},
						},
					},
				},
			},
			error: nil,
		},
		{
			desc: "a callable workflow",
			workflow: `
on:
  workflow_call:
jobs:
  thing:
    steps:
    - uses: owner/repo@master
`,
			parsed: &parseTarget{
				Name: "",
				On: workflowOnValue{
					EventConfig{Event: "workflow_call"},
				},
				Jobs: map[string]job{
					"thing": {
						Steps: []parsedStep{
							{
								Uses: &model.UsesRepository{
									Repository: "owner/repo",
									Path:       "",
									Ref:        "master",
								},
							},
						},
					},
				},
			},
		},
		{
			desc: "filter parsing",
			workflow: `
on:
  push:
    tags:
      - 'v*'
      - '!v*.*.*-*.*'
jobs:
  thing:
    steps:
    - uses: owner/repo@master`,
			parsed: &parseTarget{
				On: workflowOnValue{
					EventConfig{
						Event: "push",
						Tags: &stringList{
							"v*",
							"!v*.*.*-*.*",
						},
						Branches: nil,
					},
				},
				Name: "",
				Jobs: map[string]job{
					"thing": {
						Steps: []parsedStep{
							{
								Uses: &model.UsesRepository{
									Repository: "owner/repo",
									Path:       "",
									Ref:        "master",
								},
							},
						},
					},
				},
			},
			error: nil,
		},
		{
			desc: "error message for 'schedules'",
			workflow: `
on:
  schedules:
  - cron: "* * * 2 *"

jobs:
  thing:
    steps:
    - uses: owner/repo@master`,
			error: newParseError("`schedules` is not a valid event name, did you mean `schedule`?"),
		},
		{
			desc: "error message for using any random key as schedules",
			workflow: `
on:
  flobbleWobble:
  - cron: "* * * 2 *"

jobs:
  thing:
    steps:
    - uses: owner/repo@master`,
			error: newParseError("`flobbleWobble` is not a valid event name"),
		},
		{
			desc: "rejects invalid event names",
			workflow: `
on:
  push:
  flobbleWobble:
  issues:

jobs:
  thing:
    steps:
    - uses: owner/repo@master`,
			error: newParseError("`flobbleWobble` is not a valid event name"),
		}, {
			desc: "rejects invalid event names in list form",
			workflow: `
on: [push, flobbleWobble, issues]

jobs:
  thing:
    steps:
    - uses: owner/repo@master`,
			error: newParseError("`flobbleWobble` is not a valid event name"),
		},
		{
			desc: "using a list value for events where that's not valid",
			workflow: `
on:
  push:
  - branches: ["master"]

jobs:
  thing:
    steps:
    - uses: owner/repo@master`,
			error: newParseError("`push` requires a map value"),
		},
		{
			desc: "using a map value for schedules",
			workflow: `
on:
  schedule:
    cron: "* * * * *"

jobs:
  thing:
    steps:
    - uses: owner/repo@master`,
			error: newParseError("`schedule` accepts a list of one or more maps with the `cron` key set"),
		},
		{
			desc: "missing cron key for schedule item",
			workflow: `
on:
  schedule:
  - branches: "master"

jobs:
  thing:
    steps:
    - uses: owner/repo@master`,
			error: newParseError("`schedule` list items require the `cron` key to be set"),
		},
		{
			desc: "empty cron list",
			workflow: `
on:
  schedule:

jobs:
  thing:
    steps:
    - uses: owner/repo@master`,
			error: newParseError("`schedule` accepts a list of one or more maps with the `cron` key set"),
		},
		{
			desc: "positive and negative filters are mutually exclusive",
			workflow: `on:
  push:
    paths-ignore: ["*"]
    paths: "*"

jobs: { a: { steps: [{run: "hi"}] }}
    `,
			error: newParseError("you may only define one of `paths` and `paths-ignore` for a single event"),
		},
		{
			desc: "invalid cron expressions",
			workflow: `on:
  schedule:
  - cron: "not cron"

jobs: { a: { steps: [{run: "hi"}] }}
    `,
			error: newParseError("invalid `cron` attribute \"not cron\""),
		},
		{
			desc: "ambiguous step",
			workflow: `
on: push

jobs:
  thing:
    steps:
    - uses: owner/repo@master
      run: ls
    `,
			error: userFacingParseError{msg: "a step cannot have both the `uses` and `run` keys"},
		},
		{
			desc: "step uses workflow",
			workflow: `
on: push

jobs:
  thing:
    steps:
    - uses: owner/repo/.github/workflows/workflow.yml@master`,
			error: userFacingParseError{msg: "reusable workflows should be referenced at the top-level `jobs.*.uses' key, not within steps"},
		},
		{
			desc: "untyped step",
			workflow: `
on: push

jobs:
  thing:
    steps:
    - with:
        node-version: "hi"
    `,
			error: userFacingParseError{msg: "every step must define a `uses` or `run` key"},
		},
		{
			desc: "workflow_dispatch event trigger",
			workflow: `
on: workflow_dispatch
jobs:
  thing:
    steps:
    - run: echo
    `,
			error: nil,
			parsed: &parseTarget{
				On: workflowOnValue{EventConfig{Event: "workflow_dispatch"}},
				Jobs: map[string]job{
					"thing": {
						Steps: []parsedStep{
							{},
						},
					},
				},
			},
		},
		{
			desc: "pull_request_target event trigger",
			workflow: `
on: pull_request_target
jobs:
  thing:
    steps:
    - run: echo
    `,
			error: nil,
			parsed: &parseTarget{
				On: workflowOnValue{EventConfig{Event: "pull_request_target"}},
				Jobs: map[string]job{
					"thing": {
						Steps: []parsedStep{
							{},
						},
					},
				},
			},
		},
		{
			desc: "single need",
			workflow: `
on: push
jobs:
  thing:
    needs: build
    steps:
    - run: echo`,
			error: nil,
			parsed: &parseTarget{
				On: workflowOnValue{EventConfig{Event: "push"}},
				Jobs: map[string]job{
					"thing": {
						Needs: stringList{"build"},
						Steps: []parsedStep{
							{},
						},
					},
				},
			},
		},
		{
			desc: "multiple needs",
			workflow: `
on: push
jobs:
  thing:
    needs: [build, prething]
    steps:
    - run: echo`,
			error: nil,
			parsed: &parseTarget{
				On: workflowOnValue{EventConfig{Event: "push"}},
				Jobs: map[string]job{
					"thing": {
						Needs: stringList{"build", "prething"},
						Steps: []parsedStep{
							{},
						},
					},
				},
			},
		},
		{
			desc: "matrix strategy",
			workflow: `
on: push
jobs:
  thing:
    strategy:
      matrix:
        os: [win,linux]
        version: [1,2,3]
    steps:
    - run: echo`,
			error: nil,
			parsed: &parseTarget{
				On: workflowOnValue{EventConfig{Event: "push"}},
				Jobs: map[string]job{
					"thing": {
						Strategy: &jobStrategy{
							Matrix: map[string]any{
								"os":      []any{"win", "linux"},
								"version": []any{1, 2, 3},
							},
						},
						Steps: []parsedStep{
							{},
						},
					},
				},
			},
		},
		{
			desc: "dynamic max-parallel",
			workflow: `
on:
  workflow_dispatch:
    inputs:
      input1:
        type: number
jobs:
  thing:
    strategy:
      matrix:
        vals: [1,2]
      max-parallel: ${{ inputs.input1 }}
    steps:
    - run: echo`,
			error: nil,
			parsed: &parseTarget{
				On: workflowOnValue{
					EventConfig{
						Event: "workflow_dispatch",
						Inputs: &inputsMap{
							"input1": {
								Required: false,
								Type:     "number",
							},
						},
					},
				},
				Jobs: map[string]job{
					"thing": {
						Strategy: &jobStrategy{
							Matrix: map[string]any{
								"vals": []any{1, 2},
							},
						},
						Steps: []parsedStep{
							{},
						},
					},
				},
			},
		},
		{
			desc: "dynamic matrix strategy",
			workflow: `
on: push
jobs:
  thing:
    strategy:
      matrix: ${{fromJson(needs.job1.outputs.matrix)}}
    steps:
    - run: echo`,
			error: nil,
			parsed: &parseTarget{
				On: workflowOnValue{EventConfig{Event: "push"}},
				Jobs: map[string]job{
					"thing": {
						Strategy: &jobStrategy{
							Matrix: "${{fromJson(needs.job1.outputs.matrix)}}",
						},
						Steps: []parsedStep{
							{},
						},
					},
				},
			},
		},
		{
			desc: "dynamic strategy",
			workflow: `
on: push
jobs:
  thing:
    strategy: ${{fromJson(needs.job1.outputs.strategy)}}
    steps:
    - run: echo`,
			error: nil,
			parsed: &parseTarget{
				On: workflowOnValue{EventConfig{Event: "push"}},
				Jobs: map[string]job{
					"thing": {
						Strategy: &jobStrategy{
							Expression: "${{fromJson(needs.job1.outputs.strategy)}}",
						},
						Steps: []parsedStep{
							{},
						},
					},
				},
			},
		},
		{
			desc: "invalid strategy",
			workflow: `
on: push
jobs:
  invalid:
    strategy: [ array, of, strings ]`,
			error: newParseError("Invalid type for `job.strategy`"),
		},
		{
			desc: "jobs defined with environment but missing steps",
			workflow: `
on: push
jobs:
  thing1:
    environment:
      name: "Static Environment Name 1"
  thing2:
    environment:
      name: "Static Environment Name 2"
`,
			error: newParseError("No steps defined in `steps` and no workflow called in `uses` for the following jobs: thing1, thing2"),
		},
		{
			desc: "accepts job environments",
			workflow: `
on: push
jobs:
  a:
    environment: Static Environment Name 1
    steps:
    - run: echo Hi
  b:
    environment:
      name: Static Environment Name 1
    steps:
    - run: echo Hi
  c:
    environment:
      name: my ${{ secrets.ENVIRONMENT_NAME }} environment
    needs: a
    steps:
    - run: echo Hi`,
			error: nil,
			parsed: &parseTarget{
				On: workflowOnValue{EventConfig{Event: "push"}},
				Jobs: map[string]job{
					"a": {
						Environment: &jobEnvironment{
							Name:      "Static Environment Name 1",
							IsDynamic: false,
						},
						Steps: []parsedStep{
							{},
						},
					},
					"b": {
						Environment: &jobEnvironment{
							Name:      "Static Environment Name 1",
							IsDynamic: false,
						},
						Steps: []parsedStep{
							{},
						},
					},
					"c": {
						Environment: &jobEnvironment{
							Name:      "my ${{ secrets.ENVIRONMENT_NAME }} environment",
							IsDynamic: true,
						},
						Needs: []string{"a"},
						Steps: []parsedStep{
							{},
						},
					},
				},
			},
		},
		{
			desc: "invalid environment",
			workflow: `
on: push
jobs:
  invalid:
    environment:
      name: [ array, of, strings ]`,
			error: newParseError("Invalid type for `job.environment`"),
		},
		{
			desc: "accepts workflow concurrency",
			workflow: `
on: push
concurrency:
  group: test
  cancel-in-progress: true
jobs:
  build:
    steps:
    - run: echo Hi`,
			error: nil,
			parsed: &parseTarget{
				On: workflowOnValue{EventConfig{Event: "push"}},
				Concurrency: &concurrencyValue{
					Group: "test",
				},
				Jobs: map[string]job{
					"build": {
						Steps: []parsedStep{
							{},
						},
					},
				},
			},
		},
		{
			desc: "accepts job concurrency",
			workflow: `
on: push
jobs:
  build:
    concurrency: "test-job-group"
    steps:
    - run: echo Hi`,
			error: nil,
			parsed: &parseTarget{
				On: workflowOnValue{EventConfig{Event: "push"}},
				Jobs: map[string]job{
					"build": {
						Concurrency: &concurrencyValue{
							Group: "test-job-group",
						},
						Steps: []parsedStep{
							{},
						},
					},
				},
			},
		},
		{
			desc: "invalid workflow concurrency",
			workflow: `
on: push
concurrency: "this-is-a-very-long-group-name-0Igep549E6-io3oCPs-V1RnyCll6Z-vdazte3J3x6G-oGYFiz09SdZK-itnR410s-dZZLiswY9-wf7f2z3m-Ec3C9r22g-SNnRHlce9u-PTC9WmdwK-ct4OfIDtdtNSj-iRCFRwZJAyB73-AlSs8g0fcyD-tbNaJ7qMkBsftY-fmH3f8D44-mXm0V18G8CGfS-meHe2Ykbkul-r9MqPyRiEwQ2t-qBzE9wxMsFbj-GCkJDaHtgjvE-vrzjjFZq8hF-dXpDiyqcGa-BhjOsGDEEZ6u-WpeJiRYFcqp-wsBIY9WKgzO-BJPmYTBWHn-Wwa0tWog5kbo7-PTqNUNT5KrD-5hl8lISI6-6TpCH7OpqeP-fKSCu00tG5-sPyU9z0H0wbuB-IAQXgwrobRB"
jobs:
  invalid:
    runs-on: self-hosted
    steps:
    - run: echo Hi`,
			error: newParseError("Concurrency group name shouldn't exceed 400 characters"),
		},
		{
			desc: "invalid job concurrency",
			workflow: `
on: push
jobs:
  invalid:
    concurrency:
      group: "this-is-a-very-long-group-name-0Igep549E6-io3oCPs-V1RnyCll6Z-vdazte3J3x6G-oGYFiz09SdZK-itnR410s-dZZLiswY9-wf7f2z3m-Ec3C9r22g-SNnRHlce9u-PTC9WmdwK-ct4OfIDtdtNSj-iRCFRwZJAyB73-AlSs8g0fcyD-tbNaJ7qMkBsftY-fmH3f8D44-mXm0V18G8CGfS-meHe2Ykbkul-r9MqPyRiEwQ2t-qBzE9wxMsFbj-GCkJDaHtgjvE-vrzjjFZq8hF-dXpDiyqcGa-BhjOsGDEEZ6u-WpeJiRYFcqp-wsBIY9WKgzO-BJPmYTBWHn-Wwa0tWog5kbo7-PTqNUNT5KrD-5hl8lISI6-6TpCH7OpqeP-fKSCu00tG5-sPyU9z0H0wbuB-IAQXgwrobRB"
    runs-on: self-hosted
    steps:
    - run: echo Hi`,
			error: newParseError("Concurrency group name shouldn't exceed 400 characters"),
		},
		{
			desc: "GITHUB_TOKEN is reserved and not allowed to be used as callable workflow secret name - reusable workflow itself",
			workflow: `
on:
  workflow_call:
    secrets:
      GiThUb_tOkEn:

jobs:
  build1:
    steps:
    - run: echo hello world`,
			featureFlags: types.WorkflowFeatureFlags{},
			error:        newParseErrorWithLine(5, "secret name `GiThUb_tOkEn` within `workflow_call` can not be used since it would collide with system reserved name"),
		},
		{
			desc: "Do not error if secrets block is used in other events (avoid breaking change)",
			workflow: `
on:
  workflow_dispatch:
    secrets:
      GiThUb_tOkEn:

jobs:
  build1:
    steps:
    - run: echo hello world`,
			featureFlags: types.WorkflowFeatureFlags{},
			error:        nil,
			parsed: &parseTarget{
				On: workflowOnValue{
					EventConfig{
						Event: "workflow_dispatch",
						Secrets: &secretsMap{
							"GiThUb_tOkEn": {
								Description: "",
								Required:    false,
								Default:     "",
								Line:        5,
							},
						},
					},
				},
				Jobs: map[string]job{
					"build1": {
						Steps: []parsedStep{
							{},
						},
					},
				},
			},
		},
		{
			desc: "a truncated workflow file",
			workflow: `
on: push
name: "simple"
jobs:
  thing:
    steps:
    - uses: owner/repo@master`,
			truncated: true,
			error:     errWorkflowFileTruncated,
		},
		{
			desc: "a simple workflow with runs-on",
			workflow: `
on: push
jobs:
  thing:
    runs-on: ubuntu-latest
    steps:
    - uses: owner/repo@master`,
			parsed: &parseTarget{
				Name: "workflow.yml",
				On:   workflowOnValue{EventConfig{Event: "push"}},
				Jobs: map[string]job{
					"thing": {
						Steps: []parsedStep{
							{
								Uses: &model.UsesRepository{
									Repository: "owner/repo",
									Path:       "",
									Ref:        "master",
								},
							},
						},
						RunsOn: &runsOnConfig{
							Labels: []string{"ubuntu-latest"},
						},
					},
				},
			},
			path: "workflow.yml",
		},
		{
			desc: "a simple workflow with runs-on of mapping type",
			workflow: `
on: push
jobs:
  thing:
    runs-on:
      group: ubuntu-runners
    steps:
    - uses: owner/repo@master`,
			parsed: &parseTarget{
				Name: "workflow.yml",
				On:   workflowOnValue{EventConfig{Event: "push"}},
				Jobs: map[string]job{
					"thing": {
						Steps: []parsedStep{
							{
								Uses: &model.UsesRepository{
									Repository: "owner/repo",
									Path:       "",
									Ref:        "master",
								},
							},
						},
						RunsOn: &runsOnConfig{
							Labels: nil,
						},
					},
				},
			},
			path: "workflow.yml",
		},
		{
			desc: "job with snapshot, inline name",
			workflow: `
on: push
jobs:
  build:
    snapshot: imageName
    steps:
    - run: echo Hi`,
			error: nil,
			parsed: &parseTarget{
				On: workflowOnValue{EventConfig{Event: "push"}},
				Jobs: map[string]job{
					"build": {
						Snapshot: &snapshotConfig{
							ImageName: "imageName",
							Version:   nil,
						},
						Steps: []parsedStep{
							{},
						},
					},
				},
			},
		},
		{
			desc: "job with snapshot object, name only",
			workflow: `
on: push
jobs:
  build:
    snapshot:
      image-name: imageName
    steps:
    - run: echo Hi`,
			error: nil,
			parsed: &parseTarget{
				On: workflowOnValue{EventConfig{Event: "push"}},
				Jobs: map[string]job{
					"build": {
						Snapshot: &snapshotConfig{
							ImageName: "imageName",
							Version:   nil,
						},
						Steps: []parsedStep{
							{},
						},
					},
				},
			},
		},
		{
			desc: "job with snapshot object, name and version",
			workflow: `
on: push
jobs:
  build:
    snapshot:
      image-name: imageName
      version: 1.2.*
    steps:
    - run: echo Hi`,
			error: nil,
			parsed: &parseTarget{
				On: workflowOnValue{EventConfig{Event: "push"}},
				Jobs: map[string]job{
					"build": {
						Snapshot: &snapshotConfig{
							ImageName: "imageName",
							Version:   &snapshotVersion,
						},
						Steps: []parsedStep{
							{},
						},
					},
				},
			},
		},
	}

	for _, test := range tests {
		t.Run(test.desc, func(tt *testing.T) {
			ctx := context.Background()
			wfSrc := test.wfSrc
			if wfSrc == nil {
				wfSrc = NullWorkflowSource{}
			}
			file := types.ResolvedFile{Text: test.workflow, Path: test.path, IsTruncated: test.truncated}
			r, err := Parse(ctx, file, test.featureFlags, wfSrc, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())
			assert.Equal(tt, test.error, err)

			if test.parsed == nil {
				assert.Nil(tt, r)
			} else {
				require.NotNil(tt, r)
				assert.Equal(tt, test.parsed.Name, r.Name)
				assert.ElementsMatch(tt, test.parsed.On, r.parsed.On)
				assert.Equal(tt, test.path, r.Path)
				assert.Equal(tt, test.parsed.Jobs, r.parsed.Jobs)
				assert.Equal(tt, file, r.File)
			}
		})
	}
}

func TestParseWithCalledWorkflows(t *testing.T) {
	tests := []struct {
		desc              string
		workflow          string
		parsed            *parseTarget
		path              string
		featureFlags      types.WorkflowFeatureFlags
		wfSrc             WorkflowSource
		error             error
		testWfSrcParsedWf func(*testing.T, job)
	}{
		{
			desc: "a job that uses another workflow",
			workflow: `
on:
  push
jobs:
  build:
    uses: actions/workflows/.github/workflows/node.yml@v1`,
			featureFlags: types.WorkflowFeatureFlags{},
			wfSrc: &StubWorkflowSource{
				SourceMap: map[string]WorkflowDetails{
					"actions/workflows/.github/workflows/node.yml@v1": {
						Content: `
on:
  workflow_call:
jobs:
  thing:
    steps:
    - uses: owner/repo@master`,
						RefType: "refs/tags/",
					}}},
			parsed: &parseTarget{
				On: workflowOnValue{
					EventConfig{
						Event: "push",
					},
				},
				Name: "",
				Jobs: map[string]job{
					"build": {
						Uses: &usesWorkflow{
							Uses: model.WorkflowRef{
								Owner:   "actions",
								Repo:    "workflows",
								Path:    ".github/workflows/node.yml",
								Version: model.VersionRef{GitRef: pstring("v1")},
							},
							Line: 6,
						},
					},
				},
			},
			error: nil,
		},
		{
			desc: "a job that uses local workflow with nwo and without version",
			workflow: `
on:
  push
jobs:
  build:
    uses: actions/workflows/.github/workflows/node.yml`,
			featureFlags: types.WorkflowFeatureFlags{},
			error:        newParseErrorWithLine(6, "invalid value workflow reference: no version specified"),
		},
		{
			desc: "a job that uses local workflow without nwo and with version",
			workflow: `
on:
  push
jobs:
  build:
    uses: ./.github/workflows/node.yml@ver1`,
			featureFlags: types.WorkflowFeatureFlags{},
			error:        newParseErrorWithLine(6, "invalid value workflow reference: cannot specify version when calling local workflows"),
		},
		{
			desc: "a job that uses local workflow without nwo and without version",
			workflow: `
on:
  push
jobs:
  build:
    uses: ./.github/workflows/node.yml`,
			featureFlags: types.WorkflowFeatureFlags{},
			wfSrc: &StubWorkflowSource{
				SourceMap: map[string]WorkflowDetails{
					"owner4/repo2/.github/workflows/node.yml@testSHAasdf123": {
						Content: `
on:
  workflow_call:
jobs:
  thing:
    steps:
    - uses: owner/repo@master`,
					}},
				CallerRepoID: "R_two",
				CallerRepoNWO: types.RepositoryFullName{
					Owner: "owner4",
					Name:  "repo2",
				},
				CallerRepoSHA: "testSHAasdf123",
			},
			parsed: &parseTarget{
				On: workflowOnValue{
					EventConfig{
						Event: "push",
					},
				},
				Name: "",
				Jobs: map[string]job{
					"build": {
						Uses: &usesWorkflow{
							Uses: model.WorkflowRef{
								Owner:   ".",
								Repo:    ".",
								Path:    ".github/workflows/node.yml",
								Version: model.VersionRef{},
							},
							Line: 6,
						},
					},
				},
			},
			error: nil,
		},
		{
			desc: "Calling a reusable workflow with secrets",
			workflow: `
on:
  push
jobs:
  call1:
    uses: ./.github/workflows/node.yml
    secrets: inherit
  call2:
    uses: ./.github/workflows/node.yml
    secrets:
      secret1: test1
      secret2: test2
      secret3: ${{ secrets.REPO_SECRET }}`,
			featureFlags: types.WorkflowFeatureFlags{},
			wfSrc: &StubWorkflowSource{
				CallerRepoID: "R_two",
				CallerRepoNWO: types.RepositoryFullName{
					Owner: "owner4",
					Name:  "repo2",
				},
				SourceMap: map[string]WorkflowDetails{
					"owner4/repo2/.github/workflows/node.yml": {
						Content: `
on:
  workflow_call:
jobs:
  thing:
    runs-on: ubuntu-latest
    steps:
    - uses: owner/repo@master`,
						RefType: "refs/heads/",
					},
				}},
			parsed: &parseTarget{
				On: workflowOnValue{
					EventConfig{
						Event: "push",
					},
				},
				Name: "",
				Jobs: map[string]job{
					"call1": {
						Uses: &usesWorkflow{
							Uses: model.WorkflowRef{
								Owner:   ".",
								Repo:    ".",
								Path:    ".github/workflows/node.yml",
								Version: model.VersionRef{},
							},
							Line: 6,
						},
						Secrets: &jobSecrets{
							Inherit: true,
						},
					},
					"call2": {
						Uses: &usesWorkflow{
							Uses: model.WorkflowRef{
								Owner:   ".",
								Repo:    ".",
								Path:    ".github/workflows/node.yml",
								Version: model.VersionRef{},
							},
							Line: 9,
						},
						Secrets: &jobSecrets{
							secrets: map[string]string{
								"secret1": "test1",
								"secret2": "test2",
								"secret3": "${{ secrets.REPO_SECRET }}",
							},
						},
					},
				},
			},
			testWfSrcParsedWf: func(t *testing.T, parsedWfJob job) {
				assert.Equal(t, "ubuntu-latest", parsedWfJob.RunsOn.Labels[0])
			},
			error: nil,
		},
		{
			desc: "Calling a reusable workflow with invalid secrets",
			workflow: `
on:
  push
jobs:
  call1:
    uses: ./.github/workflows/node.yml
    secrets:
      secret1
      secret2 test2`,
			featureFlags: types.WorkflowFeatureFlags{},
			wfSrc: &StubWorkflowSource{
				SourceMap: map[string]WorkflowDetails{
					"./.github/workflows/node.yml@": {
						Content: `
on:
  workflow_call:
jobs:
  thing:
    steps:
    - uses: owner/repo@master`,
						RefType: "refs/heads/",
					}}},
			error: newParseErrorWithLine(8, "invalid value for secrets. Expected \"inherit\" keyword or explicit map of secrets"),
		},
		{
			desc: "a job that uses another workflow, but it isn't callable",
			workflow: `
on:
  push
jobs:
  build:
    uses: actions/workflows/.github/workflows/node.yml@v1`,
			featureFlags: types.WorkflowFeatureFlags{},
			wfSrc: &StubWorkflowSource{
				SourceMap: map[string]WorkflowDetails{
					"actions/workflows/.github/workflows/node.yml@v1": {
						Content: `
on:
  push:
jobs:
  thing:
    steps:
    - uses: owner/repo@master`,
						RefType: "refs/tags/",
					}}},
			error: newCalledWorkflowParseErrorWithLine(6, ParseError{message: "workflow is not reusable as it is missing a `on.workflow_call` trigger"}, `"actions/workflows/.github/workflows/node.yml@v1" (source tag with sha:v1)`),
		},
		{
			desc: "Confirm user received missing on.workflow_call error when using on.workflow_run in referenced invalid workflow_run",
			workflow: `
on:
  push:
jobs:
  build:
    uses: actions/workflows/.github/workflows/node.yml@v1`,
			featureFlags: types.WorkflowFeatureFlags{},
			wfSrc: &StubWorkflowSource{
				SourceMap: map[string]WorkflowDetails{
					"actions/workflows/.github/workflows/node.yml@v1": {
						Content: `
on: [workflow_run]
jobs:
  thing:
    steps:
    - uses: owner/repo@master`,
						RefType: "refs/tags/",
					}}},
			error: newCalledWorkflowParseErrorWithLine(6, ParseError{message: "workflow is not reusable as it is missing a `on.workflow_call` trigger"}, `"actions/workflows/.github/workflows/node.yml@v1" (source tag with sha:v1)`),
		},
		{
			desc: "Valid on.workflow_call and invalid on.workflow_run should show workflow_run error",
			workflow: `
on:
  push:
jobs:
  build:
    uses: actions/workflows/.github/workflows/node.yml@v1`,
			featureFlags: types.WorkflowFeatureFlags{},
			wfSrc: &StubWorkflowSource{
				SourceMap: map[string]WorkflowDetails{
					"actions/workflows/.github/workflows/node.yml@v1": {
						Content: `
on: [workflow_run, workflow_call]
jobs:
  thing:
    steps:
    - uses: owner/repo@master`,
						RefType: "refs/tags/",
					}}},
			error: newCalledWorkflowParseErrorWithLine(6, ParseError{message: "`on.workflow_run` does not reference any workflows. See https://docs.github.com/actions/learn-github-actions/events-that-trigger-workflows#workflow_run for more information"},
				`"actions/workflows/.github/workflows/node.yml@v1" (source tag with sha:v1)`),
		},
		{
			desc: "Confirm user received missing on.workflow_call error when using on.workflow_run in referenced valid workflow_run",
			workflow: `
name: caller
on:
  push:
jobs:
  build:
    uses: actions/workflows/.github/workflows/node.yml@v1`,
			featureFlags: types.WorkflowFeatureFlags{},
			wfSrc: &StubWorkflowSource{
				SourceMap: map[string]WorkflowDetails{
					"actions/workflows/.github/workflows/node.yml@v1": {
						Content: `
on:
  workflow_run:
    workflows: ["caller"]
jobs:
  thing:
    steps:
    - uses: owner/repo@master`,
						RefType: "refs/tags/",
					}}},
			error: newCalledWorkflowParseErrorWithLine(7, ParseError{message: "workflow is not reusable as it is missing a `on.workflow_call` trigger"},
				`"actions/workflows/.github/workflows/node.yml@v1" (source tag with sha:v1)`),
		},
		{
			desc: "recursive callable workflows at precisely max depth (3)",
			workflow: `
on:
  push
jobs:
  build:
    uses: actions/workflows/.github/workflows/called1.yml@v1`,
			featureFlags: types.WorkflowFeatureFlags{},
			wfSrc: &StubWorkflowSource{
				SourceMap: map[string]WorkflowDetails{
					"actions/workflows/.github/workflows/called1.yml@v1": {
						Content: `
on:
  workflow_call:
jobs:
  build1:
    uses: actions/workflows/.github/workflows/called2.yml@v1`,
						RefType: "refs/tags/",
					},
					"actions/workflows/.github/workflows/called2.yml@v1": {
						Content: `
on:
  workflow_call:
jobs:
  build1:
    uses: actions/workflows/.github/workflows/called3.yml@v1`,
						RefType: "refs/tags/",
					},
					"actions/workflows/.github/workflows/called3.yml@v1": {
						Content: `
on:
  workflow_call:
jobs:
  build2:
    runs-on: ubuntu-latest
    steps:
      - run: echo hello world`,
						RefType: "refs/tags/",
					},
				}},
			parsed: &parseTarget{
				On: workflowOnValue{
					EventConfig{
						Event: "push",
					},
				},
				Name: "",
				Jobs: map[string]job{
					"build": {
						Uses: &usesWorkflow{
							Uses: model.WorkflowRef{
								Owner:   "actions",
								Repo:    "workflows",
								Path:    ".github/workflows/called1.yml",
								Version: model.VersionRef{GitRef: pstring("v1")},
							},
							Line: 6,
						},
					},
				},
			},
			testWfSrcParsedWf: func(t *testing.T, parsedWfJob job) {
				assert.Equal(t, "ubuntu-latest", parsedWfJob.RunsOn.Labels[0])
			},
		},
		{
			desc: "recursive callable workflows at one beyond max depth (3)",
			workflow: `
on:
  push
jobs:
  job1:
    uses: actions/workflows/.github/workflows/called1.yml@v1`,
			featureFlags: types.WorkflowFeatureFlags{},
			wfSrc: &StubWorkflowSource{
				SourceMap: map[string]WorkflowDetails{
					"actions/workflows/.github/workflows/called1.yml@v1": {
						Content: `
on:
  workflow_call:
jobs:
  job2:
    uses: actions/workflows/.github/workflows/called2.yml@v1`,
						RefType: "refs/tags/",
					},
					"actions/workflows/.github/workflows/called2.yml@v1": {
						Content: `
on:
  workflow_call:
jobs:
  job3:
    uses: actions/workflows/.github/workflows/called3.yml@v1`,
						RefType: "refs/tags/",
					},
					"actions/workflows/.github/workflows/called3.yml@v1": {
						Content: `
on:
  workflow_call:
jobs:
  job4:
    uses: actions/workflows/.github/workflows/called4.yml@v1`,
						RefType: "refs/tags/",
					},
					"actions/workflows/.github/workflows/called4.yml@v1": {
						Content: `
on:
  workflow_call:
jobs:
  job5:
    steps:
      - run: echo }hello world`,
						RefType: "refs/tags/",
					},
				},
			},
			error: newCalledWorkflowParseErrorWithLine(6, CalledWorkflowParseError{
				chain: []string{`"actions/workflows/.github/workflows/called2.yml@v1" (source tag with sha:v1)`,
					`"actions/workflows/.github/workflows/called3.yml@v1" (source tag with sha:v1)`},
				message: `job "job4" calls workflow "actions/workflows/.github/workflows/called4.yml@v1", but doing so would exceed the limit on called workflow depth of 3`,
			}, `"actions/workflows/.github/workflows/called1.yml@v1" (source tag with sha:v1)`),
		},
		{
			desc: "uses too many callable workflows standard limit",
			workflow: `
on:
  push
jobs:
  build1:
    uses: actions/workflows/.github/workflows/callable.yml@v1
  build2:
    uses: actions/workflows/.github/workflows/callable.yml@v2
  build3:
    uses: actions/workflows/.github/workflows/callable.yml@v3
  build4:
    uses: actions/workflows/.github/workflows/callable.yml@v4
  build5:
    uses: actions/workflows/.github/workflows/callable.yml@v5
  build6:
    uses: actions/workflows/.github/workflows/callable.yml@v6
  build7:
    uses: actions/workflows/.github/workflows/callable.yml@v7
  build8:
    uses: actions/workflows/.github/workflows/callable.yml@v8
  build9:
    uses: actions/workflows/.github/workflows/callable.yml@v9
  build10:
    uses: actions/workflows/.github/workflows/callable.yml@v10
  build11:
    uses: actions/workflows/.github/workflows/callable.yml@v11
  build12:
    uses: actions/workflows/.github/workflows/callable.yml@v12
  build13:
    uses: actions/workflows/.github/workflows/callable.yml@v13
  build14:
    uses: actions/workflows/.github/workflows/callable.yml@v14
  build15:
    uses: actions/workflows/.github/workflows/callable.yml@v15
  build16:
    uses: actions/workflows/.github/workflows/callable.yml@v16
  build17:
    uses: actions/workflows/.github/workflows/callable.yml@v17
  build18:
    uses: actions/workflows/.github/workflows/callable.yml@v18
  build19:
    uses: actions/workflows/.github/workflows/callable.yml@v19
  build20:
    uses: actions/workflows/.github/workflows/callable.yml@v20
  build21:
    uses: actions/workflows/.github/workflows/callable.yml@v21`,
			featureFlags: types.WorkflowFeatureFlags{},
			wfSrc: &StubWorkflowSource{
				SourceMap: map[string]WorkflowDetails{
					"actions/workflows/.github/workflows/callable.yml@v1": {
						Content: `
on:
  workflow_call:
jobs:
  build:
    steps:
    - run: echo hello world`,
						RefType: "refs/tags/",
					}}},
			error: newParseError("too many workflows are referenced, total: 21, limit: 20"),
		},
		{
			desc: "uses too many callable workflows extended limit",
			workflow: `
on:
  push
jobs:
  build1:
    uses: actions/workflows/.github/workflows/callable.yml@v1
  build2:
    uses: actions/workflows/.github/workflows/callable.yml@v2
  build3:
    uses: actions/workflows/.github/workflows/callable.yml@v3
  build4:
    uses: actions/workflows/.github/workflows/callable.yml@v4
  build5:
    uses: actions/workflows/.github/workflows/callable.yml@v5
  build6:
    uses: actions/workflows/.github/workflows/callable.yml@v6
  build7:
    uses: actions/workflows/.github/workflows/callable.yml@v7
  build8:
    uses: actions/workflows/.github/workflows/callable.yml@v8
  build9:
    uses: actions/workflows/.github/workflows/callable.yml@v9
  build10:
    uses: actions/workflows/.github/workflows/callable.yml@v10
  build11:
    uses: actions/workflows/.github/workflows/callable.yml@v11
  build12:
    uses: actions/workflows/.github/workflows/callable.yml@v12
  build13:
    uses: actions/workflows/.github/workflows/callable.yml@v13
  build14:
    uses: actions/workflows/.github/workflows/callable.yml@v14
  build15:
    uses: actions/workflows/.github/workflows/callable.yml@v15
  build16:
    uses: actions/workflows/.github/workflows/callable.yml@v16
  build17:
    uses: actions/workflows/.github/workflows/callable.yml@v17
  build18:
    uses: actions/workflows/.github/workflows/callable.yml@v18
  build19:
    uses: actions/workflows/.github/workflows/callable.yml@v19
  build20:
    uses: actions/workflows/.github/workflows/callable.yml@v20
  build21:
    uses: actions/workflows/.github/workflows/callable.yml@v21
  build22:
    uses: actions/workflows/.github/workflows/callable.yml@v22
  build23:
    uses: actions/workflows/.github/workflows/callable.yml@v23
  build24:
    uses: actions/workflows/.github/workflows/callable.yml@v24
  build25:
    uses: actions/workflows/.github/workflows/callable.yml@v25
  build26:
    uses: actions/workflows/.github/workflows/callable.yml@v26
  build27:
    uses: actions/workflows/.github/workflows/callable.yml@v27
  build28:
    uses: actions/workflows/.github/workflows/callable.yml@v28
  build29:
    uses: actions/workflows/.github/workflows/callable.yml@v29
  build30:
    uses: actions/workflows/.github/workflows/callable.yml@v30
  build31:
    uses: actions/workflows/.github/workflows/callable.yml@v31
  build32:
    uses: actions/workflows/.github/workflows/callable.yml@v32
  build33:
    uses: actions/workflows/.github/workflows/callable.yml@v33
  build34:
    uses: actions/workflows/.github/workflows/callable.yml@v34
  build35:
    uses: actions/workflows/.github/workflows/callable.yml@v35
  build36:
    uses: actions/workflows/.github/workflows/callable.yml@v36
  build37:
    uses: actions/workflows/.github/workflows/callable.yml@v37
  build38:
    uses: actions/workflows/.github/workflows/callable.yml@v38
  build39:
    uses: actions/workflows/.github/workflows/callable.yml@v39
  build40:
    uses: actions/workflows/.github/workflows/callable.yml@v40
  build41:
    uses: actions/workflows/.github/workflows/callable.yml@v41
  build42:
    uses: actions/workflows/.github/workflows/callable.yml@v42
  build43:
    uses: actions/workflows/.github/workflows/callable.yml@v43
  build44:
    uses: actions/workflows/.github/workflows/callable.yml@v44
  build45:
    uses: actions/workflows/.github/workflows/callable.yml@v45
  build46:
    uses: actions/workflows/.github/workflows/callable.yml@v46
  build47:
    uses: actions/workflows/.github/workflows/callable.yml@v47
  build48:
    uses: actions/workflows/.github/workflows/callable.yml@v48
  build49:
    uses: actions/workflows/.github/workflows/callable.yml@v49
  build50:
    uses: actions/workflows/.github/workflows/callable.yml@v50
  build51:
    uses: actions/workflows/.github/workflows/callable.yml@v51`,
			featureFlags: types.WorkflowFeatureFlags{
				IncreasedMaxWorkflowFilesReferencedEnabled: true,
			},
			wfSrc: &StubWorkflowSource{
				SourceMap: map[string]WorkflowDetails{
					"actions/workflows/.github/workflows/callable.yml@v1": {
						Content: `
on:
  workflow_call:
jobs:
  build:
    steps:
    - run: echo hello world`,
						RefType: "refs/tags/",
					}}},
			error: newParseError("too many workflows are referenced, total: 51, limit: 50"),
		},
		{
			desc: "a job that doesn't have a need or uses, with callable workflows enabled",
			workflow: `
on:
  push
jobs:
  build:`,
			featureFlags: types.WorkflowFeatureFlags{},
			error:        newParseError("No steps defined in `steps` and no workflow called in `uses` for the following jobs: build"),
		},
		{
			desc: "recursive callable workflows exceeding max depth",
			workflow: `
on:
  push
jobs:
  build:
    uses: actions/workflows/.github/workflows/recursive.yml@v1`,
			featureFlags: types.WorkflowFeatureFlags{},
			wfSrc: &StubWorkflowSource{
				SourceMap: map[string]WorkflowDetails{
					"actions/workflows/.github/workflows/recursive.yml@v1": {
						Content: `
on:
  workflow_call:
jobs:
  build1:
    uses: actions/workflows/.github/workflows/recursive.yml@v1`,
						RefType: "refs/tags/",
					},
				}},
			error: newCalledWorkflowParseErrorWithLine(6, CalledWorkflowParseError{
				chain: []string{`"actions/workflows/.github/workflows/recursive.yml@v1" (source tag with sha:v1)`,
					`"actions/workflows/.github/workflows/recursive.yml@v1" (source tag with sha:v1)`},
				message: `job "build1" calls workflow "actions/workflows/.github/workflows/recursive.yml@v1", but doing so would exceed the limit on called workflow depth of 3`,
			}, `"actions/workflows/.github/workflows/recursive.yml@v1" (source tag with sha:v1)`),
		},
		{
			desc: "GITHUB_TOKEN is reserved and not allowed to be used as callable workflow secret name - when called",
			workflow: `
on:
  push
jobs:
  build:
    uses: actions/workflows/.github/workflows/secretinput.yml@v1`,
			featureFlags: types.WorkflowFeatureFlags{},
			wfSrc: &StubWorkflowSource{
				SourceMap: map[string]WorkflowDetails{
					"actions/workflows/.github/workflows/secretinput.yml@v1": {
						Content: `
on:
  workflow_call:
    secrets:
      GiThUb_tOkEn:

jobs:
  build1:
    steps:
    - run: echo hello world`,
						RefType: "refs/tags/",
					},
				}},
			error: newCalledWorkflowParseErrorWithLine(6, ParseError{message: "secret name `GiThUb_tOkEn` within `workflow_call` can not be used since it would collide with system reserved name"},
				`"actions/workflows/.github/workflows/secretinput.yml@v1" (source tag with sha:v1)`),
		},
		{

			desc: "test secret name which don't collide",
			workflow: `
on:
  push
jobs:
  build:
    uses: actions/workflows/.github/workflows/secretinput.yml@v1`,
			featureFlags: types.WorkflowFeatureFlags{},
			wfSrc: &StubWorkflowSource{
				SourceMap: map[string]WorkflowDetails{
					"actions/workflows/.github/workflows/secretinput.yml@v1": {
						Content: `
on:
  workflow_call:
    secrets:
      token_github:

jobs:
  build1:
    steps:
    - run: echo hello world`,
						RefType: "refs/tags/",
					},
				}},
			parsed: &parseTarget{
				On: workflowOnValue{
					EventConfig{
						Event: "push",
					},
				},
				Name: "",
				Jobs: map[string]job{
					"build": {
						Uses: &usesWorkflow{
							Uses: model.WorkflowRef{
								Owner:   "actions",
								Repo:    "workflows",
								Path:    ".github/workflows/secretinput.yml",
								Version: model.VersionRef{GitRef: pstring("v1")},
							},
							Line: 6,
						},
					},
				},
			},
		},
		{
			desc: "a workflow with run name",
			workflow: `
on: push
name: "simple"
run-name: "run-name"
jobs:
  thing:
    steps:
    - uses: owner/repo@master`,
			parsed: &parseTarget{
				Name:              "simple",
				RunNameExpression: yaml.Node{Value: "run-name"},
				On:                workflowOnValue{EventConfig{Event: "push"}},
				Jobs: map[string]job{
					"thing": {
						Steps: []parsedStep{
							{
								Uses: &model.UsesRepository{
									Repository: "owner/repo",
									Path:       "",
									Ref:        "master",
								},
							},
						},
					},
				},
			},
			featureFlags: types.WorkflowFeatureFlags{},
			path:         "workflow.yml",
		},
		{
			desc: "a simple workflow with reuse-previous-outcome",
			workflow: `
on:
  push:
    reuse-previous-outcome: true
  pull_request:
jobs:
  thing:
    steps:
    - uses: owner/repo@master`,
			parsed: &parseTarget{
				Name: "workflow.yml",
				On:   workflowOnValue{EventConfig{Event: "push", ReusePreviousOutcome: true}, EventConfig{Event: "pull_request", ReusePreviousOutcome: false}},
				Jobs: map[string]job{
					"thing": {
						Steps: []parsedStep{
							{
								Uses: &model.UsesRepository{
									Repository: "owner/repo",
									Path:       "",
									Ref:        "master",
								},
							},
						},
					},
				},
			},
			path: "workflow.yml",
		},
		{
			desc: "a workflow with name that should be truncated",
			workflow: `
on: push
# name and run-name are 520 characters long
name: "9876543210987654321098765432109876543210987654321098765432109876543210987654321098765432109876543210987654321098765432109876543210987654321098765432109876543210987654321098765432109876543210987654321098765432109876543210987654321098765432109876543210987654321098765432109876543210987654321098765432109876543210987654321098765432109876543210987654321098765432109876543210987654321098765432109876543210987654321098765432109876543210987654321098765432109876543210987654321098765432109876543210987654321098765432109876543210"
jobs:
  thing:
    steps:
    - uses: owner/repo@master`,
			parsed: &parseTarget{
				Name: "98765432109876543210987654321098765432109876543210987654321098765432109876543210987654321098765432109876543210987654321098765432109876543210987654321098765432109876543210987654321098765432109876543210987654321098765432109876543210987654321098765432109876543210987654321098765432109876543210987654321098765432109876543210987654321098765432109876543210987654321098765432109876543210987654321098765432109876543210987654321098765432109876543210987654321098765432109876543210987654321098765432109876543210987654321...",
				On:   workflowOnValue{EventConfig{Event: "push"}},
				Jobs: map[string]job{
					"thing": {
						Steps: []parsedStep{
							{
								Uses: &model.UsesRepository{
									Repository: "owner/repo",
									Path:       "",
									Ref:        "master",
								},
							},
						},
					},
				},
			},
			path: "workflow.yml",
		},
	}

	for _, test := range tests {
		t.Run(test.desc, func(tt *testing.T) {
			ctx := context.Background()
			wfSrc := test.wfSrc
			if wfSrc == nil {
				wfSrc = NullWorkflowSource{}
			}
			file := types.ResolvedFile{Text: test.workflow, Path: test.path}
			r, err := ParseWithCalledWorkflows(ctx, file, test.featureFlags, wfSrc, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())
			assert.Equal(tt, test.error, err)

			if test.parsed == nil {
				assert.Nil(tt, r)
			} else {
				require.NotNil(tt, r)
				assert.Equal(tt, test.parsed.Name, r.Name)
				assert.ElementsMatch(tt, test.parsed.On, r.parsed.On)
				assert.Equal(tt, test.path, r.Path)
				assert.Equal(tt, test.parsed.Jobs, r.parsed.Jobs)
				assert.Equal(tt, file, r.File)

				if test.wfSrc != nil {
					calledWfs := r.CalledWorkflows
					assert.Equal(tt, len(test.parsed.Jobs), len(calledWfs))

					if test.testWfSrcParsedWf != nil {
						processWorkflows(tt, calledWfs, test.testWfSrcParsedWf)
					}
				}
			}
		})
	}
}

func TestPopulateJobsUsingWorkflows(t *testing.T) {
	tests := []struct {
		desc                      string
		parsed                    *parseTarget
		featureFlags              types.WorkflowFeatureFlags
		wfSrc                     WorkflowSource
		totalCalledWorkflowsCount int
		isEnterprise              bool
		enterpriseVersion         string
		callDepth                 int
		error                     error
	}{
		{
			desc: "jobs with no called workflows",
			parsed: &parseTarget{
				Jobs: map[string]job{
					"thing": {
						Steps: []parsedStep{
							{
								Uses: &model.UsesRepository{
									Repository: "owner/repo",
									Path:       "",
									Ref:        "master",
								},
							},
						},
					},
				},
			},
			totalCalledWorkflowsCount: 0,
			callDepth:                 0,
		},
		{
			desc:         "jobs with a called workflow",
			featureFlags: types.WorkflowFeatureFlags{},
			wfSrc: &StubWorkflowSource{
				SourceMap: map[string]WorkflowDetails{
					"actions/workflows/.github/workflows/node.yml@v1": {
						Content: `
on:
  workflow_call:
jobs:
  thing:
    steps:
    - uses: owner/repo@master`,
						RefType: "refs/tags/",
					},
				}},
			parsed: &parseTarget{
				Jobs: map[string]job{
					"build": {
						Uses: &usesWorkflow{Uses: model.WorkflowRef{
							Owner:   "actions",
							Repo:    "workflows",
							Path:    ".github/workflows/node.yml",
							Version: model.VersionRef{GitRef: pstring("v1")},
						}},
					},
					"thing": {
						Steps: []parsedStep{
							{
								Uses: &model.UsesRepository{
									Repository: "owner/repo",
									Path:       "",
									Ref:        "master",
								},
							},
						},
					},
				},
			},
			totalCalledWorkflowsCount: 1,
			callDepth:                 1,
			error:                     nil,
		},
		{
			desc:         "jobs with a local called workflow without version",
			featureFlags: types.WorkflowFeatureFlags{},
			wfSrc: &StubWorkflowSource{
				SourceMap: map[string]WorkflowDetails{
					"owner4/repo2/.github/workflows/node.yml@testSHAasdf123": {
						Content: `
on:
  workflow_call:
jobs:
  thing:
    steps:
    - uses: owner/repo@master`,
					},
				},
				CallerRepoID: "R_two",
				CallerRepoNWO: types.RepositoryFullName{
					Owner: "owner4",
					Name:  "repo2",
				},
				CallerRepoSHA: "testSHAasdf123",
			},
			parsed: &parseTarget{
				Jobs: map[string]job{
					"build": {
						Uses: &usesWorkflow{Uses: model.WorkflowRef{
							Owner:   ".",
							Repo:    ".",
							Path:    ".github/workflows/node.yml",
							Version: model.VersionRef{},
						}},
					},
				},
			},
			totalCalledWorkflowsCount: 1,
			callDepth:                 1,
			error:                     nil,
		},
		{
			desc:         "calling reusable workflow with depth level 3 (3 called workflows)",
			featureFlags: types.WorkflowFeatureFlags{},
			wfSrc: &StubWorkflowSource{
				SourceMap: map[string]WorkflowDetails{
					"o1/r1/.github/workflows/called1.yml@testSHAasdf123": {
						Content: `
on:
  workflow_call:
jobs:
  job:
    uses: ./.github/workflows/called2.yml`,
						Sha: "testSHAasdf123",
					},
					"o1/r1/.github/workflows/called2.yml@testSHAasdf123": {
						Content: `
on:
  workflow_call:
jobs:
  job:
    uses: ./.github/workflows/called3.yml`,
						Sha: "testSHAasdf123",
					},
					"o1/r1/.github/workflows/called3.yml@testSHAasdf123": {
						Content: `
on:
  workflow_call:
jobs:
  job:
    steps:
      - run: echo hello`,
						Sha: "testSHAasdf123",
					},
				},
				CallerRepoID: "R_kgAB", // [0, 1]
				CallerRepoNWO: types.RepositoryFullName{
					Owner: "o1",
					Name:  "r1",
				},
				CallerRepoSHA: "testSHAasdf123",
			},
			parsed: &parseTarget{
				Jobs: map[string]job{
					"build": {
						Uses: &usesWorkflow{Uses: model.WorkflowRef{
							Owner:   ".",
							Repo:    ".",
							Path:    ".github/workflows/called1.yml",
							Version: model.VersionRef{},
						}},
					},
				},
			},
			totalCalledWorkflowsCount: 3,
			callDepth:                 3,
			error:                     nil,
		},
		{
			desc:         "calling local reusable workflow",
			featureFlags: types.WorkflowFeatureFlags{},
			wfSrc: &StubWorkflowSource{
				SourceMap: map[string]WorkflowDetails{
					"owner1/repo1/.github/workflows/called1.yml@abcdef": {
						Content: `
on:
  workflow_call:
jobs:
  job:
    uses: owner2/repo2/.github/workflows/called2.yml@main`,
					},
					"owner2/repo2/.github/workflows/called2.yml@main": {
						Content: `
on:
  workflow_call:
jobs:
  job:
    uses: ./.github/workflows/called3.yml`,
						RefType: "refs/heads/",
					},
					"owner2/repo2/.github/workflows/called3.yml@main": {
						Content: `
on:
  workflow_call:
jobs:
  job:
    steps:
      - run: echo hello`,
						RefType: "refs/heads/",
					},
				},
				CallerRepoID: "R_kgAB", // [0, 1]
				CallerRepoNWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
				CallerRepoSHA: "abcdef",
			},
			parsed: &parseTarget{
				Jobs: map[string]job{
					"build": {
						Uses: &usesWorkflow{Uses: model.WorkflowRef{
							Owner:   ".",
							Repo:    ".",
							Path:    ".github/workflows/called1.yml",
							Version: model.VersionRef{},
						}},
					},
				},
			},
			totalCalledWorkflowsCount: 3,
			callDepth:                 3,
			error:                     nil,
		},
		{
			desc:         "calling reusable workflows exceeding the maximum depth level",
			featureFlags: types.WorkflowFeatureFlags{},
			wfSrc: &StubWorkflowSource{
				SourceMap: map[string]WorkflowDetails{
					"o1/r1/.github/workflows/called1.yml@testSHAasdf123": {
						Content: `
on:
  workflow_call:
jobs:
  job:
    uses: ./.github/workflows/called2.yml`,
					},
					"o1/r1/.github/workflows/called2.yml@testSHAasdf123": {
						Content: `
on:
  workflow_call:
jobs:
  job:
    uses: ./.github/workflows/called3.yml`,
					},
					"o1/r1/.github/workflows/called3.yml@testSHAasdf123": {
						Content: `
on:
  workflow_call:
jobs:
  job:
    uses: ./.github/workflows/called4.yml`,
					},
					"o1/r1/.github/workflows/called4.yml@testSHAasdf123": {
						Content: `
on:
  workflow_call:
jobs:
  job:
    steps:
      - run: echo hello`,
					},
				},
				CallerRepoID: "R_kgAB", // [0, 1]
				CallerRepoNWO: types.RepositoryFullName{
					Owner: "o1",
					Name:  "r1",
				},
				CallerRepoSHA: "testSHAasdf123",
			},
			parsed: &parseTarget{
				Jobs: map[string]job{
					"build": {
						Uses: &usesWorkflow{Uses: model.WorkflowRef{
							Owner:   ".",
							Repo:    ".",
							Path:    ".github/workflows/called1.yml",
							Version: model.VersionRef{},
						}},
					},
				},
			},
			totalCalledWorkflowsCount: 1,
			error: newCalledWorkflowParseErrorWithLine(0, CalledWorkflowParseError{
				chain:   []string{`"./.github/workflows/called2.yml"`, `"./.github/workflows/called3.yml"`},
				message: "job \"job\" calls workflow \"./.github/workflows/called4.yml\", but doing so would exceed the limit on called workflow depth of 3",
			}, `"./.github/workflows/called1.yml"`),
		},
		{
			desc:         "a job that uses another workflow, but it isnt callable",
			featureFlags: types.WorkflowFeatureFlags{},
			wfSrc: &StubWorkflowSource{
				SourceMap: map[string]WorkflowDetails{
					"actions/workflows/.github/workflows/node.yml@v1": {
						Content: `
on:
  push:
jobs:
  thing:
    steps:
    - uses: owner/repo@master`,
						RefType: "refs/tags/",
					}}},
			parsed: &parseTarget{
				Jobs: map[string]job{
					"build": {
						Uses: &usesWorkflow{Uses: model.WorkflowRef{
							Owner:   "actions",
							Repo:    "workflows",
							Path:    ".github/workflows/node.yml",
							Version: model.VersionRef{GitRef: pstring("v1")},
						}},
					},
				},
			},
			totalCalledWorkflowsCount: 1,
			error: newCalledWorkflowParseErrorWithLine(0, ParseError{message: "workflow is not reusable as it is missing a `on.workflow_call` trigger"},
				`"actions/workflows/.github/workflows/node.yml@v1" (source tag with sha:v1)`),
		},
		{
			desc:         "jobs with a called workflow in a non-existing repo in dotcom",
			featureFlags: types.WorkflowFeatureFlags{},
			parsed: &parseTarget{
				Jobs: map[string]job{
					"build": {
						Uses: &usesWorkflow{Uses: model.WorkflowRef{
							Owner:   "actions",
							Repo:    "workflows",
							Path:    ".github/workflows/node.yml",
							Version: model.VersionRef{GitRef: pstring("v1")},
						}},
					},
					"thing": {
						Steps: []parsedStep{
							{
								Uses: &model.UsesRepository{
									Repository: "owner/repo",
									Path:       "",
									Ref:        "master",
								},
							},
						},
					},
				},
			},
			totalCalledWorkflowsCount: 1,
			isEnterprise:              false,
			error: newCalledWorkflowParseErrorWithLine(0, ParseError{message: "workflow was not found. See https://docs.github.com/actions/learn-github-actions/reusing-workflows#access-to-reusable-workflows for more information."},
				`"actions/workflows/.github/workflows/node.yml@v1"`),
		},
		{
			desc:         "jobs with a called workflow in a non-existing repo in GHES",
			featureFlags: types.WorkflowFeatureFlags{},
			parsed: &parseTarget{
				Jobs: map[string]job{
					"build": {
						Uses: &usesWorkflow{Uses: model.WorkflowRef{
							Owner:   "actions",
							Repo:    "workflows",
							Path:    ".github/workflows/node.yml",
							Version: model.VersionRef{GitRef: pstring("v1")},
						}},
					},
					"thing": {
						Steps: []parsedStep{
							{
								Uses: &model.UsesRepository{
									Repository: "owner/repo",
									Path:       "",
									Ref:        "master",
								},
							},
						},
					},
				},
			},
			totalCalledWorkflowsCount: 1,
			isEnterprise:              true,
			enterpriseVersion:         "3.4",
			error: newCalledWorkflowParseErrorWithLine(0, ParseError{message: "workflow was not found. See https://docs.github.com/enterprise-server@3.4/actions/learn-github-actions/reusing-workflows#access-to-reusable-workflows for more information."},
				`"actions/workflows/.github/workflows/node.yml@v1"`),
		},
	}

	for _, test := range tests {
		t.Run(test.desc, func(tt *testing.T) {
			ctx := context.Background()
			wfSrc := test.wfSrc
			if wfSrc == nil {
				wfSrc = NullWorkflowSource{}
			}
			_, totalCount, callDepth, err := PopulateJobsUsingWorkflows(ctx, test.parsed.Jobs, test.featureFlags, wfSrc, 1, launchutils.NewRuntimeHelper(test.isEnterprise, test.enterpriseVersion), 0, observability.NewNullObservability())
			assert.Equal(tt, test.error, err)
			if err == nil {
				assert.Equal(tt, test.callDepth, callDepth)
			}
			assert.Equal(tt, test.totalCalledWorkflowsCount, totalCount)
		})
	}
}

func TestPopulateJobsUsingWorkflows_SameWorkflowMaxLimitNotReached(t *testing.T) {
	ctx := context.Background()
	featureFlags := types.WorkflowFeatureFlags{}
	wfSrc := &StubWorkflowSource{
		SourceMap: map[string]WorkflowDetails{
			"actions/workflows/.github/workflows/node.yml@v1": {
				Content: `
on:
  workflow_call:
jobs:
  called:
    steps:
    - uses: owner/repo@master`,
				RefType: "refs/tags/",
			},
		}}
	jobs := map[string]job{}

	for id := 1; id <= 21; id++ {
		jobId := fmt.Sprintf("job%d", id)
		jobs[jobId] = job{
			Uses: &usesWorkflow{Uses: model.WorkflowRef{
				Owner:   "actions",
				Repo:    "workflows",
				Path:    ".github/workflows/node.yml",
				Version: model.VersionRef{GitRef: pstring("v1")},
			}},
		}
	}
	calledWfMap, calledWfCount, callDepth, err := PopulateJobsUsingWorkflows(ctx, jobs, featureFlags, wfSrc, 1, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())
	assert.Nil(t, err)
	assert.Equal(t, 1, calledWfCount)
	assert.Equal(t, 1, callDepth)
	assert.Equal(t, 21, len(calledWfMap))
}

func TestPopulateJobsUsingWorkflows_FetchPerUniqueReferencedWorkflow(t *testing.T) {
	ctx := context.Background()
	featureFlags := types.WorkflowFeatureFlags{}
	wfSrc := &StubWorkflowSource{
		SourceMap: map[string]WorkflowDetails{
			"actions/workflows/.github/workflows/node.yml@v1": {
				Content: `
on:
  workflow_call:
jobs:
  called:
    steps:
    - uses: owner/repo@master`,
				RefType: "refs/tags/",
			},
		}}
	jobs := map[string]job{}

	// Job1, job2 referring same workflow with v1
	for id := 1; id <= 2; id++ {
		jobId := fmt.Sprintf("job%d", id)
		jobs[jobId] = job{
			Uses: &usesWorkflow{Uses: model.WorkflowRef{
				Owner:   "actions",
				Repo:    "workflows",
				Path:    ".github/workflows/node.yml",
				Version: model.VersionRef{GitRef: pstring("v1")},
			}},
		}
	}
	calledWfMap, calledWfCount, callDepth, err := PopulateJobsUsingWorkflows(ctx, jobs, featureFlags, wfSrc, 1, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())
	assert.Nil(t, err)
	assert.Equal(t, 1, calledWfCount)
	assert.Equal(t, 1, callDepth)
	// asserts both jobs pointing to the same workflow instance that is fetched only once
	assert.Equal(t, calledWfMap["job1"], calledWfMap["job2"])
}

func TestPopulateJobsUsingWorkflows_ConcurrentWorkflowSourceAccess(t *testing.T) {
	ctx := context.Background()
	featureFlags := types.WorkflowFeatureFlags{}
	wfSrc := &StubWorkflowSource{
		SourceMap: map[string]WorkflowDetails{
			"actions1/workflows1/.github/workflows/node1.yml@v1": {
				Content: `
on:
  workflow_call:
jobs:
  calling:
    uses: ./.github/workflows/called1.yml`,
				RefType: "refs/tags/",
				Sha:     "asdf1234",
			},
			"actions1/workflows1/.github/workflows/called1.yml@asdf1234": {
				Content: `
on:
  workflow_call:
jobs:
  called1:
    steps:
      - uses: owner/repo@master`,
			},
			"actions2/workflows2/.github/workflows/node2.yml@v1": {
				Content: `
on:
  workflow_call:
jobs:
  calling:
    uses: ./.github/workflows/called2.yml`,
				RefType: "refs/tags/",
				Sha:     "asdf1234",
			},
			"actions2/workflows2/.github/workflows/called2.yml@asdf1234": {
				Content: `
on:
  workflow_call:
jobs:
  called2:
    steps:
      - uses: owner/repo@master`,
			},
		},
		CallerRepoID: "R_zero",
		CallerRepoNWO: types.RepositoryFullName{
			Owner: "actions0",
			Name:  "workflows0",
		},
		CallerRepoRef: "v1",
		CallerRepoSHA: "asdf1234",
	}
	jobs := map[string]job{}

	for id := 1; id <= 2; id++ {
		jobId := fmt.Sprintf("job%d", id)
		jobs[jobId] = job{
			Uses: &usesWorkflow{Uses: model.WorkflowRef{
				Owner:   fmt.Sprintf("actions%d", id),
				Repo:    fmt.Sprintf("workflows%d", id),
				Path:    fmt.Sprintf(".github/workflows/node%d.yml", id),
				Version: model.VersionRef{GitRef: pstring("v1")},
			}},
		}
	}
	_, calledWfCount, callDepth, err := PopulateJobsUsingWorkflows(ctx, jobs, featureFlags, wfSrc, 1, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())
	assert.Nil(t, err)
	assert.Equal(t, 2, callDepth)
	assert.Equal(t, 4, calledWfCount)
}

func TestPopulateJobsUsingWorkflows_InternalError(t *testing.T) {
	ctx := context.Background()
	featureFlags := types.WorkflowFeatureFlags{}
	wfSrc := ErrorWorkflowSource{
		Error: launcherror.NewInternalError(errors.New("internal error")),
	}
	jobs := map[string]job{
		"build": {
			Uses: &usesWorkflow{Uses: model.WorkflowRef{
				Owner:   "actions",
				Repo:    "workflows",
				Path:    ".github/workflows/node.yml",
				Version: model.VersionRef{GitRef: pstring("v1")},
			}},
		},
		"thing": {
			Steps: []parsedStep{
				{
					Uses: &model.UsesRepository{
						Repository: "owner/repo",
						Path:       "",
						Ref:        "master",
					},
				},
			},
		},
	}

	_, _, _, err := PopulateJobsUsingWorkflows(ctx, jobs, featureFlags, wfSrc, 1, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())
	assert.Error(t, err)
	assert.True(t, launcherror.IsInternalError(err))
}

func TestWorkflowEventNoRecursion(t *testing.T) {
	ctx := context.Background()
	test := struct {
		desc     string
		workflow string
		path     string
		error    error
	}{
		desc: "error when workflow_run listens to itself",
		workflow: `name: Create WordPress Post
on:
  workflow_run:
    types: [completed]
    workflows: [Create WordPress Post, Another Workflow]
jobs:
  a:
    steps:
    - run: "hi"`,
		error: newParseError("Workflow 'Create WordPress Post' cannot listen to itself."),
	}

	r, err := Parse(ctx, types.ResolvedFile{Text: test.workflow, Path: test.path}, types.WorkflowFeatureFlags{}, NullWorkflowSource{}, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())
	assert.Equal(t, test.error, err)
	assert.Nil(t, r)
}

func TestManualEvent(t *testing.T) {
	ctx := context.Background()
	parsed, err := Parse(ctx, types.ResolvedFile{Text: `on: workflow_dispatch
jobs:
  a:
    steps:
    - run: "hi"`, Path: "eg.yml"}, types.WorkflowFeatureFlags{}, NullWorkflowSource{}, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())
	require.NoError(t, err)

	_, ok := parsed.OnForEvent("workflow_dispatch")
	require.True(t, ok, "missing trigger")
}

func TestDynamicEvent(t *testing.T) {
	ctx := context.Background()
	parsed, err := Parse(ctx, types.ResolvedFile{Text: `on: push
jobs:
  a:
    steps:
    - run: "hi"`, Path: "eg.yml"}, types.WorkflowFeatureFlags{}, NullWorkflowSource{}, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())
	require.NoError(t, err)

	_, ok := parsed.OnForEvent("dynamic")
	require.True(t, ok, "missing trigger")
}

func TestIgnore(t *testing.T) {
	ctx := context.Background()
	parsed, err := Parse(ctx, types.ResolvedFile{Text: `on:
  push:
    paths-ignore: ["p/*"]
    tags-ignore: ["t/*"]
    branches-ignore: "b/*"

jobs: { a: { steps: [{run: "hi"}] }}
    `, Path: "eg.yml"}, types.WorkflowFeatureFlags{}, NullWorkflowSource{}, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())
	require.NoError(t, err)

	on, ok := parsed.OnForEvent("push")
	require.True(t, ok, "missing trigger")
	assert.Equal(t, &stringList{"p/*"}, on.PathsIgnore)
	assert.Equal(t, &stringList{"t/*"}, on.TagsIgnore)
	assert.Equal(t, &stringList{"b/*"}, on.BranchesIgnore)
}

func TestSelfHosted(t *testing.T) {
	ctx := context.Background()
	examples := []struct {
		input    string
		expected *runsOnConfig
	}{
		{`ubuntu-latest`, &runsOnConfig{Labels: []string{"ubuntu-latest"}}},
		{`self-hosted`, &runsOnConfig{Labels: []string{"self-hosted"}}},
		{`[self-hosted, linux, ARM32]`, &runsOnConfig{Labels: []string{"self-hosted", "linux", "ARM32"}}},
		{`[self-hosted, "!macos", "!x86"]`, &runsOnConfig{Labels: []string{"self-hosted", "!macos", "!x86"}}},
		{``, nil},
		{`
      group: test`, &runsOnConfig{Labels: nil}},
		{`
      labels: ubuntu-latest`, &runsOnConfig{Labels: nil}},
		{`
      group: test
      labels: ubuntu-latest`, &runsOnConfig{Labels: nil}},
	}

	for _, eg := range examples {
		wff := fmt.Sprintf(`on: push
jobs:
  a:
    steps: [{run: "ls"}]
    runs-on: %s`, eg.input)
		wf, err := Parse(ctx, types.ResolvedFile{Text: wff, Path: "foo.yml"}, types.WorkflowFeatureFlags{}, NullWorkflowSource{}, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())
		require.NoError(t, err)
		require.Equal(t, eg.expected, wf.parsed.Jobs["a"].RunsOn, "Mismatch in runs-on values for example: %s", eg.input)
	}
}

func TestIncludesLineNumbersOnParseErrors(t *testing.T) {
	ctx := context.Background()
	_, err := Parse(ctx, types.ResolvedFile{Text: "\n\n\n<foo>", Path: "foo.yml"}, types.WorkflowFeatureFlags{}, NullWorkflowSource{}, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())
	assert.Equal(t, err.Error(), "You have an error in your yaml syntax on line 4")
}

func TestRefusesToParseLargeFiles(t *testing.T) {
	ctx := context.Background()
	bigFile := make([]byte, 10*1000*1000)
	_, err := Parse(ctx, types.ResolvedFile{Text: string(bigFile), Path: "foo.yml"}, types.WorkflowFeatureFlags{}, NullWorkflowSource{}, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())
	assert.EqualError(t, err, "Workflow files can be 5 megabytes at largest")
}

func TestRefusesOverlyLargeFilePaths(t *testing.T) {
	ctx := context.Background()
	longName := strings.Repeat("❤️", 2048)
	_, err := Parse(ctx, types.ResolvedFile{Text: "on: push", Path: longName}, types.WorkflowFeatureFlags{}, NullWorkflowSource{}, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())
	assert.EqualError(t, err, "Workflow files paths can be at most 255 unicode characters")
}

func TestPullRequestTarget(t *testing.T) {
	ctx := context.Background()
	parsed, err := Parse(ctx, types.ResolvedFile{Text: `on: pull_request_target
jobs:
  a:
    steps:
    - run: "hi"`, Path: "eg.yml"}, types.WorkflowFeatureFlags{}, NullWorkflowSource{}, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())
	require.NoError(t, err)

	_, ok := parsed.OnForEvent("pull_request_target")
	require.True(t, ok, "missing trigger")
}

func TestFind(t *testing.T) {
	ctx := context.Background()
	path := ".github/workflow/some-file.yml"
	parsed, err := ParseWorkflows(ctx, []types.ResolvedFile{
		{
			Path: path,
			Text: `on: push
jobs:
  one:
    steps: ["echo hi"]`,
			SHA: "aabbcc",
		},
	}, types.WorkflowFeatureFlags{}, NullWorkflowSource{}, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())
	require.NoError(t, err)

	workflowFileReference := types.WorkflowFileReference{
		Path: path,
	}

	// Happy path
	res, err := parsed.Find(workflowFileReference)
	require.NoError(t, err)
	assert.Equal(t, parsed.PathToWorkflow[workflowFileReference], *res)

	// Failure case
	badWorkflowFileReference := types.WorkflowFileReference{
		Path: "bad-path",
	}
	res, err = parsed.Find(badWorkflowFileReference)
	assert.Nil(t, res)
	assert.Error(t, err)
}

func TestLoggingAndReportingInFetchAndParseCalledWorkflow(t *testing.T) {

	// Fixtures for this test
	featureFlags := types.WorkflowFeatureFlags{}
	wfRefStub := model.WorkflowRef{}

	// List test scenarios
	tests := []struct {
		// Test description
		desc string
		// Workflow source
		wfSrc WorkflowSource
		// Prep Context for test case
		prepareCtx func() context.Context
		// Sentry report expected
		sentryReportExpected bool
	}{
		{
			desc: "No Sentry error reported on context cancel due to parsing error in referenced workflow but logged",
			wfSrc: ErrorWorkflowSource{
				Error: twirp.InternalError("context canceled"),
			},
			prepareCtx: func() context.Context {
				ctx := context.Background()
				ctx, cancel := context.WithCancel(ctx)
				cancel()
				return ctx
			},
			sentryReportExpected: false,
		},
		{
			desc: "Sentry error reported due to service error",
			wfSrc: ErrorWorkflowSource{
				Error: twirp.NewError(twirp.PermissionDenied, "permission denied"),
			},
			prepareCtx:           context.Background,
			sentryReportExpected: true,
		},
		{
			desc: "Sentry error not reported due to internal error", // internal error will be reported later in CreateErrorCheckSuite
			wfSrc: ErrorWorkflowSource{
				Error: launcherror.NewInternalError(errors.New("internal error")),
			},
			prepareCtx:           context.Background,
			sentryReportExpected: false,
		},
		{
			desc: "Sentry error reported due to context timeout",
			wfSrc: ErrorWorkflowSource{
				Error: twirp.InternalError("context timed out"),
			},
			prepareCtx: func() context.Context {
				ctx := context.Background()
				ctx, _ = context.WithTimeout(ctx, time.Nanosecond)
				<-ctx.Done()
				return ctx
			},
			sentryReportExpected: true,
		},
		{
			desc: "No errors reported on workflow file not found but logged",
			wfSrc: ErrorWorkflowSource{
				Error: twirp.NewError(twirp.NotFound, "not found"),
			},
			prepareCtx:           context.Background,
			sentryReportExpected: false,
		},
		{
			desc:                 "No errors reported when GetWorkflowFile succeeds",
			wfSrc:                &StubWorkflowSource{},
			prepareCtx:           context.Background,
			sentryReportExpected: false,
		},
	}

	// Executing tests
	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			// Prepare test case
			ctx := tt.prepareCtx()
			obs, loggerMock, _ := observability.NewMockedObservability()
			loggerMock.On("Log", mock.Anything, mock.Anything).Return()
			loggerMock.On("Report", mock.Anything, mock.Anything).Return()
			// Execute test case
			_, _, _, _, _, _ = fetchAndParseCalledWorkflow(
				ctx,
				wfRefStub,
				featureFlags,
				tt.wfSrc,
				0,
				1,
				launchutils.NewRuntimeHelper(false, "latest"),
				0,
				obs,
				&RepositoryMetadata{})

			// Asserting log message content and if it was reported to sentry
			if tt.sentryReportExpected {
				loggerMock.AssertCalled(t, "Report", mock.Anything, mock.Anything)
			} else {
				loggerMock.AssertNotCalled(t, "Report")
			}
		})
	}
}

func TestTrimName(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{
			name:     "short name",
			input:    "My Workflow",
			expected: "My Workflow",
		},
		{
			name:     "exact length name",
			input:    strings.Repeat("a", 512),
			expected: strings.Repeat("a", 512),
		},
		{
			name:     "long name",
			input:    strings.Repeat("a", 513),
			expected: strings.Repeat("a", 509) + trimmedTextMarker,
		},
		{
			name:     "long utf-8 string",
			input:    strings.Repeat("\U0001F600", 129),
			expected: strings.Repeat("\U0001F600", 127) + trimmedTextMarker,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := TrimName(tt.input)
			require.Equal(t, tt.expected, result)
			require.LessOrEqual(t, len(result), 512)
			require.True(t, utf8.ValidString(result))
		})
	}
}

func TestIsUsingHardCodedHostedRunnerLabels(t *testing.T) {
	tests := []struct {
		name     string
		workflow *Workflow
		expected bool
	}{
		{
			name: "All labels valid, no called workflows",
			workflow: &Workflow{
				parsed: parseTarget{
					Jobs: jobMap{
						"job1": {RunsOn: &runsOnConfig{Labels: []string{"ubuntu-latest"}}},
						"job2": {RunsOn: &runsOnConfig{Labels: []string{"windows-latest"}}},
					},
				},
			},
			expected: true,
		},
		{
			name: "All labels valid, with called workflows",
			workflow: &Workflow{
				parsed: parseTarget{
					Jobs: jobMap{
						"job1": {},
					},
				},
				CalledWorkflows: map[string]CalledWorkflow{
					"workflow1": {
						Workflow: Workflow{
							parsed: parseTarget{
								Jobs: jobMap{
									"job1": {RunsOn: &runsOnConfig{Labels: []string{"macos-latest"}}},
								},
							},
						},
					},
				},
			},
			expected: true,
		},
		{
			name: "All labels valid, with called workflows nested",
			workflow: &Workflow{
				parsed: parseTarget{
					Jobs: jobMap{
						"job1": {},
					},
				},
				CalledWorkflows: map[string]CalledWorkflow{
					"workflow1": {
						Workflow: Workflow{
							parsed: parseTarget{
								Jobs: jobMap{
									"job1": {},
								},
							},
							CalledWorkflows: map[string]CalledWorkflow{
								"workflow2": {
									Workflow: Workflow{
										CalledWorkflows: map[string]CalledWorkflow{
											"workflow3": {
												Workflow: Workflow{
													parsed: parseTarget{
														Jobs: jobMap{
															"job1": {RunsOn: &runsOnConfig{Labels: []string{"macos-latest"}}},
														},
													},
												},
											},
										},
									},
								},
							},
						},
					},
				},
			},
			expected: true,
		},
		{
			name: "Uses self-hosted, with called workflows nested and combination of normal jobs",
			workflow: &Workflow{
				parsed: parseTarget{
					Jobs: jobMap{
						// normal job
						"job1": {RunsOn: &runsOnConfig{Labels: []string{"ubuntu-latest"}}},
						// job using reusable workflow
						"job2": {Uses: &usesWorkflow{Uses: model.WorkflowRef{}}},
					},
				},
				CalledWorkflows: map[string]CalledWorkflow{
					// assume job2 is using this workflow
					"workflow1": {
						Workflow: Workflow{
							parsed: parseTarget{
								Jobs: jobMap{
									"job1": {RunsOn: &runsOnConfig{Labels: []string{"self-hosted"}}},
								},
							},
							CalledWorkflows: map[string]CalledWorkflow{
								"workflow2": {
									Workflow: Workflow{
										CalledWorkflows: map[string]CalledWorkflow{
											"workflow3": {
												Workflow: Workflow{
													parsed: parseTarget{
														Jobs: jobMap{
															"job1": {RunsOn: &runsOnConfig{Labels: []string{"macos-latest"}}},
														},
													},
												},
											},
										},
									},
								},
							},
						},
					},
				},
			},
			expected: false,
		},
		{
			name: "All labels valid, with called workflows nested and combination of normal jobs",
			workflow: &Workflow{
				parsed: parseTarget{
					Jobs: jobMap{
						// normal job
						"job1": {RunsOn: &runsOnConfig{Labels: []string{"ubuntu-latest"}}},
						// job using reusable workflow
						"job2": {Uses: &usesWorkflow{Uses: model.WorkflowRef{}}},
					},
				},
				CalledWorkflows: map[string]CalledWorkflow{
					// assume job2 is using this workflow
					"workflow1": {
						Workflow: Workflow{
							parsed: parseTarget{
								Jobs: jobMap{
									"job1": {RunsOn: &runsOnConfig{Labels: []string{"ubuntu-latest"}}},
									"job2": {RunsOn: &runsOnConfig{Labels: []string{"windows-latest"}}},
								},
							},
							CalledWorkflows: map[string]CalledWorkflow{
								"workflow2": {
									Workflow: Workflow{
										CalledWorkflows: map[string]CalledWorkflow{
											"workflow3": {
												Workflow: Workflow{
													parsed: parseTarget{
														Jobs: jobMap{
															"job1": {RunsOn: &runsOnConfig{Labels: []string{"macos-latest"}}},
														},
													},
												},
											},
										},
									},
								},
							},
						},
					},
				},
			},
			expected: true,
		},
		{
			name: "With called workflows, empty parsed",
			workflow: &Workflow{
				parsed: parseTarget{
					Jobs: jobMap{
						"job1": {},
					},
				},
				CalledWorkflows: map[string]CalledWorkflow{
					"workflow1": {
						Workflow: Workflow{
							parsed: parseTarget{},
						},
					},
				},
			},
			expected: false,
		},
		{
			name: "Self-hosted label in main workflow",
			workflow: &Workflow{
				parsed: parseTarget{
					Jobs: jobMap{
						"job1": {RunsOn: &runsOnConfig{Labels: []string{"self-hosted"}}},
					},
				},
			},
			expected: false,
		},
		{
			name: "Self-hosted label in called workflow",
			workflow: &Workflow{
				parsed: parseTarget{
					Jobs: jobMap{
						"job1": {RunsOn: &runsOnConfig{Labels: []string{"ubuntu-latest"}}},
					},
				},
				CalledWorkflows: map[string]CalledWorkflow{
					"workflow1": {
						Workflow: Workflow{
							parsed: parseTarget{
								Jobs: jobMap{
									"job2": {RunsOn: &runsOnConfig{Labels: []string{"self-hosted"}}},
								},
							},
						},
					},
				},
			},
			expected: false,
		},
		{
			name:     "Nil workflow",
			workflow: nil,
			expected: false,
		},
		{
			name: "Nil jobs map in workflow",
			workflow: &Workflow{
				parsed: parseTarget{
					Jobs: nil,
				},
			},
			expected: false,
		},
		{
			name: "Empty jobs map in workflow",
			workflow: &Workflow{
				parsed: parseTarget{
					Jobs: jobMap{},
				},
			},
			expected: false,
		},
		{
			name: "Empty RunsOn in job",
			workflow: &Workflow{
				parsed: parseTarget{
					Jobs: jobMap{
						"job1": {RunsOn: &runsOnConfig{}},
					},
				},
			},
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := IsUsingHardCodedHostedRunnerLabels(tt.workflow)
			if result != tt.expected {
				t.Errorf("TestIsUsingHardCodedHostedRunnerLabels(%s) got %v, want %v", tt.name, result, tt.expected)
			}
		})
	}
}

func pstring(s string) *string { return &s }

func processWorkflows(tt *testing.T, calledWfs map[string]CalledWorkflow, testWfSrcParsedWf func(*testing.T, job)) {
	for _, calledWf := range calledWfs {
		// Check if this workflow calls other workflows and recursively process them if true
		if len(calledWf.Workflow.CalledWorkflows) > 0 {
			processWorkflows(tt, calledWf.Workflow.CalledWorkflows, testWfSrcParsedWf)
		} else {
			// This is a leaf workflow, process its jobs with the given function
			jobsMap := calledWf.Workflow.parsed.Jobs
			for _, job := range jobsMap {
				testWfSrcParsedWf(tt, job)
			}
		}
	}
}
