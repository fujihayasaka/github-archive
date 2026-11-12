package launcher

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"html/template"
	"regexp"
	"strings"
	"testing"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"gopkg.in/yaml.v3"
)

const workflowPrefix = `
name: "Test"
on:
  workflow_dispatch:
permissions: {}
jobs:
  copilot-setup-steps:
`

const workflowPrefixWithTopLevelPermissions = `
name: "Test"
on:
  workflow_dispatch:
permissions:
  contents: write
jobs:
  copilot-setup-steps:
`

const workflowUsesOnLine = `
    uses: acmecorp/reusable-workflow@v4
`

const workflowRunsOnLine = `
    runs-on: custom-runner
`

const workflowRunsOnObject = `
    runs-on:
      label: custom-runner
      group: some-group-goes-here
`

const workflowPermissions = `
    permissions:
      contents: read
      id-token: write # for setup-goproxy
`

const workflowPermissionsReadAll = `
    permissions: read-all
`

const workflowPermissionsWriteAll = `
    permissions: write-all
`

const workflowPermissionsNone = `
    permissions: {}
`

const workflowMisc = `
    timeout-minutes: 30
    container:
      image: node:18
      env:
        NODE_ENV: development
      ports:
        - 80
      volumes:
        - my_docker_volume:/volume_mount
      options: --cpus 1
      credentials:
        username: ${{ github.actor }}
        password: ${{ secrets.github_token }}
    services:
      nginx:
        image: nginx
        ports:
          - 8080:80
      redis:
        image: redis
        ports:
          - 6379/tcp
    snapshot:
      image-name: ros2-linux-image
`

const workflowSteps = `
    steps:
    - name: Output contents
      run: |
        echo "Hello world!"
        echo "I want to use GITHUB_COPILOT_API_TOKEN"
        env
      env:
        # Should _not_ be filtered out
        A: ${{ secrets.GITHUB_TOKEN }}
        B: ${{ vars.COPILOT_AGENT_FIREWALL_ENABLED }}
        C: ${{ vars.COPILOT_AGENT_FIREWALL_ALLOW_LIST}},${{ github.server_url }},${{ vars.COPILOT_AGENT_FIREWALL_ALLOW_LIST_ADDITIONS }}
        D1: ${{ vars.COPILOT_AGENT_DEBUG }}
        D2: ${{ env.COPILOT_AGENT_DEBUG }}
        # Should be filtered out
        E: ${{ secrets.GITHUB_COPILOT_API_TOKEN }}
        F: ${{ secrets.GITHUB_COPILOT_INTEGRATION_ID }}
        G: ${{ secrets.COPILOT_INTEGRATION_ID_OVERRIDE }}
        H: ${{ secrets.GITHUB_COPILOT_ACTION_DOWNLOAD_URL }}
        I1: ${{ secrets.CAPI_HMAC_KEY_OVERRIDE }}
        I2: ${{ env.CAPI_HMAC_KEY_OVERRIDE }}
        I3: ${{ vars.CAPI_HMAC_KEY_OVERRIDE }}
        I4: ${{ CAPI_HMAC_KEY_OVERRIDE }}
        I5A: ${{ secrets['CAPI_HMAC_KEY_OVERRIDE'] }}
        I5B: ${{ secrets["CAPI_HMAC_KEY_OVERRIDE"] }}
        I5C: ${{ secrets[CAPI_HMAC_KEY_OVERRIDE] }}
        I5D: ${{ secrets[ 'CAPI_HMAC_KEY_OVERRIDE' ] }}
        I5E: ${{ secrets ['CAPI_HMAC_KEY_OVERRIDE'] }}
        I5F: ${{ secrets [ 'CAPI_HMAC_KEY_OVERRIDE' ] }}
        I5G: ${{ vars['CAPI_HMAC_KEY_OVERRIDE'] }}
        I5H: ${{ env['CAPI_HMAC_KEY_OVERRIDE'] }}
        J1: ${{ toJson(secrets) }}
        J2: ${{ toJson( secrets ) }}
        J3: ${{ toJson (secrets) }}
        J4: ${{ toJson ( secrets ) }}
        J5: ${{ toJson(vars) }}
        J6: ${{ toJson(env) }}
        K: ${{ secrets.GITHUB_COPILOT_GIT_TOKEN }}
        L1: ${{ secrets.github_copilot_git_token }}
        L2: ${{ secrets['capi_hmac_key_override'] }}
        L3: ${{ SECRETS.github_copilot_git_token }}
        M1: ${{ secrets.GITHUB_COPILOT_SOME_NEW_THING }}
        M2: ${{ secrets['GITHUB_COPILOT_SOME_NEW_THING'] }}
        N1: ${{ vars.COPILOT_MCP_ENABLED }}
        N2: ${{ vars['COPILOT_MCP_ENABLED'] }}
        N3: ${{ vars.COPILOT_MCP_SOME_ARG }}
        N4: ${{ vars['COPILOT_MCP_SOME_ARG'] }}
`

var checkoutCommitCountStepVariations = []string{
	`
    steps:
    - uses: actions/checkout@v4
`,
	`
    steps:
    - uses: actions/checkout@v4
      with:
        clean: true
`,
	`
    steps:
    - uses: actions/checkout@v4
      with:
        persist-credentials: true
`,
	`
    steps:
    - uses: actions/checkout@v4
      with:
        fetch-depth: 0
`,
	`
    steps:
    - uses: actions/checkout@v4
      with:
        fetch-depth: 0
        repository: ${{ github.repository }}
`,
	`
    steps:
    - uses: actions/checkout@v4
      with:
        repository: ${{ github.repository }}
`,
	`
    steps:
    - uses: actions/checkout@v4
      with:
        repository: ${{ GITHUB.REPOSITORY }}
`,
	`
    steps:
    - uses: actions/checkout@v4
      with:
        repository: ${{ github['repository'] }}
`,
	`
    steps:
    - uses: actions/checkout@v4
      with:
        repository: ${{ github["repository"] }}
`,
	`
    steps:
    - uses: actions/checkout@v4
      with:
        repository: ${{ github[          "repository"            ] }}
`,
	`
    steps:
    - uses: actions/checkout@v4
      with:
        repository: ${{             github["repository"]             }}
`,
	`
    steps:
    - uses: actions/checkout@v4
      with:
        repository: legit/repo
`,

	`
    steps:
    - uses: actions/checkout@v4
      with:
        repository: "legit/repo"
`,
	`
    steps:
    - uses: actions/checkout@v4
      with:
        repository: 'legit/repo'
`,
	`
    steps:
    - uses: actions/checkout@v4
      with:
        repository:            legit/repo
`,

	`
    steps:
    - uses: actions/checkout@v4
      with:
        ref: ${{ github.ref }}
`,
	`
    steps:
    - uses: actions/checkout@v4
      with:
        ref: ${{ github["ref"] }}
`,
	`
    steps:
    - uses: actions/checkout@v4
      with:
        ref: ${{ github['ref'] }}
`,
	`
    steps:
    - uses: actions/checkout@v4
      with:
        ref: ${{ github[          "ref"          ] }}
`,
	`
    steps:
    - uses: actions/checkout@v4
      with:
        ref: ${{           github["ref"]          }}
`,
	`
    steps:
    - uses: actions/checkout@v4
      with:
        ref: ${{ github.ref_name }}
`,
	`
    steps:
    - uses: actions/checkout@v4
      with:
        ref: ${{ github["ref_name"] }}
`,
	`
    steps:
    - uses: actions/checkout@v4
      with:
        ref: ${{ github.head_ref }}
`,
	`
    steps:
    - uses: actions/checkout@v4
      with:
        ref: ${{ github["head_ref"] }}
`,
	`
    steps:
    - uses: actions/checkout@v4
      with:
        ref: legit-branch
`,
	`
    steps:
    - uses: actions/checkout@v4
      with:
        ref: "legit-branch"
`,
	`
    steps:
    - uses: actions/checkout@v4
      with:
        ref: 'legit-branch'
`,

	`
    steps:
    - uses: actions/checkout@v4
      with:
        ref:               "legit-branch"
`,
}

var checkoutNoCommitCountStepVariations = []string{
	`
    steps:
    - uses: actions/checkout@v4
      with:
        ref: main
`,
	`
    steps:
    - uses: actions/checkout@v4
      with:
        repository: some/repo
`,
	`
    steps:
    - uses: actions/checkout@v4
      with:
        repository: some/repo
        ref: main
`,
	`
    steps:
    - uses: actions/checkout@v4
      with:
        repository: some/repo
        fetch-depth: 0
`,
	`
    steps:
    - uses: actions/checkout@v4
      with:
        repository: some/repo
        persist-credentials: true
`,
}

var checkoutOtherPropertiesUnaffected = `
    steps:
    - uses: actions/checkout@v4
      with:
        persist-credentials: true
        fetch-depth: 0
        token: sleep-token
        ssh-key: dont-ssh-me
        ssh-known-hosts: silent-host
        ssh-strict: false
        path: /some/path
        clean: false
        filter: is-a-band
        sparse-checkout: some-folder
        sparse-checkout-cone-mode: false
        fetch-tags: true
        show-progress: false
        lfs: true
        submodules: true
        set-safe-directory: '*'
        github-server-url: https://github.localhost
`

func TestWorkflowContent(t *testing.T) {
	tests := []struct {
		name           string
		data           workflowData
		expected       []string
		expectedRegexp []string
		unexpected     []string
		validateYaml   bool
	}{
		{
			name: "basic",
			data: workflowData{
				JobName:    "copilot",
				RunName:    "Fixing issue #123",
				Secrets:    []string{},
				Variables:  []string{},
				MCPEnabled: false,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"run-name: 'Fixing issue #123'",
				"runs-on: ${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}",
				"timeout-minutes: 59",
			},
			unexpected:   []string{},
			validateYaml: true,
		},
		{
			name: "run-name not encoded",
			data: workflowData{
				JobName:    "copilot",
				RunName:    "Quote ' should not be encoded",
				Secrets:    []string{},
				Variables:  []string{},
				MCPEnabled: false,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"run-name: 'Quote ' should not be encoded'",
			},
			unexpected: []string{
				"&#39;",
			},
			validateYaml: false,
		},
		{
			name: "different runner via labels",
			data: workflowData{
				JobName:   "copilot",
				RunName:   "PR Review #456",
				Secrets:   []string{},
				Variables: []string{},
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("windows-latest"),
					"timeout-minutes": template.HTML("59"),
				},
				MCPEnabled: false,
			},
			expected: []string{
				"run-name: 'PR Review #456'",
				"runs-on: windows-latest",
			},
			unexpected:   []string{},
			validateYaml: true,
		},
		{
			name: "secrets",
			data: workflowData{
				JobName: "copilot",
				RunName: "Fixing issue #123",
				Secrets: []string{
					"TEST_SECRET_ONE",
					"TEST_SECRET_TWO",
				},
				Variables:  []string{},
				MCPEnabled: false,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"run-name: 'Fixing issue #123'",
				"runs-on: ${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}",
				"TEST_SECRET_ONE: ${{ secrets.TEST_SECRET_ONE }}",
				"TEST_SECRET_TWO: ${{ secrets.TEST_SECRET_TWO }}",
			},
			unexpected:   []string{},
			validateYaml: true,
		},
		{
			name: "variables",
			data: workflowData{
				JobName: "copilot",
				RunName: "Fixing issue #123",
				Secrets: []string{},
				Variables: []string{
					"TEST_VARIABLE_ONE",
					"TEST_VARIABLE_TWO",
				},
				MCPEnabled: false,
				Customization: map[string]template.HTML{
					"runs-on": template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
				},
			},
			expected: []string{
				"run-name: 'Fixing issue #123'",
				"runs-on: ${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}",
				"TEST_VARIABLE_ONE: ${{ vars.TEST_VARIABLE_ONE }}",
				"TEST_VARIABLE_TWO: ${{ vars.TEST_VARIABLE_TWO }}",
			},
			unexpected:   []string{},
			validateYaml: true,
		},
		{
			name: "secrets and variables",
			data: workflowData{
				JobName: "copilot",
				RunName: "Fixing issue #123",
				Secrets: []string{
					"TEST_SECRET_ONE",
					"TEST_SECRET_TWO",
				},
				Variables: []string{
					"TEST_VARIABLE_ONE",
					"TEST_VARIABLE_TWO",
				},
				MCPEnabled: false,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"run-name: 'Fixing issue #123'",
				"runs-on: ${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}",
				"TEST_SECRET_ONE: ${{ secrets.TEST_SECRET_ONE }}",
				"TEST_SECRET_TWO: ${{ secrets.TEST_SECRET_TWO }}",
				"TEST_VARIABLE_ONE: ${{ vars.TEST_VARIABLE_ONE }}",
				"TEST_VARIABLE_TWO: ${{ vars.TEST_VARIABLE_TWO }}",
			},
			unexpected:   []string{},
			validateYaml: true,
		},
		{
			name: "secrets take precedence over variables",
			data: workflowData{
				JobName: "copilot",
				RunName: "Fixing issue #123",
				Secrets: []string{
					"TEST_SECRET_ONE",
					"TEST_SECRET_TWO",
				},
				Variables: []string{
					"TEST_SECRET_ONE",
					"TEST_VARIABLE_TWO",
				},
				MCPEnabled: false,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"run-name: 'Fixing issue #123'",
				"runs-on: ${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}",
				"TEST_SECRET_ONE: ${{ secrets.TEST_SECRET_ONE }}",
				"TEST_SECRET_TWO: ${{ secrets.TEST_SECRET_TWO }}",
				"TEST_VARIABLE_TWO: ${{ vars.TEST_VARIABLE_TWO }}",
			},
			unexpected: []string{
				"TEST_SECRET_ONE: ${{ vars.TEST_SECRET_ONE }}",
			},
			validateYaml: true,
		},
		{
			name: "MCP disabled",
			data: workflowData{
				JobName: "copilot",
				RunName: "Fixing issue #123",
				Secrets: []string{
					"COPILOT_MCP_SECRET_ONE",
				},
				Variables: []string{
					"COPILOT_MCP_VARIABLE_ONE",
				},
				MCPEnabled: false,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"run-name: 'Fixing issue #123'",
				"runs-on: ${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}",
				"COPILOT_MCP_SECRET_ONE: ${{ secrets.COPILOT_MCP_SECRET_ONE }}",
				"COPILOT_MCP_VARIABLE_ONE: ${{ vars.COPILOT_MCP_VARIABLE_ONE }}",
				"COPILOT_MCP_ENABLED: false",
				// "Start downloading Playwright MCP server in the background" step is skipped
				"if: ${{ env.SHOULD_CONTINUE == 'true' && false && runner.os == 'Linux' }}",
			},
			unexpected: []string{
				"COPILOT_MCP_ENABLED: true",
			},
			validateYaml: true,
		},
		{
			name: "MCP enabled, 3P disabled",
			data: workflowData{
				JobName: "copilot",
				RunName: "Fixing issue #123",
				Secrets: []string{
					"COPILOT_MCP_SECRET_ONE",
					"NON_MCP_SECRET",
				},
				Variables: []string{
					"COPILOT_MCP_VARIABLE_ONE",
					"NON_MCP_VARIABLE",
				},
				MCPEnabled:   true,
				MCP3PEnabled: false,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
				PlaywrightVersion: "foo",
			},
			expected: []string{
				"run-name: 'Fixing issue #123'",
				"runs-on: ${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}",
				"COPILOT_MCP_SECRET_ONE: ${{ secrets.COPILOT_MCP_SECRET_ONE }}",
				"COPILOT_MCP_VARIABLE_ONE: ${{ vars.COPILOT_MCP_VARIABLE_ONE }}",
				"NON_MCP_SECRET: ${{ secrets.NON_MCP_SECRET }}",
				"NON_MCP_VARIABLE: ${{ vars.NON_MCP_VARIABLE }}",
				"COPILOT_MCP_ENABLED: true",
				"GITHUB_COPILOT_MCP_JSON_FROM_INPUT: \"${{ github.event.inputs.GITHUB_COPILOT_MCP_JSON }}\"",
				"GITHUB_COPILOT_REMOTE_MCP_ENABLED: false",
				// "Start downloading Playwright MCP server in the background" step is run
				"if: ${{ env.SHOULD_CONTINUE == 'true' && true && runner.os == 'Linux' }}",
				// "Start downloading Playwright MCP server in the background" step is configured with the correct version
				"PLAYWRIGHT_VERSION: \"foo\"",
			},
			unexpected: []string{
				"COPILOT_MCP_ENABLED: false",
				"GITHUB_COPILOT_3P_MCP_ENABLED: true",
				"GITHUB_COPILOT_REMOTE_MCP_ENABLED: true",
			},
			validateYaml: true,
		},
		{
			name: "MCP enabled, 3P enabled",
			data: workflowData{
				JobName: "copilot",
				RunName: "Fixing issue #123",
				Secrets: []string{
					"COPILOT_MCP_SECRET_ONE",
					"NON_MCP_SECRET",
				},
				Variables: []string{
					"COPILOT_MCP_VARIABLE_ONE",
					"NON_MCP_VARIABLE",
				},
				MCPEnabled:   true,
				MCP3PEnabled: true,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
				PlaywrightVersion: "foo",
			},
			expected: []string{
				"run-name: 'Fixing issue #123'",
				"runs-on: ${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}",
				"COPILOT_MCP_SECRET_ONE: ${{ secrets.COPILOT_MCP_SECRET_ONE }}",
				"COPILOT_MCP_VARIABLE_ONE: ${{ vars.COPILOT_MCP_VARIABLE_ONE }}",
				"NON_MCP_SECRET: ${{ secrets.NON_MCP_SECRET }}",
				"NON_MCP_VARIABLE: ${{ vars.NON_MCP_VARIABLE }}",
				"COPILOT_MCP_ENABLED: true",
				"GITHUB_COPILOT_MCP_JSON_FROM_INPUT: \"${{ github.event.inputs.GITHUB_COPILOT_MCP_JSON }}\"",
				"GITHUB_COPILOT_3P_MCP_ENABLED: true",
				"GITHUB_COPILOT_REMOTE_MCP_ENABLED: false",
				// "Start downloading Playwright MCP server in the background" step is run
				"if: ${{ env.SHOULD_CONTINUE == 'true' && true && runner.os == 'Linux' }}",
				// "Start downloading Playwright MCP server in the background" step is configured with the correct version
				"PLAYWRIGHT_VERSION: \"foo\"",
			},
			unexpected: []string{
				"COPILOT_MCP_ENABLED: false",
				"GITHUB_COPILOT_3P_MCP_ENABLED: false",
				"GITHUB_COPILOT_REMOTE_MCP_ENABLED: true",
			},
			validateYaml: true,
		},
		{
			name: "MCP enabled, 3P enabled, remote enabled",
			data: workflowData{
				JobName: "copilot",
				RunName: "Fixing issue #123",
				Secrets: []string{
					"COPILOT_MCP_SECRET_ONE",
					"NON_MCP_SECRET",
				},
				Variables: []string{
					"COPILOT_MCP_VARIABLE_ONE",
					"NON_MCP_VARIABLE",
				},
				MCPEnabled:       true,
				MCP3PEnabled:     true,
				McpRemoteEnabled: true,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
				PlaywrightVersion: "foo",
			},
			expected: []string{
				"run-name: 'Fixing issue #123'",
				"runs-on: ${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}",
				"COPILOT_MCP_SECRET_ONE: ${{ secrets.COPILOT_MCP_SECRET_ONE }}",
				"COPILOT_MCP_VARIABLE_ONE: ${{ vars.COPILOT_MCP_VARIABLE_ONE }}",
				"NON_MCP_SECRET: ${{ secrets.NON_MCP_SECRET }}",
				"NON_MCP_VARIABLE: ${{ vars.NON_MCP_VARIABLE }}",
				"COPILOT_MCP_ENABLED: true",
				"GITHUB_COPILOT_MCP_JSON_FROM_INPUT: \"${{ github.event.inputs.GITHUB_COPILOT_MCP_JSON }}\"",
				"GITHUB_COPILOT_3P_MCP_ENABLED: true",
				"GITHUB_COPILOT_REMOTE_MCP_ENABLED: true",
				// "Start downloading Playwright MCP server in the background" step is run
				"if: ${{ env.SHOULD_CONTINUE == 'true' && true && runner.os == 'Linux' }}",
				// "Start downloading Playwright MCP server in the background" step is configured with the correct version
				"PLAYWRIGHT_VERSION: \"foo\"",
			},
			unexpected: []string{
				"COPILOT_MCP_ENABLED: false",
				"GITHUB_COPILOT_3P_MCP_ENABLED: false",
				"GITHUB_COPILOT_REMOTE_MCP_ENABLED: false",
			},
			validateYaml: true,
		},
		{
			name: "development variables appear",
			data: workflowData{
				JobName:                  "copilot",
				RunName:                  "Fixing issue #123",
				IsDevelopmentEnvironment: true,
				MCPEnabled:               false,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"run-name: 'Fixing issue #123'",
				"runs-on: ${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}",
				"COPILOT_INTEGRATION_ID_OVERRIDE: \"${{ secrets.COPILOT_INTEGRATION_ID_OVERRIDE }}\"",
				"CAPI_HMAC_KEY_OVERRIDE: \"${{ secrets.CAPI_HMAC_KEY_OVERRIDE }}\"",
			},
			validateYaml: true,
		},
		{
			name: "development variables do not appear",
			data: workflowData{
				JobName:                  "copilot",
				RunName:                  "Fixing issue #123",
				IsDevelopmentEnvironment: false,
				MCPEnabled:               false,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"run-name: 'Fixing issue #123'",
				"runs-on: ${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}",
			},
			unexpected: []string{
				"COPILOT_INTEGRATION_ID_OVERRIDE: \"${{ secrets.COPILOT_INTEGRATION_ID_OVERRIDE }}\"",
				"CAPI_HMAC_KEY_OVERRIDE: \"${{ secrets.CAPI_HMAC_KEY_OVERRIDE }}\"",
			},
			validateYaml: true,
		},
		{
			name: "known step names are included",
			data: workflowData{
				JobName:    "copilot",
				RunName:    "Fixing issue #123",
				MCPEnabled: true,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected:     ActionsWorkflowJobKnownSteps(),
			unexpected:   []string{},
			validateYaml: true,
		},
		{
			name: "continues if custom setup steps fail",
			data: workflowData{
				JobName:    "copilot",
				RunName:    "Fixing issue #123",
				MCPEnabled: true,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"if: ${{ env.SHOULD_CONTINUE == 'true' && (success() || !cancelled()) && runner.os == 'Linux' }}",
			},
			validateYaml: true,
		},
		{
			name: "HTTP_PROXY does not get injected by default",
			data: workflowData{
				JobName:    "copilot",
				RunName:    "Fixing issue #123",
				Secrets:    []string{},
				Variables:  []string{},
				MCPEnabled: false,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			unexpected: []string{
				"HTTP_PROXY: ",
			},
			validateYaml: true,
		},
		{
			name: "HTTP_PROXY is injected if set in variable",
			data: workflowData{
				JobName: "copilot",
				RunName: "Fixing issue #123",
				Secrets: []string{},
				Variables: []string{
					"HTTP_PROXY",
				},
				MCPEnabled: false,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"HTTP_PROXY: ",
			},
			validateYaml: true,
		},
		{
			name: "HTTP_PROXY is injected if set in secret",
			data: workflowData{
				JobName: "copilot",
				RunName: "Fixing issue #123",
				Secrets: []string{
					"HTTP_PROXY",
				},
				Variables:  []string{},
				MCPEnabled: false,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"HTTP_PROXY: ",
			},
			validateYaml: true,
		},
		{
			name: "HTTPS_PROXY does not get injected by default",
			data: workflowData{
				JobName:    "copilot",
				RunName:    "Fixing issue #123",
				Secrets:    []string{},
				Variables:  []string{},
				MCPEnabled: false,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			unexpected: []string{
				"HTTPS_PROXY: ",
			},
			validateYaml: true,
		},
		{
			name: "HTTPS_PROXY is injected if set in variable",
			data: workflowData{
				JobName: "copilot",
				RunName: "Fixing issue #123",
				Secrets: []string{},
				Variables: []string{
					"HTTPS_PROXY",
				},
				MCPEnabled: false,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"HTTPS_PROXY: ",
			},
			validateYaml: true,
		},
		{
			name: "HTTPS_PROXY is injected if set in secret",
			data: workflowData{
				JobName: "copilot",
				RunName: "Fixing issue #123",
				Secrets: []string{
					"HTTPS_PROXY",
				},
				Variables:  []string{},
				MCPEnabled: false,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"HTTPS_PROXY: ",
			},
			validateYaml: true,
		},
		{
			name: "SSL_CERT_FILE does not get injected by default",
			data: workflowData{
				JobName:    "copilot",
				RunName:    "Fixing issue #123",
				Secrets:    []string{},
				Variables:  []string{},
				MCPEnabled: false,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			unexpected: []string{
				"SSL_CERT_FILE: ",
			},
			validateYaml: true,
		},
		{
			name: "SSL_CERT_FILE is injected if set in variable",
			data: workflowData{
				JobName: "copilot",
				RunName: "Fixing issue #123",
				Secrets: []string{},
				Variables: []string{
					"SSL_CERT_FILE",
				},
				MCPEnabled: false,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"SSL_CERT_FILE: ",
			},
			validateYaml: true,
		},
		{
			name: "SSL_CERT_FILE is injected if set in secret",
			data: workflowData{
				JobName: "copilot",
				RunName: "Fixing issue #123",
				Secrets: []string{
					"SSL_CERT_FILE",
				},
				Variables:  []string{},
				MCPEnabled: false,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"SSL_CERT_FILE: ",
			},
			validateYaml: true,
		},
		{
			name: "NODE_EXTRA_CA_CERTS does not get injected by default",
			data: workflowData{
				JobName:    "copilot",
				RunName:    "Fixing issue #123",
				Secrets:    []string{},
				Variables:  []string{},
				MCPEnabled: false,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			unexpected: []string{
				"NODE_EXTRA_CA_CERTS: ",
			},
			validateYaml: true,
		},
		{
			name: "NODE_EXTRA_CA_CERTS is injected if set in variable",
			data: workflowData{
				JobName: "copilot",
				RunName: "Fixing issue #123",
				Secrets: []string{},
				Variables: []string{
					"NODE_EXTRA_CA_CERTS",
				},
				MCPEnabled: false,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"NODE_EXTRA_CA_CERTS: ",
			},
			validateYaml: true,
		},
		{
			name: "NODE_EXTRA_CA_CERTS is injected if set in secret",
			data: workflowData{
				JobName: "copilot",
				RunName: "Fixing issue #123",
				Secrets: []string{
					"NODE_EXTRA_CA_CERTS",
				},
				Variables:  []string{},
				MCPEnabled: false,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"NODE_EXTRA_CA_CERTS: ",
			},
			validateYaml: true,
		},
		{
			name: "NO_PROXY does not get injected by default",
			data: workflowData{
				JobName:    "copilot",
				RunName:    "Fixing issue #123",
				Secrets:    []string{},
				Variables:  []string{},
				MCPEnabled: false,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			unexpected: []string{
				"NO_PROXY: ",
			},
			validateYaml: true,
		},
		{
			name: "NO_PROXY is injected if set in variable",
			data: workflowData{
				JobName: "copilot",
				RunName: "Fixing issue #123",
				Secrets: []string{},
				Variables: []string{
					"NO_PROXY",
				},
				MCPEnabled: false,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"NO_PROXY: ",
			},
			validateYaml: true,
		},
		{
			name: "NO_PROXY is injected if set in secret",
			data: workflowData{
				JobName: "copilot",
				RunName: "Fixing issue #123",
				Secrets: []string{
					"NO_PROXY",
				},
				Variables:  []string{},
				MCPEnabled: false,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"NO_PROXY: ",
			},
			validateYaml: true,
		},
		{
			name: "SSL_CERT_FILE does not get injected by default",
			data: workflowData{
				RunName:    "Fixing issue #123",
				Secrets:    []string{},
				Variables:  []string{},
				MCPEnabled: false,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			unexpected: []string{
				"SSL_CERT_FILE: ",
			},
		},
		{
			name: "SSL_CERT_FILE is injected if set in variable",
			data: workflowData{
				RunName: "Fixing issue #123",
				Secrets: []string{},
				Variables: []string{
					"SSL_CERT_FILE",
				},
				MCPEnabled: false,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"SSL_CERT_FILE: ",
			},
		},
		{
			name: "SSL_CERT_FILE is injected if set in secret",
			data: workflowData{
				RunName: "Fixing issue #123",
				Secrets: []string{
					"SSL_CERT_FILE",
				},
				Variables:  []string{},
				MCPEnabled: false,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"SSL_CERT_FILE: ",
			},
		},
		{
			name: "default entry point is dist/index.js",
			data: workflowData{
				JobName:           "copilot",
				RunName:           "Fixing issue #123",
				MCPEnabled:        false,
				RuntimeEntryPoint: "dist/index.js",
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"${{ runner.temp }}/copilot-developer-action-main/dist/index.js",
			},
			validateYaml: true,
		},
		{
			name: "cca entry point is dist-cca/index.js",
			data: workflowData{
				JobName:           "copilot",
				RunName:           "Fixing issue #123",
				MCPEnabled:        false,
				RuntimeEntryPoint: "dist-cca/index.js",
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"${{ runner.temp }}/copilot-developer-action-main/dist-cca/index.js",
			},
			validateYaml: true,
		},
		{
			name: "claude entry point is dist-claude/index.js",
			data: workflowData{
				JobName:           "copilot",
				RunName:           "Fixing issue #123",
				MCPEnabled:        false,
				RuntimeEntryPoint: "dist-claude/index.js",
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"${{ runner.temp }}/copilot-developer-action-main/dist-claude/index.js",
			},
			validateYaml: true,
		},
		{
			name: "codex entry point is dist-codex/index.js",
			data: workflowData{
				JobName:           "copilot",
				RunName:           "Fixing issue #123",
				MCPEnabled:        false,
				RuntimeEntryPoint: "dist-codex/index.js",
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"${{ runner.temp }}/copilot-developer-action-main/dist-codex/index.js",
			},
			validateYaml: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			launcher := &ActionsLauncher{
				opts: ActionsLauncherOpts{
					ActionsDefaultRunsOnLabels: "ubuntu-latest",
				},
			}

			result, err := launcher.workflowContent(context.Background(), &tt.data, workflowTemplate, nil)
			require.NoError(t, err, "workflowContent should not return an error")

			if tt.validateYaml {
				var yamlData any
				err = yaml.Unmarshal([]byte(result), &yamlData)
				require.NoError(t, err, "workflow content should be valid YAML")
			}

			for _, expected := range tt.expected {
				assert.Contains(t, result, expected, "workflow content should contain the expected string")
			}

			for _, expected := range tt.expectedRegexp {
				assert.Regexp(t, expected, result, "workflow content should match the expected regex")
			}

			for _, unexpected := range tt.unexpected {
				assert.NotContains(t, result, unexpected, "workflow content should not contain the unexpected string")
			}
		})
	}
}

func TestKnownStepNames(t *testing.T) {
	launcher := &ActionsLauncher{
		opts: ActionsLauncherOpts{
			ActionsDefaultRunsOnLabels: "ubuntu-latest",
		},
	}

	data := workflowData{
		JobName:    "copilot",
		RunName:    "Fixing issue #123",
		MCPEnabled: true,
		Customization: map[string]template.HTML{
			"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
			"timeout-minutes": template.HTML("59"),
		},
	}

	result, err := launcher.workflowContent(context.Background(), &data, workflowTemplate, nil)
	require.NoError(t, err, "workflowContent should not return an error")

	stepNameRegex := regexp.MustCompile(`^\s*-\s+name:\s*(.+)$`)

	var stepNames []string
	lines := strings.SplitSeq(result, "\n")
	for line := range lines {
		matches := stepNameRegex.FindStringSubmatch(line)

		if len(matches) > 1 {
			stepName := strings.TrimSpace(matches[1])
			// Remove quotes if present
			stepName = strings.Trim(stepName, "'\"")
			stepNames = append(stepNames, stepName)
		}
	}

	// Check if the known step names are present in the result
	for _, stepName := range stepNames {
		assert.Contains(t, ActionsWorkflowJobKnownSteps(), stepName, "Expected step name %s not found in known steps", stepName)
	}
}

// TestWorkflowContentPointerBehavior verifies that workflowContent correctly modifies
// the workflowData passed as a pointer, and produces the expected output.
func TestWorkflowContentPointerBehavior(t *testing.T) {
	launcher := &ActionsLauncher{
		opts: ActionsLauncherOpts{
			ActionsDefaultRunsOnLabels: "ubuntu-latest",
		},
	}

	t.Run("modifies secrets and variables slices in place", func(t *testing.T) {
		// Create data with secrets/variables that should be filtered
		data := workflowData{
			JobName: "copilot",
			RunName: "Fixing issue #123",
			// COPILOT_AGENT_DEBUG is in workflowDirectlyReferencedVarNames
			Secrets: []string{
				"TEST_SECRET",
				"COPILOT_AGENT_DEBUG",
			},
			Variables: []string{
				"TEST_VARIABLE",
				"COPILOT_AGENT_FIREWALL_ENABLED",
			},
			MCPEnabled: false,
			Customization: map[string]template.HTML{
				"runs-on":         template.HTML("ubuntu-latest"),
				"timeout-minutes": template.HTML("59"),
			},
		}

		originalSecretsLen := len(data.Secrets)
		originalVariablesLen := len(data.Variables)

		result, err := launcher.workflowContent(context.Background(), &data, workflowTemplate, nil)
		require.NoError(t, err, "workflowContent should not return an error")

		// With pointer semantics, the data should be modified in place
		// Secrets should have COPILOT_AGENT_DEBUG removed
		assert.Less(t, len(data.Secrets), originalSecretsLen, "Secrets slice should be modified")
		assert.NotContains(t, data.Secrets, "COPILOT_AGENT_DEBUG", "COPILOT_AGENT_DEBUG should be removed from Secrets")
		assert.Contains(t, data.Secrets, "TEST_SECRET", "TEST_SECRET should remain in Secrets")

		// Variables should have COPILOT_AGENT_FIREWALL_ENABLED removed
		assert.Less(t, len(data.Variables), originalVariablesLen, "Variables slice should be modified")
		assert.NotContains(t, data.Variables, "COPILOT_AGENT_FIREWALL_ENABLED", "COPILOT_AGENT_FIREWALL_ENABLED should be removed from Variables")
		assert.Contains(t, data.Variables, "TEST_VARIABLE", "TEST_VARIABLE should remain in Variables")

		// Verify the output still has the correct content
		assert.Contains(t, result, "TEST_SECRET: ${{ secrets.TEST_SECRET }}", "output should contain TEST_SECRET")
		assert.Contains(t, result, "TEST_VARIABLE: ${{ vars.TEST_VARIABLE }}", "output should contain TEST_VARIABLE")
		assert.NotContains(t, result, "COPILOT_AGENT_DEBUG: ${{ secrets.COPILOT_AGENT_DEBUG }}", "output should not duplicate COPILOT_AGENT_DEBUG")
	})

	t.Run("extractMCPVars modifies data when MCP enabled", func(t *testing.T) {
		data := workflowData{
			JobName:    "copilot",
			RunName:    "Fixing issue #123",
			MCPEnabled: true,
			Secrets: []string{
				"TEST_SECRET",
				"COPILOT_MCP_TEST_SECRET", // MCP prefixed should be extracted
			},
			Variables: []string{
				"TEST_VARIABLE",
				"COPILOT_MCP_TEST_VARIABLE", // MCP prefixed should be extracted
			},
			MCPSecrets:   []string{},
			MCPVariables: []string{},
			Customization: map[string]template.HTML{
				"runs-on":         template.HTML("ubuntu-latest"),
				"timeout-minutes": template.HTML("59"),
			},
		}

		_, err := launcher.workflowContent(context.Background(), &data, workflowTemplate, nil)
		require.NoError(t, err, "workflowContent should not return an error")

		// MCP secrets/variables should be moved to the separate slices
		assert.Contains(t, data.MCPSecrets, "COPILOT_MCP_TEST_SECRET", "COPILOT_MCP_TEST_SECRET should be in MCPSecrets")
		assert.NotContains(t, data.Secrets, "COPILOT_MCP_TEST_SECRET", "COPILOT_MCP_TEST_SECRET should be removed from Secrets")
		assert.Contains(t, data.MCPVariables, "COPILOT_MCP_TEST_VARIABLE", "COPILOT_MCP_TEST_VARIABLE should be in MCPVariables")
		assert.NotContains(t, data.Variables, "COPILOT_MCP_TEST_VARIABLE", "COPILOT_MCP_TEST_VARIABLE should be removed from Variables")
	})

	t.Run("secrets take precedence over variables with same name", func(t *testing.T) {
		data := workflowData{
			JobName:    "copilot",
			RunName:    "Fixing issue #123",
			MCPEnabled: false,
			Secrets: []string{
				"SAME_NAME",
				"TEST_SECRET",
			},
			Variables: []string{
				"SAME_NAME",
				"TEST_VARIABLE",
			},
			Customization: map[string]template.HTML{
				"runs-on":         template.HTML("ubuntu-latest"),
				"timeout-minutes": template.HTML("59"),
			},
		}

		result, err := launcher.workflowContent(context.Background(), &data, workflowTemplate, nil)
		require.NoError(t, err, "workflowContent should not return an error")

		// With pointer semantics, SAME_NAME should be removed from Variables
		assert.Contains(t, data.Secrets, "SAME_NAME", "SAME_NAME should remain in Secrets")
		assert.NotContains(t, data.Variables, "SAME_NAME", "SAME_NAME should be removed from Variables")

		// Output should only have the secret version
		assert.Contains(t, result, "SAME_NAME: ${{ secrets.SAME_NAME }}", "output should contain SAME_NAME as secret")
	})
}

func TestGenerateRunName(t *testing.T) {
	tests := []struct {
		name     string
		opts     LaunchAgentOpts
		expected string
	}{
		{
			name: "fix-pr-comment",
			opts: LaunchAgentOpts{
				Action:   "fix-pr-comment",
				PRNumber: 456,
			},
			expected: "Addressing comment on PR #456",
		},
		{
			name: "fix-issue",
			opts: LaunchAgentOpts{
				Action:      "fix-issue",
				IssueNumber: 123,
			},
			expected: "Fixing issue #123",
		},
		{
			opts: LaunchAgentOpts{
				RunName:  "Applying Code Scanning Autofix on PR #123",
				PRNumber: 123,
			},
			expected: "Applying Code Scanning Autofix on PR #123",
		},
		{
			opts: LaunchAgentOpts{
				RunName:  "Single quote ' should be escaped",
				PRNumber: 123,
			},
			expected: "Single quote '' should be escaped",
		},
		{
			opts: LaunchAgentOpts{
				RunName:  "Run name should be truncated to 255 characters, which is the maximum length for GitHub Actions run names. This is a very long run name that exceeds the limit and should be truncated accordingly. Oh wait, it's not long enough, still not long enough, still (OK, you shouldn't see any of this now)",
				PRNumber: 123,
			},
			expected: "Run name should be truncated to 255 characters, which is the maximum length for GitHub Actions run names. This is a very long run name that exceeds the limit and should be truncated accordingly. Oh wait, it''s not long enough, still not long enough, st...",
		},
		{
			opts: LaunchAgentOpts{
				RunName: `Multi-line run-name
 be shrunk to one-liner
without bloated empty spaces`,
				PRNumber: 123,
			},
			expected: "Multi-line run-name be shrunk to one-liner without bloated empty spaces",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := GenerateRunName(&tt.opts)
			assert.Equal(t, tt.expected, result, "GenerateRunName should return the expected run name")
		})
	}
}

func TestGenerateSetupStepsErrorComment(t *testing.T) {
	testErr := errors.New("Oopsie-doo")
	ctx := context.Background()
	cf := github.NoopClientFactory{
		GitHubAppLogin: "copilot-swe-agent",
		GitHubBotLogin: "copilot-swe-agent[bot]",
	}
	launcher := &ActionsLauncher{
		obsv: observability.NewNoopExporters(),
		opts: ActionsLauncherOpts{
			ActionsDefaultRunsOnLabels: "ubuntu-latest",
		},
	}

	t.Run("error during fix", func(t *testing.T) {
		gh := cf.NewClient("fake-token")
		opts := LaunchAgentOpts{
			Action:     "fix",
			ActorLogin: "monalisa",
			PRNumber:   2,
		}
		err := launcher.handleActionsSetupStepsError(ctx, gh, testErr, &opts)
		require.NoError(t, err, "processCustomActionsWorkflow should not return an error")

		var createCommentCall *github.MethodCall
		for _, call := range gh.(*github.NoopClient).MethodCalls {
			switch call.Method {
			case "CreateComment":
				createCommentCall = &call
			default:
				continue
			}
		}
		// Check comment
		assert.NotNil(t, createCommentCall, "CreateIssueComment should have been called")
		assert.Len(t, createCommentCall.Args, 3)
		commentBody := createCommentCall.Args[2].(string)
		assert.Contains(t, commentBody, "@monalisa")
		assert.Contains(t, commentBody, "Oopsie-doo")
	})

	t.Run("error during fix-comment", func(t *testing.T) {
		gh := cf.NewClient("fake-token")
		opts := LaunchAgentOpts{
			Action:     "fix-comment",
			ActorLogin: "monalisa",
			PRNumber:   2,
		}
		err := launcher.handleActionsSetupStepsError(ctx, gh, testErr, &opts)
		require.NoError(t, err, "processCustomActionsWorkflow should not return an error")

		var createCommentCall *github.MethodCall
		for _, call := range gh.(*github.NoopClient).MethodCalls {
			if call.Method == "CreateComment" {
				createCommentCall = &call
			}
		}
		// Check comment
		assert.NotNil(t, createCommentCall, "CreateIssueComment should have been called")
		commentBody := createCommentCall.Args[2].(string)
		assert.Contains(t, commentBody, "@monalisa")
		assert.Contains(t, commentBody, "Oopsie-doo")
	})
}

func TestCustomWorkflows(t *testing.T) {
	launcher := &ActionsLauncher{
		ffClient: featureflags.NewNoopClient(map[string]bool{}),
		opts: ActionsLauncherOpts{
			ActionsDefaultRunsOnLabels: "ubuntu-latest",
		},
		obsv: observability.NewNoopExporters(),
	}

	t.Run("All customization options", func(t *testing.T) {
		const workflow = workflowPrefix + workflowRunsOnLine + workflowPermissions + workflowMisc + workflowSteps
		data := workflowData{
			RunName:                     "Fixing issue #123",
			AgentDebug:                  true,
			AgentFirewallEnabledDefault: true,
			IsDevelopmentEnvironment:    true,
			MCPEnabled:                  true,
			Customization: map[string]template.HTML{
				"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
				"timeout-minutes": template.HTML("59"),
			},
		}
		opts := LaunchAgentOpts{
			CommitCount: 5,
			GitHubRepo:  "legit/repo",
			BranchName:  "legit-branch",
		}
		updatedCustomization, _, err := launcher.processSetupStepsWorkflow(context.Background(), workflow, data.Customization, &opts, "https://api.githubcopilot.com")
		require.NoError(t, err, "processCustomActionsWorkflow should not return an error")
		data.Customization = updatedCustomization
		content, err := launcher.workflowContent(context.Background(), &data, workflowTemplate, nil)
		require.NoError(t, err, "workflowContent should not return an error")

		// Note deployments: write should be automatically added here
		assert.Contains(t, content, "    permissions: \n      contents: read\n      deployments: write\n      id-token: write", "permissions are incorrect")

		assert.Contains(t, content, "    runs-on: custom-runner", "runs-on is incorrect")

		// The yaml will be alphabetized, so just check each line - spacing covers the dupes
		expectedLines := strings.SplitSeq(workflowMisc, "\n")
		for line := range expectedLines {
			assert.Contains(t, content, line, "workflow content should contain the expected string")
		}
		assert.Contains(t, content, "timeout-minutes: 30", "timeout-minutes is incorrect")
		assert.Contains(t, content, "echo \"COPILOT_AGENT_TIMEOUT_MIN=30\" >> $GITHUB_ENV", "COPILOT_AGENT_TIMEOUT_MIN is incorrect")

		checkStepContent(t, content)
	})

	t.Run("No line permissions, but top level permissions", func(t *testing.T) {
		const workflow = workflowPrefixWithTopLevelPermissions + workflowRunsOnLine + workflowMisc + workflowSteps
		data := workflowData{
			RunName:                     "Fixing issue #123",
			AgentDebug:                  true,
			AgentFirewallEnabledDefault: true,
			IsDevelopmentEnvironment:    true,
			MCPEnabled:                  true,
			Customization: map[string]template.HTML{
				"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
				"timeout-minutes": template.HTML("59"),
			},
		}
		opts := LaunchAgentOpts{
			CommitCount: 5,
			GitHubRepo:  "legit/repo",
			BranchName:  "legit-branch",
		}
		updatedCustomization, _, err := launcher.processSetupStepsWorkflow(context.Background(), workflow, data.Customization, &opts, "https://api.githubcopilot.com")
		require.NoError(t, err, "processCustomActionsWorkflow should not return an error")
		data.Customization = updatedCustomization
		content, err := launcher.workflowContent(context.Background(), &data, workflowTemplate, nil)
		require.NoError(t, err, "workflowContent should not return an error")

		// Note deployments: write should be automatically added here
		assert.Contains(t, content, "    permissions: \n      contents: write\n      deployments: write\n", "permissions are incorrect")

		assert.Contains(t, content, "    runs-on: custom-runner", "runs-on is incorrect")

		// The yaml will be alphabetized, so just check each line - spacing covers the dupes
		expectedLines := strings.SplitSeq(workflowMisc, "\n")
		for line := range expectedLines {
			assert.Contains(t, content, line, "workflow content should contain the expected string")
		}
		assert.Contains(t, content, "timeout-minutes: 30", "timeout-minutes is incorrect")
		assert.Contains(t, content, "echo \"COPILOT_AGENT_TIMEOUT_MIN=30\" >> $GITHUB_ENV", "COPILOT_AGENT_TIMEOUT_MIN is incorrect")

		checkStepContent(t, content)
	})

	t.Run("Runs-on line, no permissions", func(t *testing.T) {
		const workflow = workflowPrefix + workflowRunsOnLine + workflowSteps
		data := workflowData{
			RunName:                     "Fixing issue #123",
			AgentDebug:                  true,
			AgentFirewallEnabledDefault: true,
			IsDevelopmentEnvironment:    true,
			MCPEnabled:                  true,
			Customization: map[string]template.HTML{
				"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
				"timeout-minutes": template.HTML("59"),
			},
		}
		opts := LaunchAgentOpts{
			CommitCount: 5,
			GitHubRepo:  "legit/repo",
			BranchName:  "legit-branch",
		}
		updatedCustomization, _, err := launcher.processSetupStepsWorkflow(context.Background(), workflow, data.Customization, &opts, "https://api.githubcopilot.com")
		require.NoError(t, err, "processCustomActionsWorkflow should not return an error")
		data.Customization = updatedCustomization
		content, err := launcher.workflowContent(context.Background(), &data, workflowTemplate, nil)
		require.NoError(t, err, "workflowContent should not return an error")

		assert.Contains(t, content, "    permissions: \n      deployments: write\n", "permissions are incorrect")

		assert.Contains(t, content, "    runs-on: custom-runner", "runs-on is incorrect")

		assert.Contains(t, content, "timeout-minutes: 59", "timeout-minutes is incorrect")
		assert.Contains(t, content, "echo \"COPILOT_AGENT_TIMEOUT_MIN=59\" >> $GITHUB_ENV", "COPILOT_AGENT_TIMEOUT_MIN is incorrect")

		checkStepContent(t, content)
	})

	t.Run("Runs-on object, no permissions", func(t *testing.T) {
		const workflow = workflowPrefix + workflowRunsOnObject + workflowSteps
		data := workflowData{
			RunName:                     "Fixing issue #123",
			AgentDebug:                  true,
			AgentFirewallEnabledDefault: true,
			IsDevelopmentEnvironment:    true,
			MCPEnabled:                  true,
			Customization: map[string]template.HTML{
				"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
				"timeout-minutes": template.HTML("59"),
			},
		}
		opts := LaunchAgentOpts{
			CommitCount: 5,
			GitHubRepo:  "legit/repo",
			BranchName:  "legit-branch",
		}
		updatedCustomization, _, err := launcher.processSetupStepsWorkflow(context.Background(), workflow, data.Customization, &opts, "https://api.githubcopilot.com")
		require.NoError(t, err, "processCustomActionsWorkflow should not return an error")
		data.Customization = updatedCustomization
		content, err := launcher.workflowContent(context.Background(), &data, workflowTemplate, nil)
		require.NoError(t, err, "workflowContent should not return an error")

		// Note deployments: write should be automatically added here
		assert.Contains(t, content, "    permissions: \n      deployments: write\n", "permissions are incorrect")

		// Note permissions comes back alphabetically sorted, so the order may be different
		assert.Contains(t, content, "    runs-on: \n      group: some-group-goes-here\n      label: custom-runner", "runs-on is incorrect")

		assert.Contains(t, content, "timeout-minutes: 59", "timeout-minutes is incorrect")
		assert.Contains(t, content, "echo \"COPILOT_AGENT_TIMEOUT_MIN=59\" >> $GITHUB_ENV", "COPILOT_AGENT_TIMEOUT_MIN is incorrect")

		checkStepContent(t, content)
	})

	t.Run("Calling a reusable workflow with uses:", func(t *testing.T) {
		const workflow = workflowPrefix + workflowUsesOnLine
		data := workflowData{
			RunName:                     "Fixing issue #123",
			AgentDebug:                  true,
			AgentFirewallEnabledDefault: true,
			IsDevelopmentEnvironment:    true,
			MCPEnabled:                  true,
			Customization: map[string]template.HTML{
				"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
				"timeout-minutes": template.HTML("59"),
			},
		}
		opts := LaunchAgentOpts{
			CommitCount: 5,
			GitHubRepo:  "legit/repo",
			BranchName:  "legit-branch",
		}
		updatedCustomization, _, err := launcher.processSetupStepsWorkflow(context.Background(), workflow, data.Customization, &opts, "https://api.githubcopilot.com")
		require.Error(t, err, "processCustomActionsWorkflow should return an error")
		assert.Contains(t, err.Error(), "calling a reusable workflow with the `uses:` keyword is not supported in `copilot-setup-steps` jobs", "error message is incorrect")
		assert.Nil(t, updatedCustomization)
	})

	t.Run("Permissions, no runs-on", func(t *testing.T) {
		const workflow = workflowPrefix + workflowPermissions + workflowSteps
		data := workflowData{
			RunName:                     "Fixing issue #123",
			AgentDebug:                  true,
			AgentFirewallEnabledDefault: true,
			IsDevelopmentEnvironment:    true,
			MCPEnabled:                  true,
			Customization: map[string]template.HTML{
				"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
				"timeout-minutes": template.HTML("59"),
			},
		}
		opts := LaunchAgentOpts{
			CommitCount: 5,
			GitHubRepo:  "legit/repo",
			BranchName:  "legit-branch",
		}
		updatedCustomization, _, err := launcher.processSetupStepsWorkflow(context.Background(), workflow, data.Customization, &opts, "https://api.githubcopilot.com")
		require.NoError(t, err, "processCustomActionsWorkflow should not return an error")
		data.Customization = updatedCustomization
		content, err := launcher.workflowContent(context.Background(), &data, workflowTemplate, nil)
		require.NoError(t, err, "workflowContent should not return an error")

		// Note permissions comes back alphabetically sorted, so the order may be different, and deployments write should be auto-added
		assert.Contains(t, content, "    permissions: \n      contents: read\n      deployments: write\n      id-token: write", "permissions are incorrect")

		assert.Contains(t, content, "    runs-on: ${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}", "runs-on is incorrect")
		assert.NotContains(t, content, "custom-runner")

		assert.Contains(t, content, "timeout-minutes: 59", "timeout-minutes is incorrect")
		assert.Contains(t, content, "echo \"COPILOT_AGENT_TIMEOUT_MIN=59\" >> $GITHUB_ENV", "COPILOT_AGENT_TIMEOUT_MIN is incorrect")

		checkStepContent(t, content)
	})

	t.Run("Permissions write-all", func(t *testing.T) {
		const workflow = workflowPrefix + workflowPermissionsWriteAll + workflowSteps
		data := workflowData{
			RunName:                     "Fixing issue #123",
			AgentDebug:                  true,
			AgentFirewallEnabledDefault: true,
			IsDevelopmentEnvironment:    true,
			MCPEnabled:                  true,
			Customization: map[string]template.HTML{
				"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
				"timeout-minutes": template.HTML("59"),
			},
		}
		opts := LaunchAgentOpts{
			CommitCount: 5,
			GitHubRepo:  "legit/repo",
			BranchName:  "legit-branch",
		}
		updatedCustomization, _, err := launcher.processSetupStepsWorkflow(context.Background(), workflow, data.Customization, &opts, "https://api.githubcopilot.com")
		require.NoError(t, err, "processCustomActionsWorkflow should not return an error")
		data.Customization = updatedCustomization
		content, err := launcher.workflowContent(context.Background(), &data, workflowTemplate, nil)
		require.NoError(t, err, "workflowContent should not return an error")

		assert.Contains(t, content, "    permissions: write-all", "permissions are incorrect")

		checkStepContent(t, content)
	})

	t.Run("Permissions read-all", func(t *testing.T) {
		const workflow = workflowPrefix + workflowPermissionsReadAll + workflowSteps
		data := workflowData{
			RunName:                     "Fixing issue #123",
			AgentDebug:                  true,
			AgentFirewallEnabledDefault: true,
			IsDevelopmentEnvironment:    true,
			MCPEnabled:                  true,
			Customization: map[string]template.HTML{
				"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
				"timeout-minutes": template.HTML("59"),
			},
		}
		opts := LaunchAgentOpts{
			CommitCount: 5,
			GitHubRepo:  "legit/repo",
			BranchName:  "legit-branch",
		}
		updatedCustomization, _, err := launcher.processSetupStepsWorkflow(context.Background(), workflow, data.Customization, &opts, "https://api.githubcopilot.com")
		require.NoError(t, err, "processCustomActionsWorkflow should not return an error")
		data.Customization = updatedCustomization
		content, err := launcher.workflowContent(context.Background(), &data, workflowTemplate, nil)
		require.NoError(t, err, "workflowContent should not return an error")

		assert.Contains(t, content, "    permissions: \n      actions: read\n      attestations: read\n      checks: read\n      contents: read\n      deployments: write\n      discussions: read\n      issues: read\n      models: read\n      packages: read\n      pages: read\n      pull-requests: read\n      security-events: read\n      statuses: read\n", "permissions are incorrect")

		checkStepContent(t, content)
	})

	t.Run("Permissions read-all", func(t *testing.T) {
		const workflow = workflowPrefix + workflowPermissionsNone + workflowSteps
		data := workflowData{
			RunName:                     "Fixing issue #123",
			AgentDebug:                  true,
			AgentFirewallEnabledDefault: true,
			IsDevelopmentEnvironment:    true,
			MCPEnabled:                  true,
			Customization: map[string]template.HTML{
				"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
				"timeout-minutes": template.HTML("59"),
			},
		}
		opts := LaunchAgentOpts{
			CommitCount: 5,
			GitHubRepo:  "legit/repo",
			BranchName:  "legit-branch",
		}
		updatedCustomization, _, err := launcher.processSetupStepsWorkflow(context.Background(), workflow, data.Customization, &opts, "https://api.githubcopilot.com")
		require.NoError(t, err, "processCustomActionsWorkflow should not return an error")
		data.Customization = updatedCustomization
		content, err := launcher.workflowContent(context.Background(), &data, workflowTemplate, nil)
		require.NoError(t, err, "workflowContent should not return an error")

		assert.Contains(t, content, "    permissions: \n      deployments: write\n", "permissions are incorrect")

		checkStepContent(t, content)
	})

	t.Run("Just steps", func(t *testing.T) {
		const workflow = workflowPrefix + workflowSteps
		data := workflowData{
			RunName:                     "Fixing issue #123",
			AgentDebug:                  true,
			AgentFirewallEnabledDefault: true,
			IsDevelopmentEnvironment:    true,
			MCPEnabled:                  true,
			Customization: map[string]template.HTML{
				"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
				"timeout-minutes": template.HTML("59"),
			},
		}
		opts := LaunchAgentOpts{
			CommitCount: 5,
			GitHubRepo:  "legit/repo",
			BranchName:  "legit-branch",
		}
		updatedCustomization, _, err := launcher.processSetupStepsWorkflow(context.Background(), workflow, data.Customization, &opts, "https://api.githubcopilot.com")
		require.NoError(t, err, "processCustomActionsWorkflow should not return an error")
		data.Customization = updatedCustomization
		content, err := launcher.workflowContent(context.Background(), &data, workflowTemplate, nil)
		require.NoError(t, err, "workflowContent should not return an error")

		// Note permissions comes back alphabetically sorted, so the order may be different, and deployments write should be auto-added
		assert.NotContains(t, content, "    permissions: \n      contents: read\n      deployments: write\n      id-token: write", "permissions are incorrect")

		assert.Contains(t, content, "    runs-on: ${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}", "runs-on is incorrect")
		assert.NotContains(t, content, "custom-runner")

		assert.Contains(t, content, "timeout-minutes: 59", "timeout-minutes is incorrect")
		assert.Contains(t, content, "echo \"COPILOT_AGENT_TIMEOUT_MIN=59\" >> $GITHUB_ENV", "COPILOT_AGENT_TIMEOUT_MIN is incorrect")

		checkStepContent(t, content)
	})

	t.Run("Checkout has injected fetch-depth", func(t *testing.T) {
		data := workflowData{
			RunName:                     "Fixing issue #123",
			AgentDebug:                  true,
			AgentFirewallEnabledDefault: true,
			IsDevelopmentEnvironment:    true,
			MCPEnabled:                  true,
		}
		opts := LaunchAgentOpts{
			CommitCount: 5,
			GitHubRepo:  "legit/repo",
			BranchName:  "legit-branch",
		}
		// Check variations where the commit count should be copied into fetch-depth
		for _, checkoutStep := range checkoutCommitCountStepVariations {
			data.Customization = map[string]template.HTML{
				"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
				"timeout-minutes": template.HTML("59"),
			}
			workflow := workflowPrefix + checkoutStep
			updatedCustomization, _, err := launcher.processSetupStepsWorkflow(context.Background(), workflow, data.Customization, &opts, "https://api.githubcopilot.com")
			require.NoError(t, err, "processCustomActionsWorkflow should not return an error")
			data.Customization = updatedCustomization
			content, err := launcher.workflowContent(context.Background(), &data, workflowTemplate, nil)
			require.NoError(t, err, "workflowContent should not return an error")

			// Verify actions steps (now includes if condition from logging)
			assert.Contains(t, content, "      - if: ${{ env.SHOULD_CONTINUE == 'true' }}\n        uses: actions/checkout@v4\n        with:\n", "uses is incorrect")
			assert.Contains(t, content, "          persist-credentials: false", "persist-credentials is incorrect")
			// Actual depth should be the PR commit count +1 to get the commit before the PR was created
			assert.Contains(t, content, "          fetch-depth: 6", "fetch-depth is incorrect")

			// Check that other parts where set up correctly
			assert.Contains(t, content, "    runs-on: ${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}", "runs-on is incorrect")
			assert.Contains(t, content, "timeout-minutes: 59", "timeout-minutes is incorrect")
			assert.Contains(t, content, "echo \"COPILOT_AGENT_TIMEOUT_MIN=59\" >> $GITHUB_ENV", "COPILOT_AGENT_TIMEOUT_MIN is incorrect")
		}
	})

	t.Run("Checkout always has persist-credentials false", func(t *testing.T) {
		data := workflowData{
			RunName:                     "Fixing issue #123",
			AgentDebug:                  true,
			AgentFirewallEnabledDefault: true,
			IsDevelopmentEnvironment:    true,
			MCPEnabled:                  true,
		}
		opts := LaunchAgentOpts{
			CommitCount: 5,
			GitHubRepo:  "legit/repo",
			BranchName:  "legit-branch",
		}
		// Check variations where only persist credentials should be set
		for _, checkoutStep := range checkoutNoCommitCountStepVariations {
			data.Customization = map[string]template.HTML{
				"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
				"timeout-minutes": template.HTML("59"),
			}
			workflow := workflowPrefix + checkoutStep
			updatedCustomization, _, err := launcher.processSetupStepsWorkflow(context.Background(), workflow, data.Customization, &opts, "https://api.githubcopilot.com")
			require.NoError(t, err, "processCustomActionsWorkflow should not return an error")
			data.Customization = updatedCustomization
			content, err := launcher.workflowContent(context.Background(), &data, workflowTemplate, nil)
			require.NoError(t, err, "workflowContent should not return an error")

			// Verify actions steps (now includes if condition from logging)
			assert.Contains(t, content, "      - if: ${{ env.SHOULD_CONTINUE == 'true' }}\n        uses: actions/checkout@v4\n        with:\n", "uses is incorrect")
			assert.Contains(t, content, "          persist-credentials: false", "persist-credentials is incorrect")
			assert.NotContains(t, content, "          fetch-depth: 5", "fetch-depth is incorrect")

			// Check that other parts where set up correctly
			assert.Contains(t, content, "    runs-on: ${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}", "runs-on is incorrect")
			assert.Contains(t, content, "timeout-minutes: 59", "timeout-minutes is incorrect")
			assert.Contains(t, content, "echo \"COPILOT_AGENT_TIMEOUT_MIN=59\" >> $GITHUB_ENV", "COPILOT_AGENT_TIMEOUT_MIN is incorrect")
		}
	})

	t.Run("Checkout has other properties that are not affected", func(t *testing.T) {
		data := workflowData{
			RunName:                     "Fixing issue #123",
			AgentDebug:                  true,
			AgentFirewallEnabledDefault: true,
			IsDevelopmentEnvironment:    true,
			MCPEnabled:                  true,
			Customization: map[string]template.HTML{
				"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
				"timeout-minutes": template.HTML("59"),
			},
		}
		opts := LaunchAgentOpts{
			CommitCount: 5,
			GitHubRepo:  "legit/repo",
			BranchName:  "legit-branch",
		}
		workflow := workflowPrefix + checkoutOtherPropertiesUnaffected
		updatedCustomization, _, err := launcher.processSetupStepsWorkflow(context.Background(), workflow, data.Customization, &opts, "https://api.githubcopilot.com")
		require.NoError(t, err, "processCustomActionsWorkflow should not return an error")
		data.Customization = updatedCustomization
		content, err := launcher.workflowContent(context.Background(), &data, workflowTemplate, nil)
		require.NoError(t, err, "workflowContent should not return an error")

		// Verify properties are correct - but order can be different so check each individually (now includes if condition from logging)
		assert.Contains(t, content, "      - if: ${{ env.SHOULD_CONTINUE == 'true' }}\n        uses: actions/checkout@v4\n        with:\n", "uses is incorrect")
		assert.Contains(t, content, "          persist-credentials: false", "persist-credentials is incorrect")
		// Actual depth should be the PR commit count +1 to get the commit before the PR was created
		assert.Contains(t, content, "          fetch-depth: 6", "fetch-depth is incorrect")
		assert.Contains(t, content, "          token: sleep-token", "token is incorrect")
		assert.Contains(t, content, "          ssh-key: dont-ssh-me", "ssh-key is incorrect")
		assert.Contains(t, content, "          ssh-known-hosts: silent-host", "ssh-known-hosts is incorrect")
		assert.Contains(t, content, "          ssh-strict: false", "ssh-strict is incorrect")
		assert.Contains(t, content, "          path: /some/path", "path is incorrect")
		assert.Contains(t, content, "          clean: false", "clean is incorrect")
		assert.Contains(t, content, "          filter: is-a-band", "filter is incorrect")
		assert.Contains(t, content, "          sparse-checkout: some-folder", "sparse-checkout is incorrect")
		assert.Contains(t, content, "          sparse-checkout-cone-mode: false", "sparse-checkout-cone-mode is incorrect")
		assert.Contains(t, content, "          fetch-tags: true", "fetch-tags is incorrect")
		assert.Contains(t, content, "          show-progress: false", "show-progress is incorrect")
		assert.Contains(t, content, "          lfs: true", "lfs is incorrect")
		assert.Contains(t, content, "          submodules: true", "submodules is incorrect")
		assert.Contains(t, content, "          set-safe-directory: '*'", "set-safe-directory is incorrect")
		assert.Contains(t, content, "          github-server-url: https://github.localhost", "github-server-url is incorrect")

		// Check that other parts where set up correctly
		assert.Contains(t, content, "    runs-on: ${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}", "runs-on is incorrect")
		assert.Contains(t, content, "timeout-minutes: 59", "timeout-minutes is incorrect")
		assert.Contains(t, content, "echo \"COPILOT_AGENT_TIMEOUT_MIN=59\" >> $GITHUB_ENV", "COPILOT_AGENT_TIMEOUT_MIN is incorrect")
	})
}

func checkStepContent(t *testing.T, content string) {
	// Some variables should remain
	assert.Contains(t, content, "A: ${{ secrets.GITHUB_TOKEN }}")
	assert.Contains(t, content, "B: ${{ vars.COPILOT_AGENT_FIREWALL_ENABLED }}")
	assert.Contains(t, content, "C: ${{ vars.COPILOT_AGENT_FIREWALL_ALLOW_LIST}},${{ github.server_url }},${{ vars.COPILOT_AGENT_FIREWALL_ALLOW_LIST_ADDITIONS }}")
	assert.Contains(t, content, "D1: ${{ vars.COPILOT_AGENT_DEBUG }}")
	assert.Contains(t, content, "D2: ${{ env.COPILOT_AGENT_DEBUG }}")

	// Check variable, env, secret, and straight references
	varName := []string{
		"E", "F", "G", "H", "I1", "I2", "I3", "I4", "I5A", "I5B", "I5C", "I5D", "I5E", "I5F",
		"I5G", "I5H", "J1", "J2", "J3", "J4", "J5", "J6", "K", "L1", "L2", "L3", "M1", "M2", "N1", "N2", "N3", "N4",
	}
	for _, name := range varName {
		assert.Contains(t, content, fmt.Sprintf("%s: ${{ '' }}", name), "variable %s is not correct", name)
	}
	// The run statement should have the env var name filtered out
	assert.Contains(t, content, "run: |\n          echo \"Hello world!\"\n          echo \"I want to use ''\"\n          env", "step run is not correct")

	// But some of these secrets should appear later for the runtime
	assert.Contains(t, content, "GITHUB_COPILOT_API_TOKEN: \"${{ secrets.GITHUB_COPILOT_API_TOKEN }}\"")
	assert.Contains(t, content, "GITHUB_COPILOT_INTEGRATION_ID: \"${{ secrets.GITHUB_COPILOT_INTEGRATION_ID }}\"")
	assert.Contains(t, content, "COPILOT_INTEGRATION_ID_OVERRIDE: \"${{ secrets.COPILOT_INTEGRATION_ID_OVERRIDE }}\"")
	assert.Contains(t, content, "CAPI_HMAC_KEY_OVERRIDE: \"${{ secrets.CAPI_HMAC_KEY_OVERRIDE }}\"")
	assert.Contains(t, content, "GITHUB_COPILOT_ACTION_DOWNLOAD_URL: ${{ secrets.GITHUB_COPILOT_ACTION_DOWNLOAD_URL }}")

	// Check step formatting - however, the order may be different, so just check what comes after
	assert.Contains(t, content, "name: Output contents", "step name is not correct")
	assert.Contains(t, content, "env:\n          A:", "step env is not correct")
}

func TestEnvironmentVariablesOverride(t *testing.T) {
	// Test that override variables take precedence over variables from other sources
	t.Run("override variables take precedence", func(t *testing.T) {
		launcher := &ActionsLauncher{
			obsv:     observability.NewNoopExporters(),
			ffClient: featureflags.NewNoopClient(map[string]bool{}),
			opts: ActionsLauncherOpts{
				AgentLauncherOpts: AgentLauncherOpts{
					CopilotAPIURL:    "https://api.original.com",
					AgentCallbackURL: "https://callback.original.com",
					UploadsURL:       "https://uploads.github.com/user-attachments/assets",
					ModelOverride:    "",
					AgentDebug:       false,
					Environment:      "test",
					MCPEnabled:       false,
					AgentTimeoutMin:  60,
					RuntimeSHA:       "original-sha",
				},
			},
		}

		opts := LaunchAgentOpts{
			JobID:            "test-job-123",
			SessionID:        "test-session-456",
			ActorLogin:       "test-actor",
			ActorID:          12345,
			GitHubToken:      "original-token",
			GitHubRepo:       "test/repo",
			GitHubRepoOwner:  "test",
			GitHubRepoID:     67890,
			BranchName:       "main",
			Model:            "gpt-4",
			ProblemStatement: "Fix the bug",
			Action:           "fix-issue",
			Agent:            agenticapptest.NewTestCopilot(t),
		}

		// Create overrides that should take precedence
		overrides := &Variables{
			"COPILOT_AGENT_CALLBACK_URL": {Value: "https://callback.override.com"},
			"COPILOT_AGENT_JOB_ID":       {Value: "override-job-999"},
			"COPILOT_AGENT_MODEL":        {Value: "gpt-4-override"},
			"CUSTOM_OVERRIDE_VAR":        {Value: "custom-value"},
		}

		result, err := launcher.environmentVariables(context.Background(), &opts, overrides)
		require.NoError(t, err, "environmentVariables should not return an error")

		// Verify that the result contains the expected top-level inputs
		assert.Contains(t, result, "COPILOT_AGENT_INPUTS", "should contain COPILOT_AGENT_INPUTS")
		assert.Contains(t, result, "COPILOT_AGENT_ACTOR_ID", "should contain COPILOT_AGENT_ACTOR_ID")
		assert.Contains(t, result, "COPILOT_AGENT_RUNTIME_VERSION", "should contain COPILOT_AGENT_RUNTIME_VERSION")

		// Parse the COPILOT_AGENT_INPUTS JSON to check the actual variables
		inputsJSON := result["COPILOT_AGENT_INPUTS"]
		assert.NotEmpty(t, inputsJSON, "COPILOT_AGENT_INPUTS should not be empty")

		var inputs map[string]string
		err = json.Unmarshal([]byte(inputsJSON), &inputs)
		require.NoError(t, err, "should be able to unmarshal COPILOT_AGENT_INPUTS")

		// Test that override values take precedence
		assert.Equal(t, "https://callback.override.com", inputs["COPILOT_AGENT_CALLBACK_URL"],
			"COPILOT_AGENT_CALLBACK_URL should use override value")
		assert.Equal(t, "override-job-999", inputs["COPILOT_AGENT_JOB_ID"],
			"COPILOT_AGENT_JOB_ID should use override value")
		assert.Equal(t, "gpt-4-override", inputs["COPILOT_AGENT_MODEL"],
			"COPILOT_AGENT_MODEL should use override value")
		assert.Equal(t, "custom-value", inputs["CUSTOM_OVERRIDE_VAR"],
			"CUSTOM_OVERRIDE_VAR should be included from overrides")

		// Test that non-overridden values still come from original sources
		assert.Equal(t, "test-session-456", inputs["COPILOT_AGENT_SESSION_ID"],
			"COPILOT_AGENT_SESSION_ID should use original value")
		assert.Equal(t, "test-actor", inputs["COPILOT_AGENT_ACTOR"],
			"COPILOT_AGENT_ACTOR should use original value")
		assert.Equal(t, "12345", inputs["COPILOT_AGENT_ACTOR_ID"],
			"COPILOT_AGENT_ACTOR_ID should use original value")
		assert.Equal(t, "runtime-original-sha", inputs["COPILOT_AGENT_RUNTIME_VERSION"],
			"COPILOT_AGENT_RUNTIME_VERSION should use default format (feature flag disabled)")

		assert.Equal(t, "https://uploads.github.com/user-attachments/assets", inputs["GITHUB_UPLOADS_URL"],
			"top-level GITHUB_UPLOADS_URL should match")

		// Verify that the top-level COPILOT_AGENT_ACTOR_ID matches
		assert.Equal(t, "12345", result["COPILOT_AGENT_ACTOR_ID"],
			"top-level COPILOT_AGENT_ACTOR_ID should match")
		assert.Equal(t, "runtime-original-sha", result["COPILOT_AGENT_RUNTIME_VERSION"],
			"top-level COPILOT_AGENT_RUNTIME_VERSION should match")
	})

	t.Run("nil overrides should not cause errors", func(t *testing.T) {
		launcher := &ActionsLauncher{
			obsv:     observability.NewNoopExporters(),
			ffClient: featureflags.NewNoopClient(map[string]bool{}),
			opts: ActionsLauncherOpts{
				AgentLauncherOpts: AgentLauncherOpts{
					CopilotAPIURL:    "https://api.test.com",
					AgentCallbackURL: "https://callback.test.com",
					Environment:      "test",
				},
			},
		}

		opts := LaunchAgentOpts{
			JobID:     "test-job",
			SessionID: "test-session",
			ActorID:   123,
			Model:     "gpt-4",
			Agent:     agenticapptest.NewTestCopilot(t),
		}

		result, err := launcher.environmentVariables(context.Background(), &opts, nil)
		require.NoError(t, err, "environmentVariables should handle nil overrides")
		assert.Contains(t, result, "COPILOT_AGENT_INPUTS", "should still contain COPILOT_AGENT_INPUTS")
	})

	t.Run("empty overrides should not affect variables", func(t *testing.T) {
		launcher := &ActionsLauncher{
			obsv:     observability.NewNoopExporters(),
			ffClient: featureflags.NewNoopClient(map[string]bool{}),
			opts: ActionsLauncherOpts{
				AgentLauncherOpts: AgentLauncherOpts{
					CopilotAPIURL:    "https://api.test.com",
					AgentCallbackURL: "https://callback.test.com",
					Environment:      "test",
				},
			},
		}

		opts := LaunchAgentOpts{
			JobID:     "test-job-original",
			SessionID: "test-session",
			ActorID:   123,
			Model:     "gpt-4",
			Agent:     agenticapptest.NewTestCopilot(t),
		}

		emptyOverrides := &Variables{}

		result, err := launcher.environmentVariables(context.Background(), &opts, emptyOverrides)
		require.NoError(t, err, "environmentVariables should handle empty overrides")

		inputsJSON := result["COPILOT_AGENT_INPUTS"]
		var inputs map[string]string
		err = json.Unmarshal([]byte(inputsJSON), &inputs)
		require.NoError(t, err, "should be able to unmarshal COPILOT_AGENT_INPUTS")

		// Verify original values are preserved
		assert.Equal(t, "test-job-original", inputs["COPILOT_AGENT_JOB_ID"],
			"COPILOT_AGENT_JOB_ID should use original value when no override")
	})
}

func TestProblemStatementGzip(t *testing.T) {
	// Test that the problem statement is gzipped correctly.
	al := &ActionsLauncher{
		obsv: observability.NewNoopExporters(),
		ffClient: featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentGZipProblemStatement: true,
		}),
	} // Don't need many env vars
	ps := strings.Repeat("This is a test problem statement that should be gzipped correctly. ", 10000)
	opts := LaunchAgentOpts{
		SessionID:        "i-should-not-be-gzipped",
		ProblemStatement: ps,
		Agent:            agenticapptest.NewTestCopilot(t),
	}
	vars, err := al.environmentVariables(context.Background(), &opts, nil)
	require.NoError(t, err)
	assert.NotEmpty(t, vars)
	assert.Contains(t, vars, "COPILOT_AGENT_INPUTS")

	// Expected compressed length is 4027 instead of the giant 894196 base64 encoded string.
	// (Note: includes 6 extra chars for runtime version "latest" vs empty string in original code)
	assert.Len(t, vars["COPILOT_AGENT_INPUTS"], 4027)

	// Make sure the prompt has a "gz:" prefix
	assert.Contains(t, vars["COPILOT_AGENT_INPUTS"], "COPILOT_AGENT_PROMPT\":\"gz:")
	// Make sure not everything is gzipped
	assert.Contains(t, vars["COPILOT_AGENT_INPUTS"], "COPILOT_AGENT_SESSION_ID\":\"i-should-not-be-gzipped")
}

func TestProblemStatementWithoutGzip(t *testing.T) {
	// Test that the problem statement is gzipped correctly.
	al := &ActionsLauncher{
		obsv: observability.NewNoopExporters(),
		ffClient: featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentGZipProblemStatement: false,
		}),
	} // Don't need many env vars
	ps := strings.Repeat("This is a test problem statement that should be gzipped correctly. ", 10000)
	opts := LaunchAgentOpts{
		SessionID:        "i-should-not-be-gzipped",
		ProblemStatement: ps,
		Agent:            agenticapptest.NewTestCopilot(t),
	}
	vars, err := al.environmentVariables(context.Background(), &opts, nil)
	require.NoError(t, err)
	assert.NotEmpty(t, vars)
	assert.Contains(t, vars, "COPILOT_AGENT_INPUTS")

	// The problem statement here is giant, so the total length is BIG.
	// (Note: includes 6 extra chars for runtime version "latest" vs empty string in original code)
	assert.Len(t, vars["COPILOT_AGENT_INPUTS"], 894196)

	// Make sure the prompt does not have a prefix
	assert.NotContains(t, vars["COPILOT_AGENT_INPUTS"], "COPILOT_AGENT_PROMPT\":\"gz:")
	assert.Contains(t, vars["COPILOT_AGENT_INPUTS"], "COPILOT_AGENT_PROMPT\":\"")
	// Make sure not everything is gzipped
	assert.Contains(t, vars["COPILOT_AGENT_INPUTS"], "COPILOT_AGENT_SESSION_ID\":\"i-should-not-be-gzipped")
}

func TestGetURLsForEnvironment(t *testing.T) {
	tests := []struct {
		name                      string
		environment               config.Environment
		environmentName           string
		copilotAPIURL             string
		agentCallbackURL          string
		tenantSlug                string
		expectError               bool
		expectedCopilotAPIURL     string
		expectedActionDownloadURL string
		expectedAgentCallbackURL  string
		expectedUploadURL         string
		expectedDownloadURL       string
		expectedSecretScanningURL string
	}{
		{
			name:                      "staging environment",
			environment:               config.EnvironmentStaging,
			environmentName:           "staging",
			copilotAPIURL:             "https://api.githubcopilot.com",
			agentCallbackURL:          "https://callback.example.com",
			tenantSlug:                "",
			expectError:               false,
			expectedCopilotAPIURL:     "https://api.githubcopilot.com",
			expectedActionDownloadURL: "https://api.githubcopilot.com/agents/swe-staging/runtime",
			expectedAgentCallbackURL:  "https://api.githubcopilot.com/agents/swe-staging/agent",
			expectedUploadURL:         "https://uploads.github.com/user-attachments/assets",
			expectedDownloadURL:       "https://api.githubcopilot.com/agents/swe-staging/runtime",
			expectedSecretScanningURL: "https://scanning-api.github.com/api/v1/scan/multipart",
		},
		{
			name:                      "sith lord staging environment",
			environment:               config.EnvironmentStaging,
			environmentName:           "staging-sith-lord",
			copilotAPIURL:             "https://api.githubcopilot.com",
			agentCallbackURL:          "https://callback.example.com",
			tenantSlug:                "",
			expectError:               false,
			expectedCopilotAPIURL:     "https://api.githubcopilot.com",
			expectedActionDownloadURL: "https://api.githubcopilot.com/agents/swe-staging-sith-lord/runtime",
			expectedAgentCallbackURL:  "https://api.githubcopilot.com/agents/swe-staging-sith-lord/agent",
			expectedSecretScanningURL: "https://scanning-api.github.com/api/v1/scan/multipart",
		},
		{
			name:                      "jedi knight staging environment",
			environment:               config.EnvironmentStaging,
			environmentName:           "staging-jedi-knight",
			copilotAPIURL:             "https://api.githubcopilot.com",
			agentCallbackURL:          "https://callback.example.com",
			tenantSlug:                "",
			expectError:               false,
			expectedCopilotAPIURL:     "https://api.githubcopilot.com",
			expectedActionDownloadURL: "https://api.githubcopilot.com/agents/swe-staging-jedi-knight/runtime",
			expectedAgentCallbackURL:  "https://api.githubcopilot.com/agents/swe-staging-jedi-knight/agent",
			expectedSecretScanningURL: "https://scanning-api.github.com/api/v1/scan/multipart",
		},
		{
			name:                      "proxima environment with tenant",
			environment:               config.EnvironmentProxima,
			copilotAPIURL:             "https://api.<tenant>.github.com",
			agentCallbackURL:          "https://callback.<tenant>.example.com",
			tenantSlug:                "test-org",
			expectError:               false,
			expectedCopilotAPIURL:     "https://api.test-org.github.com",
			expectedActionDownloadURL: "https://api.test-org.github.com/agents/swe/runtime",
			expectedAgentCallbackURL:  "https://callback.test-org.example.com",
			expectedUploadURL:         "https://uploads.test-org.ghe.com/",
			expectedDownloadURL:       "https://api.test-org.github.com/agents/swe/runtime",
			expectedSecretScanningURL: "https://scanning-api.test-org.ghe.com/api/v1/scan/multipart",
		},
		{
			name:                      "proxima environment without tenant placeholder",
			environment:               config.EnvironmentProxima,
			copilotAPIURL:             "https://api.github.com",
			agentCallbackURL:          "https://callback.example.com",
			tenantSlug:                "test-org",
			expectError:               false,
			expectedCopilotAPIURL:     "https://api.github.com",
			expectedActionDownloadURL: "https://api.github.com/agents/swe/runtime",
			expectedAgentCallbackURL:  "https://callback.example.com",
			expectedUploadURL:         "https://uploads.github.com/user-attachments/assets",
			expectedDownloadURL:       "https://api.github.com/agents/swe/runtime",
			expectedSecretScanningURL: "https://scanning-api.github.com/api/v1/scan/multipart",
		},
		{
			name:                      "proxima environment with missing tenant slug",
			environment:               config.EnvironmentProxima,
			copilotAPIURL:             "https://api.<tenant>.github.com",
			agentCallbackURL:          "https://callback.example.com",
			tenantSlug:                "",
			expectError:               true,
			expectedCopilotAPIURL:     "",
			expectedActionDownloadURL: "",
			expectedAgentCallbackURL:  "",
			expectedUploadURL:         "",
			expectedDownloadURL:       "",
			expectedSecretScanningURL: "",
		},
		{
			name:                      "proxima environment with agent callback URL tenant placeholder and missing tenant slug",
			environment:               config.EnvironmentProxima,
			copilotAPIURL:             "https://api.github.com",
			agentCallbackURL:          "https://callback.<tenant>.example.com",
			tenantSlug:                "",
			expectError:               true,
			expectedCopilotAPIURL:     "",
			expectedActionDownloadURL: "",
			expectedAgentCallbackURL:  "",
			expectedUploadURL:         "",
			expectedDownloadURL:       "",
			expectedSecretScanningURL: "",
		},
		{
			name:                      "development environment that uses callback URL",
			environment:               config.EnvironmentDevelopment,
			copilotAPIURL:             "https://api.githubcopilot.com",
			agentCallbackURL:          "https://callback.example.com",
			tenantSlug:                "",
			expectError:               false,
			expectedCopilotAPIURL:     "https://api.githubcopilot.com",
			expectedActionDownloadURL: "",
			expectedAgentCallbackURL:  "https://callback.example.com",
			expectedUploadURL:         "https://uploads.github.com/user-attachments/assets",
			expectedDownloadURL:       "",
			expectedSecretScanningURL: "https://scanning-api.github.com/api/v1/scan/multipart",
		},
		{
			name:                      "production environment (default case)",
			environment:               config.EnvironmentProduction,
			copilotAPIURL:             "https://api.githubcopilot.com",
			agentCallbackURL:          "https://callback.example.com",
			tenantSlug:                "",
			expectError:               false,
			expectedCopilotAPIURL:     "https://api.githubcopilot.com",
			expectedActionDownloadURL: "",
			expectedAgentCallbackURL:  "https://api.githubcopilot.com/agents/swe/agent",
			expectedUploadURL:         "https://uploads.github.com/user-attachments/assets",
			expectedDownloadURL:       "",
			expectedSecretScanningURL: "https://scanning-api.github.com/api/v1/scan/multipart",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := context.Background()

			// Set up tenant slug in context if provided
			if tt.tenantSlug != "" {
				ctx = requestctx.AddData(ctx, &requestctx.CtxData{})
				err := requestctx.AddTenantSlug(ctx, tt.tenantSlug)
				require.NoError(t, err)
			}

			// Create ActionsLauncher with test options
			launcher := &ActionsLauncher{
				ffClient: featureflags.NewNoopClient(map[string]bool{}),
				obsv:     observability.NewNoopExporters(),
				opts: ActionsLauncherOpts{
					AgentLauncherOpts: AgentLauncherOpts{
						CopilotAPIURL:     tt.copilotAPIURL,
						AgentCallbackURL:  tt.agentCallbackURL,
						UploadsURL:        tt.expectedUploadURL,
						DownloadsURL:      tt.expectedDownloadURL,
						SecretScanningURL: tt.expectedSecretScanningURL,
					},
				},
			}

			// Call the method under test

			urls, err := launcher.getURLsForEnvironment(ctx, tt.environment, tt.environmentName, 123)

			// Assert error expectation
			if tt.expectError {
				require.Error(t, err)
				assert.Empty(t, urls.CopilotAPIURL)
				assert.Empty(t, urls.ActionDownloadURL)
				assert.Empty(t, urls.AgentCallbackURL)
				assert.Empty(t, urls.UploadURL)
				assert.Empty(t, urls.DownloadURL)
				assert.Empty(t, urls.SecretScanningURL)
			} else {
				require.NoError(t, err)
				assert.Equal(t, tt.expectedCopilotAPIURL, urls.CopilotAPIURL)
				assert.Equal(t, tt.expectedActionDownloadURL, urls.ActionDownloadURL)
				assert.Equal(t, tt.expectedAgentCallbackURL, urls.AgentCallbackURL)
				assert.Equal(t, tt.expectedUploadURL, urls.UploadURL)
				assert.Equal(t, tt.expectedDownloadURL, urls.DownloadURL)
				assert.Equal(t, tt.expectedSecretScanningURL, urls.SecretScanningURL)
			}
		})
	}
}

func TestGetURLsForEnvironment_SubscriptionBased(t *testing.T) {
	tests := []struct {
		name                      string
		environment               config.Environment
		environmentName           string
		copilotAPIURL             string
		actorID                   int64
		featureFlagEnabled        bool
		mockCopilotPlan           string // Will be mapped to githubtwirp.CopilotPlan
		expectedCopilotAPIURL     string
		expectedCopilotAPIHost    string
		expectedActionDownloadURL string
		expectedAgentCallbackURL  string
	}{
		{
			name:                      "Business plan with feature flag enabled",
			environment:               config.EnvironmentProduction,
			environmentName:           "production",
			copilotAPIURL:             "https://api.githubcopilot.com",
			actorID:                   123,
			featureFlagEnabled:        true,
			mockCopilotPlan:           "COPILOT_PLAN_BUSINESS",
			expectedCopilotAPIURL:     "https://api.business.githubcopilot.com",
			expectedCopilotAPIHost:    "api.business.githubcopilot.com",
			expectedActionDownloadURL: "",
			expectedAgentCallbackURL:  "https://api.business.githubcopilot.com/agents/swe/agent",
		},
		{
			name:                      "Enterprise plan with feature flag enabled",
			environment:               config.EnvironmentProduction,
			environmentName:           "production",
			copilotAPIURL:             "https://api.githubcopilot.com",
			actorID:                   456,
			featureFlagEnabled:        true,
			mockCopilotPlan:           "COPILOT_PLAN_ENTERPRISE",
			expectedCopilotAPIURL:     "https://api.enterprise.githubcopilot.com",
			expectedCopilotAPIHost:    "api.enterprise.githubcopilot.com",
			expectedActionDownloadURL: "",
			expectedAgentCallbackURL:  "https://api.enterprise.githubcopilot.com/agents/swe/agent",
		},
		{
			name:                      "Individual plan with feature flag enabled",
			environment:               config.EnvironmentProduction,
			environmentName:           "production",
			copilotAPIURL:             "https://api.githubcopilot.com",
			actorID:                   789,
			featureFlagEnabled:        true,
			mockCopilotPlan:           "COPILOT_PLAN_INDIVIDUAL",
			expectedCopilotAPIURL:     "https://api.individual.githubcopilot.com",
			expectedCopilotAPIHost:    "api.individual.githubcopilot.com",
			expectedActionDownloadURL: "",
			expectedAgentCallbackURL:  "https://api.individual.githubcopilot.com/agents/swe/agent",
		},
		{
			name:                      "Individual Pro Plus plan with feature flag enabled",
			environment:               config.EnvironmentProduction,
			environmentName:           "production",
			copilotAPIURL:             "https://api.githubcopilot.com",
			actorID:                   101112,
			featureFlagEnabled:        true,
			mockCopilotPlan:           "COPILOT_PLAN_INDIVIDUAL_PRO",
			expectedCopilotAPIURL:     "https://api.individual.githubcopilot.com",
			expectedCopilotAPIHost:    "api.individual.githubcopilot.com",
			expectedActionDownloadURL: "",
			expectedAgentCallbackURL:  "https://api.individual.githubcopilot.com/agents/swe/agent",
		},
		{
			name:                      "Business plan with feature flag disabled",
			environment:               config.EnvironmentProduction,
			environmentName:           "production",
			copilotAPIURL:             "https://api.githubcopilot.com",
			actorID:                   131415,
			featureFlagEnabled:        false,
			mockCopilotPlan:           "COPILOT_PLAN_BUSINESS",
			expectedCopilotAPIURL:     "https://api.githubcopilot.com",
			expectedCopilotAPIHost:    "api.githubcopilot.com",
			expectedActionDownloadURL: "",
			expectedAgentCallbackURL:  "https://api.githubcopilot.com/agents/swe/agent",
		},
		{
			name:                      "Business plan with staging environment and feature flag enabled",
			environment:               config.EnvironmentStaging,
			environmentName:           "staging",
			copilotAPIURL:             "https://api.githubcopilot.com",
			actorID:                   161718,
			featureFlagEnabled:        true,
			mockCopilotPlan:           "COPILOT_PLAN_BUSINESS",
			expectedCopilotAPIURL:     "https://api.business.githubcopilot.com",
			expectedCopilotAPIHost:    "api.business.githubcopilot.com",
			expectedActionDownloadURL: "https://api.business.githubcopilot.com/agents/swe-staging/runtime",
			expectedAgentCallbackURL:  "https://api.business.githubcopilot.com/agents/swe-staging/agent",
		},
		{
			name:                      "Enterprise plan with staging environment and feature flag enabled",
			environment:               config.EnvironmentStaging,
			environmentName:           "staging",
			copilotAPIURL:             "https://api.githubcopilot.com",
			actorID:                   192021,
			featureFlagEnabled:        true,
			mockCopilotPlan:           "COPILOT_PLAN_ENTERPRISE",
			expectedCopilotAPIURL:     "https://api.enterprise.githubcopilot.com",
			expectedCopilotAPIHost:    "api.enterprise.githubcopilot.com",
			expectedActionDownloadURL: "https://api.enterprise.githubcopilot.com/agents/swe-staging/runtime",
			expectedAgentCallbackURL:  "https://api.enterprise.githubcopilot.com/agents/swe-staging/agent",
		},
		{
			name:                      "Business plan with development environment - feature flag not applied",
			environment:               config.EnvironmentDevelopment,
			environmentName:           "development",
			copilotAPIURL:             "https://api.githubcopilot.com",
			actorID:                   222324,
			featureFlagEnabled:        true, // Feature flag enabled but not applied to development
			mockCopilotPlan:           "COPILOT_PLAN_BUSINESS",
			expectedCopilotAPIURL:     "https://api.githubcopilot.com",
			expectedCopilotAPIHost:    "api.githubcopilot.com",
			expectedActionDownloadURL: "",
			expectedAgentCallbackURL:  "https://api.githubcopilot.com/agents/swe/agent",
		},
		{
			name:                      "Empty ApiHost falls back to default URL",
			environment:               config.EnvironmentProduction,
			environmentName:           "production",
			copilotAPIURL:             "https://api.githubcopilot.com",
			actorID:                   252627,
			featureFlagEnabled:        true,
			mockCopilotPlan:           "COPILOT_PLAN_EMPTY_API_HOST", // Special case for empty ApiHost
			expectedCopilotAPIURL:     "https://api.githubcopilot.com",
			expectedCopilotAPIHost:    "api.githubcopilot.com",
			expectedActionDownloadURL: "",
			expectedAgentCallbackURL:  "https://api.githubcopilot.com/agents/swe/agent",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := context.Background()

			// Create a mock feature flag client
			ffFlags := map[string]bool{}
			if tt.featureFlagEnabled {
				ffFlags[featureflags.CopilotSWESubscriptionBasedCapiURL] = true
			}
			ffClient := featureflags.NewNoopClient(ffFlags)

			// Create a mock Twirp client that returns the specified plan with Skuisolation.ApiHost
			mockTwirp := githubtwirp.NewNoopClient()
			mockTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
				var plan copilotUsersTwirp.CopilotPlan
				var apiHost string
				switch tt.mockCopilotPlan {
				case "COPILOT_PLAN_BUSINESS":
					plan = copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS
					apiHost = "api.business.githubcopilot.com"
				case "COPILOT_PLAN_ENTERPRISE":
					plan = copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE
					apiHost = "api.enterprise.githubcopilot.com"
				case "COPILOT_PLAN_INDIVIDUAL":
					plan = copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL
					apiHost = "api.individual.githubcopilot.com"
				case "COPILOT_PLAN_INDIVIDUAL_PRO":
					plan = copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL_PRO
					apiHost = "api.individual.githubcopilot.com"
				case "COPILOT_PLAN_EMPTY_API_HOST":
					// Test case for empty ApiHost - should fall back to default URL
					plan = copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS
					apiHost = "" // Empty ApiHost to test fallback
				default:
					plan = copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INVALID
					apiHost = "api.githubcopilot.com"
				}

				userDetails := &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan:      plan,
					HasPaidAccess:    true,
					HasFreeAccess:    false,
					HasLimitedAccess: false,
				}

				// Only add Skuisolation if apiHost is not empty (to test nil handling)
				if apiHost != "" {
					userDetails.Skuisolation = &copilotUsersTwirp.SKUIsolation{
						ApiHost: apiHost,
					}
				}

				return &copilotUsersTwirp.GetCopilotUserResponse{
					UserDetails: userDetails,
				}, nil
			}

			// Create ActionsLauncher with test options
			launcher := &ActionsLauncher{
				ffClient: ffClient,
				ghTwirp:  mockTwirp,
				obsv:     observability.NewNoopExporters(),
				opts: ActionsLauncherOpts{
					AgentLauncherOpts: AgentLauncherOpts{
						CopilotAPIURL:     tt.copilotAPIURL,
						UploadsURL:        "https://uploads.github.com/user-attachments/assets",
						DownloadsURL:      "https://downloads.github.com",
						SecretScanningURL: "https://scanning-api.github.com/api/v1/scan/multipart",
					},
				},
			}

			// Call the method under test
			urls, err := launcher.getURLsForEnvironment(ctx, tt.environment, tt.environmentName, tt.actorID)

			// Assert no error
			require.NoError(t, err)
			assert.Equal(t, tt.expectedCopilotAPIURL, urls.CopilotAPIURL)
			assert.Equal(t, tt.expectedCopilotAPIHost, urls.CopilotAPIHost)
			if tt.expectedActionDownloadURL != "" {
				assert.Equal(t, tt.expectedActionDownloadURL, urls.ActionDownloadURL)
			}
			assert.Equal(t, tt.expectedAgentCallbackURL, urls.AgentCallbackURL)
			assert.Equal(t, "https://uploads.github.com/user-attachments/assets", urls.UploadURL)
			assert.NotEmpty(t, urls.DownloadURL)
			assert.NotEmpty(t, urls.SecretScanningURL)
		})
	}
}

func TestReplaceFirewallTenantPlaceholders(t *testing.T) {
	tests := []struct {
		name                           string
		agentFirewallRequiredAllowList string
		tenantSlug                     string
		expectedRequiredAllowList      string
		expectError                    bool
		expectedErrorMsg               string
	}{
		{
			name:                           "successful replacement",
			agentFirewallRequiredAllowList: "required.<tenant>.com",
			tenantSlug:                     "test-tenant",
			expectedRequiredAllowList:      "required.test-tenant.com",
			expectError:                    false,
		},
		{
			name:                           "URL encoded placeholders",
			agentFirewallRequiredAllowList: "required.%3Ctenant%3E.com",
			tenantSlug:                     "test-tenant",
			expectedRequiredAllowList:      "required.test-tenant.com",
			expectError:                    false,
		},
		{
			name:                           "no placeholders",
			agentFirewallRequiredAllowList: "required.github.com",
			tenantSlug:                     "test-tenant",
			expectedRequiredAllowList:      "required.github.com",
			expectError:                    false,
		},
		{
			name:                           "placeholder but no tenant",
			agentFirewallRequiredAllowList: "<tenant>.required.com",
			tenantSlug:                     "",
			expectedRequiredAllowList:      "",
			expectError:                    true,
			expectedErrorMsg:               "failed to replace tenant placeholder in agent firewall",
		},
		{
			name:                           "error in required allow list",
			agentFirewallRequiredAllowList: "required.<tenant>.com",
			tenantSlug:                     "",
			expectedRequiredAllowList:      "",
			expectError:                    true,
			expectedErrorMsg:               "failed to replace tenant placeholder in agent firewall required allow list",
		},
		{
			name:                           "multiple placeholders",
			agentFirewallRequiredAllowList: "<tenant>.required.com,secure.<tenant>.net",
			tenantSlug:                     "my-org",
			expectedRequiredAllowList:      "my-org.required.com,secure.my-org.net",
			expectError:                    false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Set up context with tenant slug if provided
			ctx := context.Background()
			if tt.tenantSlug != "" {
				ctx = requestctx.AddData(ctx, &requestctx.CtxData{
					TenantSlug: tt.tenantSlug,
				})
			} else {
				// Add data but leave tenant slug empty
				ctx = requestctx.AddData(ctx, &requestctx.CtxData{})
			}

			// Create input opts
			opts := ActionsLauncherOpts{
				AgentLauncherOpts: AgentLauncherOpts{
					AgentFirewallRequiredAllowList: tt.agentFirewallRequiredAllowList,
				},
			}

			// Call the function under test
			result, err := replaceFirewallTenantPlaceholders(ctx, opts.AgentFirewallRequiredAllowList)

			// Assert results
			if tt.expectError {
				require.Error(t, err)
				assert.Contains(t, err.Error(), tt.expectedErrorMsg)
			} else {
				require.NoError(t, err)
				assert.Equal(t, tt.expectedRequiredAllowList, result)
			}
		})
	}
}

func TestReplaceFirewallRepoPlaceholders(t *testing.T) {
	tests := []struct {
		name                           string
		agentFirewallRequiredAllowList string
		repoOwner                      string
		repoName                       string
		expectedRequiredAllowList      string
	}{
		{
			name:                           "successful replacement",
			agentFirewallRequiredAllowList: "https://api.github.com/repos/{{repo_owner}}/{{repo_name}}/copilot_internal/",
			repoOwner:                      "github",
			repoName:                       "sweagentd",
			expectedRequiredAllowList:      "https://api.github.com/repos/github/sweagentd/copilot_internal/",
		},
		{
			name:                           "multiple placeholders",
			agentFirewallRequiredAllowList: "https://api.github.com/repos/{{repo_owner}}/{{repo_name}}/copilot_internal/,https://example.com/{{repo_owner}}/{{repo_name}}/data",
			repoOwner:                      "test-org",
			repoName:                       "test-repo",
			expectedRequiredAllowList:      "https://api.github.com/repos/test-org/test-repo/copilot_internal/,https://example.com/test-org/test-repo/data",
		},
		{
			name:                           "no placeholders",
			agentFirewallRequiredAllowList: "https://api.github.com/advisories",
			repoOwner:                      "github",
			repoName:                       "sweagentd",
			expectedRequiredAllowList:      "https://api.github.com/advisories",
		},
		{
			name:                           "empty repo values",
			agentFirewallRequiredAllowList: "https://api.github.com/repos/{{repo_owner}}/{{repo_name}}/copilot_internal/",
			repoOwner:                      "",
			repoName:                       "",
			expectedRequiredAllowList:      "https://api.github.com/repos///copilot_internal/",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := replaceFirewallRepoPlaceholders(tt.agentFirewallRequiredAllowList, tt.repoOwner, tt.repoName)
			assert.Equal(t, tt.expectedRequiredAllowList, result)
		})
	}
}

func TestLaunchAgent_FirewallAllowListIncludesCopilotAPIHost(t *testing.T) {
	tests := []struct {
		name                      string
		featureFlagEnabled        bool
		mockCopilotPlan           string
		baseFirewallAllowList     string
		expectedFirewallAllowList string // substring to look for in the workflow
	}{
		{
			name:                      "Business plan includes subscription-based host in firewall allow list",
			featureFlagEnabled:        true,
			mockCopilotPlan:           "COPILOT_PLAN_BUSINESS",
			baseFirewallAllowList:     "api.githubcopilot.com,uploads.github.com",
			expectedFirewallAllowList: "api.githubcopilot.com,uploads.github.com,api.business.githubcopilot.com",
		},
		{
			name:                      "Enterprise plan includes subscription-based host in firewall allow list",
			featureFlagEnabled:        true,
			mockCopilotPlan:           "COPILOT_PLAN_ENTERPRISE",
			baseFirewallAllowList:     "api.githubcopilot.com",
			expectedFirewallAllowList: "api.githubcopilot.com,api.enterprise.githubcopilot.com",
		},
		{
			name:                      "Feature flag disabled uses default host parsed from URL",
			featureFlagEnabled:        false,
			mockCopilotPlan:           "COPILOT_PLAN_BUSINESS",
			baseFirewallAllowList:     "uploads.github.com",
			expectedFirewallAllowList: "uploads.github.com,api.githubcopilot.com",
		},
		{
			name:                      "Empty base allow list only includes CopilotAPIHost without leading comma",
			featureFlagEnabled:        true,
			mockCopilotPlan:           "COPILOT_PLAN_BUSINESS",
			baseFirewallAllowList:     "",
			expectedFirewallAllowList: "api.business.githubcopilot.com",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := context.Background()

			// Set up feature flags
			ffFlags := map[string]bool{}
			if tt.featureFlagEnabled {
				ffFlags[featureflags.CopilotSWESubscriptionBasedCapiURL] = true
			}
			ffClient := featureflags.NewNoopClient(ffFlags)

			// Create mock Twirp client
			mockTwirp := githubtwirp.NewNoopClient()
			mockTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
				var plan copilotUsersTwirp.CopilotPlan
				var apiHost string
				switch tt.mockCopilotPlan {
				case "COPILOT_PLAN_BUSINESS":
					plan = copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS
					apiHost = "api.business.githubcopilot.com"
				case "COPILOT_PLAN_ENTERPRISE":
					plan = copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE
					apiHost = "api.enterprise.githubcopilot.com"
				default:
					plan = copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL
					apiHost = "api.individual.githubcopilot.com"
				}

				return &copilotUsersTwirp.GetCopilotUserResponse{
					UserDetails: &copilotUsersTwirp.CopilotUserDetails{
						CopilotPlan:   plan,
						HasPaidAccess: true,
						Skuisolation: &copilotUsersTwirp.SKUIsolation{
							ApiHost: apiHost,
						},
					},
				}, nil
			}
			mockTwirp.NoopSweagentdAPI.MockMCPConfigurationForRepository = func(ctx context.Context, req *sweagentdTwirp.MCPConfigurationForRepositoryRequest) (*sweagentdTwirp.MCPConfigurationForRepositoryResponse, error) {
				return &sweagentdTwirp.MCPConfigurationForRepositoryResponse{
					McpConfigurationJson: "{}",
					IsMcpEnabled:         false,
				}, nil
			}

			// Create mock GitHub client factory that captures the workflow
			noopClient := &github.NoopClient{
				GithubAppLogin: "copilot-swe-agent",
				GithubBotLogin: "copilot-swe-agent[bot]",
			}
			clientFactory := &github.NoopClientFactory{
				GitHubAppLogin: "copilot-swe-agent",
				GitHubBotLogin: "copilot-swe-agent[bot]",
				MockNewClient: func(token string) github.ClientInterface {
					return noopClient
				},
			}

			// Create the launcher
			launcher := &ActionsLauncher{
				obsv:                observability.NewNoopExporters(),
				ffClient:            ffClient,
				githubClientFactory: clientFactory,
				ghTwirp:             mockTwirp,
				spokes:              spokestest.NewClient(t),
				appProvider:         agenticapptest.NewTestProvider(t),
				opts: ActionsLauncherOpts{
					ActionsDefaultRunsOnLabels: "ubuntu-latest",
					AgentLauncherOpts: AgentLauncherOpts{
						CopilotAPIURL:                  "https://api.githubcopilot.com",
						AgentCallbackURL:               "https://api.githubcopilot.com/agents/swe/agent",
						UploadsURL:                     "https://uploads.github.com/user-attachments/assets",
						DownloadsURL:                   "https://downloads.github.com",
						SecretScanningURL:              "https://scanning-api.github.com/api/v1/scan/multipart",
						AgentFirewallRequiredAllowList: tt.baseFirewallAllowList,
						Environment:                    "production",
						AgentTimeoutMin:                60,
					},
				},
			}

			// Create launch options
			opts := &LaunchAgentOpts{
				JobID:             "test-job-123",
				SessionID:         "test-session-456",
				ActorLogin:        "test-actor",
				ActorID:           12345,
				GitHubToken:       "test-token",
				GitHubRepo:        "test/repo",
				GitHubRepoOwner:   "test",
				GitHubRepoName:    "repo",
				GitHubRepoID:      67890,
				GitHubRepoOwnerID: 11111,
				BranchName:        "test-branch",
				Agent:             agenticapptest.NewTestProvider(t).CopilotApp(),
			}

			// Call LaunchAgent
			_, err := launcher.LaunchAgent(ctx, opts)
			require.NoError(t, err)

			// Find the CreateDynamicWorkflowRun call
			var workflowContent string
			for _, call := range noopClient.MethodCalls {
				if call.Method == "CreateDynamicWorkflowRun" {
					workflowOpts := call.Args[4].(*github.NewDynamicWorkflowRun)
					workflowContent = *workflowOpts.Workflow
					break
				}
			}

			require.NotEmpty(t, workflowContent, "CreateDynamicWorkflowRun should have been called with workflow content")

			// Verify the firewall allow list contains the expected hosts
			assert.Contains(t, workflowContent, tt.expectedFirewallAllowList,
				"Workflow should contain the expected firewall allow list with CopilotAPIHost")
		})
	}
}

func TestLaunchAgent_RepoPlaceholdersReplaced(t *testing.T) {
	ctx := context.Background()

	// Create mock Twirp client
	mockTwirp := githubtwirp.NewNoopClient()
	mockTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
		return &copilotUsersTwirp.GetCopilotUserResponse{
			UserDetails: &copilotUsersTwirp.CopilotUserDetails{
				CopilotPlan:   copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
				HasPaidAccess: true,
			},
		}, nil
	}
	mockTwirp.NoopSweagentdAPI.MockMCPConfigurationForRepository = func(ctx context.Context, req *sweagentdTwirp.MCPConfigurationForRepositoryRequest) (*sweagentdTwirp.MCPConfigurationForRepositoryResponse, error) {
		return &sweagentdTwirp.MCPConfigurationForRepositoryResponse{
			McpConfigurationJson: "{}",
			IsMcpEnabled:         false,
		}, nil
	}

	// Create mock GitHub client factory
	noopClient := &github.NoopClient{
		GithubAppLogin: "copilot-swe-agent",
		GithubBotLogin: "copilot-swe-agent[bot]",
	}
	clientFactory := &github.NoopClientFactory{
		GitHubAppLogin: "copilot-swe-agent",
		GitHubBotLogin: "copilot-swe-agent[bot]",
		MockNewClient: func(token string) github.ClientInterface {
			return noopClient
		},
	}

	// Create the launcher with repo placeholders in the allowlist
	launcher := &ActionsLauncher{
		obsv:                observability.NewNoopExporters(),
		ffClient:            featureflags.NewNoopClient(map[string]bool{}),
		githubClientFactory: clientFactory,
		ghTwirp:             mockTwirp,
		spokes:              spokestest.NewClient(t),
		appProvider:         agenticapptest.NewTestProvider(t),
		opts: ActionsLauncherOpts{
			ActionsDefaultRunsOnLabels: "ubuntu-latest",
			AgentLauncherOpts: AgentLauncherOpts{
				CopilotAPIURL:                  "https://api.githubcopilot.com",
				AgentCallbackURL:               "https://api.githubcopilot.com/agents/swe/agent",
				UploadsURL:                     "https://uploads.github.com/user-attachments/assets",
				DownloadsURL:                   "https://downloads.github.com",
				SecretScanningURL:              "https://scanning-api.github.com/api/v1/scan/multipart",
				AgentFirewallRequiredAllowList: "https://api.github.com/repos/{{repo_owner}}/{{repo_name}}/copilot_internal/",
				Environment:                    "production",
				AgentTimeoutMin:                60,
			},
		},
	}

	// Create launch options with specific repo owner and name
	opts := &LaunchAgentOpts{
		JobID:             "test-job-123",
		SessionID:         "test-session-456",
		ActorLogin:        "test-actor",
		ActorID:           12345,
		GitHubToken:       "test-token",
		GitHubRepo:        "github/sweagentd",
		GitHubRepoOwner:   "github",
		GitHubRepoName:    "sweagentd",
		GitHubRepoID:      67890,
		GitHubRepoOwnerID: 11111,
		BranchName:        "test-branch",
		Agent:             agenticapptest.NewTestProvider(t).CopilotApp(),
	}

	// Call LaunchAgent
	_, err := launcher.LaunchAgent(ctx, opts)
	require.NoError(t, err)

	// Find the CreateDynamicWorkflowRun call
	var workflowContent string
	for _, call := range noopClient.MethodCalls {
		if call.Method == "CreateDynamicWorkflowRun" {
			workflowOpts := call.Args[4].(*github.NewDynamicWorkflowRun)
			workflowContent = *workflowOpts.Workflow
			break
		}
	}

	require.NotEmpty(t, workflowContent, "CreateDynamicWorkflowRun should have been called with workflow content")

	// Verify the repo placeholders were replaced in the workflow
	assert.Contains(t, workflowContent, "https://api.github.com/repos/github/sweagentd/copilot_internal/",
		"Workflow should contain the repo-scoped firewall rule with placeholders replaced")
	assert.NotContains(t, workflowContent, "{{repo_owner}}",
		"Workflow should not contain unreplaced repo_owner placeholder")
	assert.NotContains(t, workflowContent, "{{repo_name}}",
		"Workflow should not contain unreplaced repo_name placeholder")
}

func TestActionsWorkflowJobKnownStepsWithErrorMessage(t *testing.T) {
	t.Run("steps with not-supported errors are subset of known steps", func(t *testing.T) {
		knownSteps := ActionsWorkflowJobKnownSteps()
		stepsWithMessages := ActionsWorkflowNotSupportedStepsWithErrorMessage()

		for stepName := range stepsWithMessages {
			assert.Contains(t, knownSteps, stepName, "step %q with not-supported errors should be in the list of known steps", stepName)
		}
	})
}

func TestRuntimeEntryPoint(t *testing.T) {
	ctx := context.Background()
	actorID := int64(12345)

	tests := []struct {
		name               string
		featureFlags       map[string]bool
		expectedEntryPoint string
	}{
		{
			name:               "default entry point when no feature flags are enabled",
			featureFlags:       map[string]bool{},
			expectedEntryPoint: "dist/index.js",
		},
		{
			name: "cca entry point when cca feature flag is enabled",
			featureFlags: map[string]bool{
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV2: true,
			},
			expectedEntryPoint: "dist-cca/index.js",
		},
		{
			name: "claude entry point when claude feature flag is enabled",
			featureFlags: map[string]bool{
				featureflags.CopilotSWEAgentRuntimeEntryPointClaude: true,
			},
			expectedEntryPoint: "dist-claude/index.js",
		},
		{
			name: "codex entry point when codex feature flag is enabled",
			featureFlags: map[string]bool{
				featureflags.CopilotSWEAgentRuntimeEntryPointCodex: true,
			},
			expectedEntryPoint: "dist-codex/index.js",
		},
		{
			name: "cca takes precedence when all runtime feature flags are enabled",
			featureFlags: map[string]bool{
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV2:  true,
				featureflags.CopilotSWEAgentRuntimeEntryPointClaude: true,
				featureflags.CopilotSWEAgentRuntimeEntryPointCodex:  true,
			},
			expectedEntryPoint: "dist-cca/index.js",
		},
		{
			name: "claude takes precedence when claude and codex feature flags are enabled",
			featureFlags: map[string]bool{
				featureflags.CopilotSWEAgentRuntimeEntryPointClaude: true,
				featureflags.CopilotSWEAgentRuntimeEntryPointCodex:  true,
			},
			expectedEntryPoint: "dist-claude/index.js",
		},
		{
			name: "default entry point when all runtime feature flags are disabled",
			featureFlags: map[string]bool{
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV2:  false,
				featureflags.CopilotSWEAgentRuntimeEntryPointClaude: false,
				featureflags.CopilotSWEAgentRuntimeEntryPointCodex:  false,
			},
			expectedEntryPoint: "dist/index.js",
		},
		{
			name: "claude disabled but codex enabled",
			featureFlags: map[string]bool{
				featureflags.CopilotSWEAgentRuntimeEntryPointClaude: false,
				featureflags.CopilotSWEAgentRuntimeEntryPointCodex:  true,
			},
			expectedEntryPoint: "dist-codex/index.js",
		},
		{
			name: "claude enabled but codex disabled",
			featureFlags: map[string]bool{
				featureflags.CopilotSWEAgentRuntimeEntryPointClaude: true,
				featureflags.CopilotSWEAgentRuntimeEntryPointCodex:  false,
			},
			expectedEntryPoint: "dist-claude/index.js",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ffClient := featureflags.NewNoopClient(tt.featureFlags)
			launcher := &ActionsLauncher{
				ffClient: ffClient,
			}

			opts := &LaunchAgentOpts{
				ActorID:           actorID,
				GitHubRepoID:      67890,
				GitHubRepoOwnerID: 11111,
				Agent:             agenticapptest.NewTestCopilot(t),
			}
			data := &workflowData{
				JobName: opts.Agent.ComputeSlug(),
			}
			launcher.applyRuntimeSetup(ctx, opts, data)
			assert.Equal(t, tt.expectedEntryPoint, data.RuntimeEntryPoint, "RuntimeEntryPoint should match expected value")
		})
	}
}

func TestGitHubMCPTokenSecretName(t *testing.T) {
	ctx := context.Background()
	actorID := int64(12345)

	tests := []struct {
		name                         string
		featureFlags                 map[string]bool
		expectedGitHubMCPTokenSecret string
	}{
		{
			name:                         "feature flag disabled - uses GITHUB_COPILOT_API_TOKEN",
			featureFlags:                 map[string]bool{},
			expectedGitHubMCPTokenSecret: "GITHUB_COPILOT_API_TOKEN",
		},
		{
			name: "feature flag enabled - uses GITHUB_COPILOT_GITHUB_TOKEN",
			featureFlags: map[string]bool{
				featureflags.CopilotSWEAgentCustomAgentPermissions: true,
			},
			expectedGitHubMCPTokenSecret: "GITHUB_COPILOT_GITHUB_TOKEN",
		},
		{
			name: "feature flag explicitly disabled - uses GITHUB_COPILOT_API_TOKEN",
			featureFlags: map[string]bool{
				featureflags.CopilotSWEAgentCustomAgentPermissions: false,
			},
			expectedGitHubMCPTokenSecret: "GITHUB_COPILOT_API_TOKEN",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ffClient := featureflags.NewNoopClient(tt.featureFlags)
			launcher := &ActionsLauncher{
				ffClient: ffClient,
				obsv:     observability.NewNoopExporters(),
				opts: ActionsLauncherOpts{
					ActionsDefaultRunsOnLabels: "ubuntu-latest",
				},
			}

			opts := &LaunchAgentOpts{
				ActorID:           actorID,
				GitHubRepoID:      67890,
				GitHubRepoOwnerID: 11111,
				Agent:             agenticapptest.NewTestCopilot(t),
			}

			data := workflowData{
				RunName:                  "Test workflow",
				MCPEnabled:               true,
				GitHubMCPTokenSecretName: getGitHubMCPTokenSecretName(ctx, ffClient, opts),
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("ubuntu-latest"),
					"timeout-minutes": template.HTML("59"),
				},
			}

			content, err := launcher.workflowContent(ctx, &data, workflowTemplate, nil)
			require.NoError(t, err, "workflowContent should not return an error")

			// Verify the correct token secret name is used in the GITHUB_PERSONAL_ACCESS_TOKEN environment variable
			expectedToken := fmt.Sprintf("GITHUB_PERSONAL_ACCESS_TOKEN: \"${{ secrets.COPILOT_MCP_GITHUB_PERSONAL_ACCESS_TOKEN || secrets.%s }}\"", tt.expectedGitHubMCPTokenSecret)
			assert.Contains(t, content, expectedToken, "workflow content should contain the correct GitHub MCP token secret name")
		})
	}
}
