package launcher

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"html/template"
	"maps"
	"regexp"
	"strings"
	"testing"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	vexi "github.com/github/feature-management-client-go/vexi/v2"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/environmentfeatures"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/runnerlabels"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	"github.com/github/sweagentd/internal/sweagentd"
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
				"environment: copilot",
			},
			unexpected:   []string{},
			validateYaml: true,
		},
		{
			name: "agent secrets enabled omits copilot environment",
			data: workflowData{
				JobName:         "copilot",
				RunName:         "Fixing issue #123",
				Secrets:         []string{},
				Variables:       []string{},
				MCPEnabled:      false,
				UseAgentSecrets: true,
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
			unexpected: []string{
				"environment: copilot",
			},
			validateYaml: true,
		},
		{
			name: "agent secrets enabled but include copilot environment flag keeps environment",
			data: workflowData{
				JobName:         "copilot",
				RunName:         "Fixing issue #123",
				Secrets:         []string{},
				Variables:       []string{},
				MCPEnabled:      false,
				UseAgentSecrets: true,
				IncludeCopilotEnvironmentInDynamicWorkflow: true,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"run-name: 'Fixing issue #123'",
				"runs-on: ${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}",
				"timeout-minutes: 59",
				"environment: copilot",
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
					"runs-on":         template.HTML(runnerlabels.WindowsLatestLabel),
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
				// "Pre-cache Playwright MCP server in the background" step is skipped
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
				// "Pre-cache Playwright MCP server in the background" step is run
				"if: ${{ env.SHOULD_CONTINUE == 'true' && true && runner.os == 'Linux' }}",
				// "Pre-cache Playwright MCP server in the background" step is configured with the correct version
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
				// "Pre-cache Playwright MCP server in the background" step is run
				"if: ${{ env.SHOULD_CONTINUE == 'true' && true && runner.os == 'Linux' }}",
				// "Pre-cache Playwright MCP server in the background" step is configured with the correct version
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
				// "Pre-cache Playwright MCP server in the background" step is run
				"if: ${{ env.SHOULD_CONTINUE == 'true' && true && runner.os == 'Linux' }}",
				// "Pre-cache Playwright MCP server in the background" step is configured with the correct version
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
			name: "MCP enabled with read-only mode (CCR)",
			data: workflowData{
				JobName:         "copilot",
				RunName:         "CCR Review #789",
				Secrets:         []string{},
				Variables:       []string{},
				MCPEnabled:      true,
				MCP3PEnabled:    true,
				MCPReadOnlyMode: true,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
				PlaywrightVersion: "foo",
			},
			expected: []string{
				"COPILOT_MCP_ENABLED: true",
				"COPILOT_MCP_READ_ONLY_MODE: true",
			},
			unexpected: []string{
				"COPILOT_MCP_READ_ONLY_MODE: false",
			},
			validateYaml: true,
		},
		{
			name: "MCP enabled without read-only mode (non-CCR)",
			data: workflowData{
				JobName:         "copilot",
				RunName:         "Agent Task #101",
				Secrets:         []string{},
				Variables:       []string{},
				MCPEnabled:      true,
				MCP3PEnabled:    true,
				MCPReadOnlyMode: false,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
				PlaywrightVersion: "foo",
			},
			expected: []string{
				"COPILOT_MCP_ENABLED: true",
				"COPILOT_MCP_READ_ONLY_MODE: false",
			},
			unexpected: []string{
				"COPILOT_MCP_READ_ONLY_MODE: true",
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
			name: "preinstalled runtime rewires prepare path",
			data: workflowData{
				JobName:                "copilot",
				RunName:                "Fixing issue #123",
				MCPEnabled:             true,
				UsePreinstalledRuntime: true,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"name: Use pre-installed runtime (Linux)",
				"name: Pre-seed mkcert CA (Linux)",
				"name: Clean up mkcert CA (Linux)",
				"env.COPILOT_PREINSTALLED_RUNTIME != 'true'",
			},
			unexpected: []string{
				"name: Pre-cache Playwright MCP server in the background (Linux)",
				"name: Pre-cache Playwright MCP server in the background (Windows)",
				"name: Generate agent firewall CA (Linux)",
			},
			validateYaml: true,
		},
		{
			name: "background mkcert keygen step appears when flag enabled",
			data: workflowData{
				JobName:                "copilot",
				RunName:                "Fixing issue #123",
				MCPEnabled:             true,
				BackgroundMkcertKeygen: true,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"name: Generate agent firewall CA (Linux)",
				"mkcert -install",
				".mkcert-bg-done",
				"COPILOT_AGENT_BACKGROUND_MKCERT",
			},
			validateYaml: true,
		},
		{
			name: "background mkcert keygen step hidden when flag disabled",
			data: workflowData{
				JobName:                "copilot",
				RunName:                "Fixing issue #123",
				MCPEnabled:             true,
				BackgroundMkcertKeygen: false,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			unexpected: []string{
				"name: Generate agent firewall CA (Linux)",
				"COPILOT_AGENT_BACKGROUND_MKCERT",
			},
			validateYaml: true,
		},
		{
			name: "background mkcert keygen step hidden when preinstalled runtime",
			data: workflowData{
				JobName:                "copilot",
				RunName:                "Fixing issue #123",
				MCPEnabled:             true,
				BackgroundMkcertKeygen: true,
				UsePreinstalledRuntime: true,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"name: Pre-seed mkcert CA (Linux)",
			},
			unexpected: []string{
				"name: Generate agent firewall CA (Linux)",
			},
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
		{
			name: "download autofind step is included by default",
			data: workflowData{
				JobName:    "copilot",
				RunName:    "Fixing issue #123",
				MCPEnabled: false,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"name: Download Autofind (Linux)",
				"name: Download Autofind (Windows)",
				"autofind.tar.gz",
				"secrets.GITHUB_COPILOT_AUTOFIND_DOWNLOAD_URL",
			},
			validateYaml: true,
		},
		{
			name: "download autofind step is excluded when ActionDownloadURL is set",
			data: workflowData{
				JobName:           "copilot",
				RunName:           "Fixing issue #123",
				MCPEnabled:        false,
				ActionDownloadURL: "https://example.com/custom-runtime.tar.gz",
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			unexpected: []string{
				"name: Download Autofind (Linux)",
				"name: Download Autofind (Windows)",
			},
			validateYaml: true,
		},
		{
			name: "Post-Prepare Copilot step appears for github org",
			data: workflowData{
				JobName:         "copilot",
				RunName:         "Fixing issue #123",
				MCPEnabled:      false,
				RepositoryOwner: "github",
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"name: Checkout Repository for Post-Prepare",
				"name: Post-Prepare Copilot (Linux)",
				"name: Post-Prepare Copilot (Windows)",
				"vars.AUTOFIND_LOC != ''",
				"AUTOFIND_LOC: \"${{ vars.AUTOFIND_LOC }}\"",
			},
			validateYaml: true,
		},
		{
			name: "Post-Prepare Copilot step appears for dsp-testing org",
			data: workflowData{
				JobName:         "copilot",
				RunName:         "Fixing issue #123",
				MCPEnabled:      false,
				RepositoryOwner: "dsp-testing",
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"name: Checkout Repository for Post-Prepare",
				"name: Post-Prepare Copilot (Linux)",
				"name: Post-Prepare Copilot (Windows)",
				"vars.AUTOFIND_LOC != ''",
			},
			validateYaml: true,
		},
		{
			name: "Post-Prepare Copilot step hidden for external org",
			data: workflowData{
				JobName:         "copilot",
				RunName:         "Fixing issue #123",
				MCPEnabled:      false,
				RepositoryOwner: "external-org",
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			unexpected: []string{
				"name: Post-Prepare Copilot (Linux)",
			},
			validateYaml: true,
		},
		{
			name: "Post-Prepare Copilot step hidden when RepositoryOwner empty",
			data: workflowData{
				JobName:         "copilot",
				RunName:         "Fixing issue #123",
				MCPEnabled:      false,
				RepositoryOwner: "",
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			unexpected: []string{
				"name: Post-Prepare Copilot (Linux)",
			},
			validateYaml: true,
		},
		{
			name: "Post-Prepare Copilot step with preinstalled runtime includes COPILOT_PREINSTALLED_RUNTIME check",
			data: workflowData{
				JobName:                "copilot",
				RunName:                "Fixing issue #123",
				MCPEnabled:             false,
				RepositoryOwner:        "github",
				UsePreinstalledRuntime: true,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"name: Checkout Repository for Post-Prepare",
				"name: Post-Prepare Copilot (Linux)",
				"name: Post-Prepare Copilot (Windows)",
				"env.COPILOT_PREINSTALLED_RUNTIME != 'true'",
			},
			validateYaml: true,
		},
		{
			name: "stdin secrets are piped via stdin for runtime",
			data: workflowData{
				JobName:           "copilot",
				RunName:           "Fixing issue #123",
				Secrets:           []string{},
				Variables:         []string{},
				MCPEnabled:        true,
				RuntimeEntryPoint: "dist-cca-v3/index.js",
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				`secrets=$("${{ runner.temp }}/ghcca-node/node/bin/node" -p "JSON.stringify({`,
				`unset GITHUB_COPILOT_GITHUB_TOKEN GITHUB_PERSONAL_ACCESS_TOKEN GITHUB_COPILOT_API_TOKEN GITHUB_COPILOT_INTEGRATION_ID COPILOT_JOB_NONCE`,
				`unset GITHUB_TOKEN GITHUB_COPILOT_GITHUB_TOKEN GITHUB_COPILOT_API_TOKEN GITHUB_COPILOT_INTEGRATION_ID COPILOT_INTEGRATION_ID_OVERRIDE CAPI_HMAC_KEY_OVERRIDE COPILOT_JOB_NONCE`,
				`printf '%s' "$secrets" |`,
				`COPILOT_JOB_NONCE: process.env.COPILOT_JOB_NONCE || ''`,
				`printf '%s' "$secrets" | "$RUNNER_PATH/copilot-developer-action-main/script/start-mcp-servers.sh"`,
			},
			validateYaml: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			launcher := &ActionsLauncher{
				opts: ActionsLauncherOpts{
					ActionsDefaultRunsOnLabels: runnerlabels.UbuntuLatestLabel,
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

func TestWorkflowContentV2StdinSecrets(t *testing.T) {
	launcher := &ActionsLauncher{
		opts: ActionsLauncherOpts{
			ActionsDefaultRunsOnLabels: runnerlabels.UbuntuLatestLabel,
		},
	}

	baseData := func() workflowData {
		return workflowData{
			JobName:           "copilot",
			RunName:           "Fixing issue #123",
			Secrets:           []string{},
			Variables:         []string{},
			MCPEnabled:        true,
			RuntimeEntryPoint: "dist-cca-v3/index.js",
			Customization: map[string]template.HTML{
				"runs-on":         template.HTML("'ubuntu-latest'"),
				"timeout-minutes": template.HTML("59"),
			},
		}
	}

	t.Run("linux pipes secrets via stdin", func(t *testing.T) {
		data := baseData()
		data.TargetOS = "linux"
		data.ExpectedRunnerOS = "Linux"

		result, err := launcher.workflowContent(context.Background(), &data, workflowTemplateV2, nil)
		require.NoError(t, err)

		assert.Contains(t, result, `printf '%s' "$secrets" | "$RUNNER_PATH/copilot-developer-action-main/script/start-mcp-servers.sh"`)
		assert.Contains(t, result, `secrets=$("${{ runner.temp }}/ghcca-node/node/bin/node" -p "JSON.stringify({`)
		assert.Contains(t, result, `unset GITHUB_COPILOT_GITHUB_TOKEN GITHUB_PERSONAL_ACCESS_TOKEN GITHUB_COPILOT_API_TOKEN GITHUB_COPILOT_INTEGRATION_ID COPILOT_JOB_NONCE`)
		assert.Contains(t, result, `unset GITHUB_TOKEN GITHUB_COPILOT_GITHUB_TOKEN GITHUB_COPILOT_API_TOKEN GITHUB_COPILOT_INTEGRATION_ID COPILOT_INTEGRATION_ID_OVERRIDE CAPI_HMAC_KEY_OVERRIDE COPILOT_JOB_NONCE`)
		assert.Contains(t, result, `printf '%s' "$secrets" |`)
	})

	t.Run("windows does not pipe secrets via stdin", func(t *testing.T) {
		data := baseData()
		data.TargetOS = "windows"
		data.ExpectedRunnerOS = "Windows"

		result, err := launcher.workflowContent(context.Background(), &data, workflowTemplateV2, nil)
		require.NoError(t, err)

		assert.NotContains(t, result, `printf '%s' "$secrets" |`)
		assert.NotContains(t, result, `start-mcp-servers.sh`)
	})

	t.Run("include copilot environment flag keeps environment in v2", func(t *testing.T) {
		data := baseData()
		data.TargetOS = "linux"
		data.ExpectedRunnerOS = "Linux"
		data.UseAgentSecrets = true
		data.IncludeCopilotEnvironmentInDynamicWorkflow = true

		result, err := launcher.workflowContent(context.Background(), &data, workflowTemplateV2, nil)
		require.NoError(t, err)

		assert.Contains(t, result, "environment: copilot")
	})
}

func TestWorkflowContentProjectsResumeSessionID(t *testing.T) {
	launcher := &ActionsLauncher{
		opts: ActionsLauncherOpts{
			ActionsDefaultRunsOnLabels: runnerlabels.UbuntuLatestLabel,
		},
	}

	baseData := func() workflowData {
		return workflowData{
			JobName:           "copilot",
			RunName:           "Fixing issue #123",
			Variables:         []string{"COPILOT_AGENT_RESUME_SESSION_ID"},
			MCPEnabled:        true,
			RuntimeEntryPoint: "dist-cca-v3/index.js",
			Customization: map[string]template.HTML{
				"runs-on":         template.HTML("'ubuntu-latest'"),
				"timeout-minutes": template.HTML("59"),
			},
		}
	}

	expectedProjection := `COPILOT_AGENT_RESUME_SESSION_ID: "${{ fromJSON(github.event.inputs.COPILOT_AGENT_INPUTS).COPILOT_AGENT_RESUME_SESSION_ID }}"`
	templates := map[string]string{
		"legacy": workflowTemplate,
		"v2":     workflowTemplateV2,
	}

	for name, tmpl := range templates {
		t.Run(name, func(t *testing.T) {
			data := baseData()
			data.TargetOS = "linux"
			data.ExpectedRunnerOS = "Linux"

			result, err := launcher.workflowContent(context.Background(), &data, tmpl, nil)
			require.NoError(t, err)

			assert.Contains(t, result, expectedProjection)
			assert.NotContains(t, result, "vars.COPILOT_AGENT_RESUME_SESSION_ID")
		})
	}
}

func TestKnownStepNames(t *testing.T) {
	launcher := &ActionsLauncher{
		opts: ActionsLauncherOpts{
			ActionsDefaultRunsOnLabels: runnerlabels.UbuntuLatestLabel,
		},
	}

	// Render with every conditional step enabled so the rendered output
	// covers every name in actions_workflow*.yaml. Missing flags here would
	// let new yaml step names slip past this check.
	data := workflowData{
		JobName:                "copilot",
		RunName:                "Fixing issue #123",
		MCPEnabled:             true,
		BackgroundMkcertKeygen: true,
		RuntimeSetup:           "echo setup",
		EngineEnabled:          true,
		Customization: map[string]template.HTML{
			"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
			"timeout-minutes": template.HTML("59"),
		},
	}

	templates := map[string]string{
		"legacy": workflowTemplate,
		"v2":     workflowTemplateV2,
	}

	stepNameRegex := regexp.MustCompile(`^\s*-\s+name:\s*(.+)$`)
	knownSteps := ActionsWorkflowJobKnownSteps()

	for tmplName, tmpl := range templates {
		t.Run(tmplName, func(t *testing.T) {
			result, err := launcher.workflowContent(context.Background(), &data, tmpl, nil)
			require.NoError(t, err, "workflowContent should not return an error")

			for line := range strings.SplitSeq(result, "\n") {
				matches := stepNameRegex.FindStringSubmatch(line)
				if len(matches) <= 1 {
					continue
				}
				stepName := strings.Trim(strings.TrimSpace(matches[1]), "'\"")
				assert.Contains(t, knownSteps, stepName, "step name %q in %s template not found in ActionsWorkflowJobKnownSteps", stepName, tmplName)
			}
		})
	}
}

// TestValidateExpectedRunnerOSStep verifies that the early-assertion step is
// emitted by the v2 template when TargetOS is statically known, and is never
// emitted by the legacy template (since ExpectedRunnerOS is only populated on
// the v2 path in production — see LaunchAgent).
func TestValidateExpectedRunnerOSStep(t *testing.T) {
	launcher := &ActionsLauncher{
		opts: ActionsLauncherOpts{
			ActionsDefaultRunsOnLabels: runnerlabels.UbuntuLatestLabel,
		},
	}

	mkData := func(targetOS, expectedOS string) workflowData {
		runsOn := runnerlabels.UbuntuLatestLabel
		if targetOS == "windows" {
			runsOn = runnerlabels.WindowsLatestLabel
		}
		return workflowData{
			JobName:          "copilot",
			RunName:          "Fixing issue #123",
			TargetOS:         targetOS,
			ExpectedRunnerOS: expectedOS,
			Customization: map[string]template.HTML{
				"runs-on":         template.HTML(runsOn),
				"timeout-minutes": template.HTML("59"),
			},
		}
	}

	t.Run("v2 Linux render emits assertion step against runner.os == 'Linux'", func(t *testing.T) {
		data := mkData("linux", "Linux")
		result, err := launcher.workflowContent(context.Background(), &data, workflowTemplateV2, nil)
		require.NoError(t, err)
		assert.Contains(t, result, "Validate expected runner OS")
		assert.Contains(t, result, "runner.os != 'Linux'")
		assert.Contains(t, result, "workflow rendered for linux")
	})

	t.Run("v2 Windows render emits assertion step against runner.os == 'Windows'", func(t *testing.T) {
		data := mkData("windows", "Windows")
		result, err := launcher.workflowContent(context.Background(), &data, workflowTemplateV2, nil)
		require.NoError(t, err)
		assert.Contains(t, result, "Validate expected runner OS")
		assert.Contains(t, result, "runner.os != 'Windows'")
	})

	t.Run("legacy template never emits assertion step even with ExpectedRunnerOS set", func(t *testing.T) {
		// Defense: ExpectedRunnerOS should never be populated on the legacy
		// path in production (LaunchAgent only sets it when v2 is selected),
		// but verify the legacy template ignores it even if it ever leaks.
		data := mkData("linux", "Linux")
		result, err := launcher.workflowContent(context.Background(), &data, workflowTemplate, nil)
		require.NoError(t, err)
		assert.NotContains(t, result, "Validate expected runner OS")
	})
}

// TestWorkflowTemplateV2 verifies that the v2 template renders only the steps
// for the resolved TargetOS, omits the steps for the other OS, and strips the
// per-step `runner.os == 'X'` runtime guards.
func TestWorkflowTemplateV2(t *testing.T) {
	launcher := &ActionsLauncher{
		opts: ActionsLauncherOpts{
			ActionsDefaultRunsOnLabels: runnerlabels.UbuntuLatestLabel,
		},
	}

	mkData := func(targetOS, expectedOS string) workflowData {
		runsOn := runnerlabels.UbuntuLatestLabel
		if targetOS == "windows" {
			runsOn = runnerlabels.WindowsLatestLabel
		}
		return workflowData{
			JobName:          "copilot",
			RunName:          "Fixing issue #123",
			TargetOS:         targetOS,
			ExpectedRunnerOS: expectedOS,
			Customization: map[string]template.HTML{
				"runs-on":         template.HTML(runsOn),
				"timeout-minutes": template.HTML("59"),
			},
		}
	}

	t.Run("Linux render emits Linux steps and omits Windows steps", func(t *testing.T) {
		data := mkData("linux", "Linux")
		result, err := launcher.workflowContent(context.Background(), &data, workflowTemplateV2, nil)
		require.NoError(t, err)

		// Linux step bodies present.
		assert.Contains(t, result, "Prepare Copilot (Linux)")
		assert.Contains(t, result, "Processing Request (Linux)")
		assert.Contains(t, result, "Clean Up (Linux)")

		// Windows step bodies absent.
		assert.NotContains(t, result, "Prepare Copilot (Windows)")
		assert.NotContains(t, result, "Processing Request (Windows)")
		assert.NotContains(t, result, "Clean Up (Windows)")

		// No per-step runtime OS guards remain (legacy form: `if: ${{ runner.os == 'X' }}`).
		// The validate-runner-OS step legitimately uses `runner.os == 'Windows'` as part of
		// a compound `!=` assertion, so we match the legacy single-condition guard form here.
		assert.NotContains(t, result, "if: ${{ runner.os == 'Linux' }}")
		assert.NotContains(t, result, "if: ${{ runner.os == 'Windows' }}")

		// Defense-in-depth assertion is still wired up.
		assert.Contains(t, result, "Validate expected runner OS")
		assert.Contains(t, result, "runner.os != 'Linux'")
	})

	t.Run("Windows render emits Windows steps and omits Linux steps", func(t *testing.T) {
		data := mkData("windows", "Windows")
		result, err := launcher.workflowContent(context.Background(), &data, workflowTemplateV2, nil)
		require.NoError(t, err)

		// Windows step bodies present.
		assert.Contains(t, result, "Prepare Copilot (Windows)")
		assert.Contains(t, result, "Processing Request (Windows)")
		assert.Contains(t, result, "Clean Up (Windows)")

		// Linux step bodies absent.
		assert.NotContains(t, result, "Prepare Copilot (Linux)")
		assert.NotContains(t, result, "Processing Request (Linux)")
		assert.NotContains(t, result, "Clean Up (Linux)")

		// No per-step runtime OS guards remain (legacy form).
		assert.NotContains(t, result, "if: ${{ runner.os == 'Linux' }}")
		assert.NotContains(t, result, "if: ${{ runner.os == 'Windows' }}")

		assert.Contains(t, result, "Validate expected runner OS")
		assert.Contains(t, result, "runner.os != 'Windows'")
	})

	t.Run("v2 Windows render includes Post-Prepare Copilot (Windows) when RepositoryOwner is github", func(t *testing.T) {
		data := mkData("windows", "Windows")
		data.RepositoryOwner = "github"
		result, err := launcher.workflowContent(context.Background(), &data, workflowTemplateV2, nil)
		require.NoError(t, err)

		// Windows post-prepare step present.
		assert.Contains(t, result, "name: Checkout Repository for Post-Prepare")
		assert.Contains(t, result, "name: Post-Prepare Copilot (Windows)")

		// Linux post-prepare step absent (v2 only includes target OS).
		assert.NotContains(t, result, "name: Post-Prepare Copilot (Linux)")
	})

	t.Run("v2 preserves all known step names across the union of OS renders", func(t *testing.T) {
		// Some steps are gated by additional flags (MCPEnabled, EngineRepo,
		// UseFirewall, etc.) so we render with those flipped on so every step
		// body has a chance to appear in at least one of the two OS renders.
		fullData := func(targetOS, expectedOS string) workflowData {
			d := mkData(targetOS, expectedOS)
			d.MCPEnabled = true
			d.UsePreinstalledRuntime = true
			return d
		}

		linuxData := fullData("linux", "Linux")
		linuxOut, err := launcher.workflowContent(context.Background(), &linuxData, workflowTemplateV2, nil)
		require.NoError(t, err)

		windowsData := fullData("windows", "Windows")
		windowsOut, err := launcher.workflowContent(context.Background(), &windowsData, workflowTemplateV2, nil)
		require.NoError(t, err)

		// Steps from ActionsWorkflowJobKnownSteps may be Linux-only or
		// Windows-only; check that each one shows up in at least one render.
		// Some are conditional even with our enabled flags — we accept that
		// and only check the steps that the legacy template renders too.
		legacyData := fullData("", "")
		legacyOut, err := launcher.workflowContent(context.Background(), &legacyData, workflowTemplate, nil)
		require.NoError(t, err)

		for _, name := range ActionsWorkflowJobKnownSteps() {
			if !strings.Contains(legacyOut, name) {
				continue // legacy doesn't render it under this data, so v2 isn't expected to either
			}
			if !strings.Contains(linuxOut, name) && !strings.Contains(windowsOut, name) {
				t.Errorf("step %q is rendered by legacy template but missing from both v2 OS renders", name)
			}
		}
	})
}

// TestWorkflowContentPointerBehavior verifies that workflowContent correctly modifies
// the workflowData passed as a pointer, and produces the expected output.
func TestWorkflowContentPointerBehavior(t *testing.T) {
	launcher := &ActionsLauncher{
		opts: ActionsLauncherOpts{
			ActionsDefaultRunsOnLabels: runnerlabels.UbuntuLatestLabel,
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
				"runs-on":         template.HTML(runnerlabels.UbuntuLatestLabel),
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
				"runs-on":         template.HTML(runnerlabels.UbuntuLatestLabel),
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
				"runs-on":         template.HTML(runnerlabels.UbuntuLatestLabel),
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

func TestGenerateRunName_AgentWorkflowRunName(t *testing.T) {
	t.Run("non-empty WorkflowRunName takes precedence over RunName, PR, and issue", func(t *testing.T) {
		agent := agenticapptest.NewTestApp(0).WithWorkflowRunName("Running Copilot Code Review")
		opts := &LaunchAgentOpts{
			Agent:       agent,
			RunName:     "should be ignored",
			Action:      "fix-pr-comment",
			PRNumber:    123,
			IssueNumber: 456,
		}
		assert.Equal(t, "Running Copilot Code Review", GenerateRunName(opts))
	})

	t.Run("empty WorkflowRunName falls through to AppName", func(t *testing.T) {
		agent := agenticapptest.NewTestApp(0)
		opts := &LaunchAgentOpts{Agent: agent}
		assert.Equal(t, "Running "+agent.AppName(), GenerateRunName(opts))
	})

	t.Run("CodeScanning with PR number includes PR number in name", func(t *testing.T) {
		agent := agenticapp.NewCodeScanning(1, "github-advanced-security", 2, "bot", "commit", "email@example.com")
		opts := &LaunchAgentOpts{Agent: agent, PRNumber: 42}
		assert.Equal(t, "Code scanning AI findings on PR #42", GenerateRunName(opts))
	})

	t.Run("CodeScanning without PR number omits PR suffix", func(t *testing.T) {
		agent := agenticapp.NewCodeScanning(1, "github-advanced-security", 2, "bot", "commit", "email@example.com")
		opts := &LaunchAgentOpts{Agent: agent, PRNumber: 0}
		assert.Equal(t, "Code scanning AI findings", GenerateRunName(opts))
	})
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
			ActionsDefaultRunsOnLabels: runnerlabels.UbuntuLatestLabel,
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
			ActionsDefaultRunsOnLabels: runnerlabels.UbuntuLatestLabel,
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
					CopilotAPIURL:       "https://api.original.com",
					AgentCallbackURL:    "https://callback.original.com",
					UploadsURL:          "https://uploads.github.com/user-attachments/assets",
					ModelOverride:       "",
					AgentDebug:          false,
					Environment:         "test",
					MCPEnabled:          false,
					AgentTimeoutMin:     60,
					RuntimeSHA:          "original-sha",
					RuntimeSubmoduleSHA: "runtime-submodule-sha123",
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

		// Verify COPILOT_AGENT_RUNTIME_SHA is in the serialized inputs (accessed via fromJSON in workflow)
		assert.Equal(t, "runtime-submodule-sha123", inputs["COPILOT_AGENT_RUNTIME_SHA"],
			"COPILOT_AGENT_RUNTIME_SHA should be in serialized inputs")
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
						Environment:       tt.environmentName,
					},
				},
			}

			// Call the method under test
			opts := &LaunchAgentOpts{
				ActorID:           123,
				GitHubRepoID:      456,
				GitHubRepoOwnerID: 789,
			}
			urls, err := launcher.getURLsForEnvironment(ctx, tt.environment, opts)

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
		repoID                    int64
		ownerID                   int64
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
			repoID:                    456,
			ownerID:                   789,
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
			repoID:                    789,
			ownerID:                   101,
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
			repoID:                    101,
			ownerID:                   102,
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
			repoID:                    103,
			ownerID:                   104,
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
			repoID:                    105,
			ownerID:                   106,
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
			repoID:                    107,
			ownerID:                   108,
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
			repoID:                    109,
			ownerID:                   110,
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
			repoID:                    111,
			ownerID:                   112,
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
			repoID:                    113,
			ownerID:                   114,
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
						Environment:       tt.environmentName,
					},
				},
			}

			// Call the method under test
			opts := &LaunchAgentOpts{
				ActorID:           tt.actorID,
				GitHubRepoID:      tt.repoID,
				GitHubRepoOwnerID: tt.ownerID,
			}
			urls, err := launcher.getURLsForEnvironment(ctx, tt.environment, opts)

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
					ActionsDefaultRunsOnLabels: runnerlabels.UbuntuLatestLabel,
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
			ActionsDefaultRunsOnLabels: runnerlabels.UbuntuLatestLabel,
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
		expectedSetup      string
	}{
		{
			name:               "default entry point when no feature flags are enabled",
			featureFlags:       map[string]bool{},
			expectedEntryPoint: "dist/index.js",
		},
		{
			name: "cca v3 app entry point when cca v3 app feature flag is enabled",
			featureFlags: map[string]bool{
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV3App: true,
			},
			expectedEntryPoint: "dist-cca-v3/index.js",
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
			expectedSetup:      agenticapp.CodexSetupCommand,
		},
		{
			name: "cca v3 app takes precedence when all runtime feature flags are enabled",
			featureFlags: map[string]bool{
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV3App: true,
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV2:    true,
				featureflags.CopilotSWEAgentRuntimeEntryPointClaude:   true,
				featureflags.CopilotSWEAgentRuntimeEntryPointCodex:    true,
			},
			expectedEntryPoint: "dist-cca-v3/index.js",
		},
		{
			name: "cca takes precedence when cca v3 app is disabled",
			featureFlags: map[string]bool{
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV3App: false,
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV2:    true,
				featureflags.CopilotSWEAgentRuntimeEntryPointClaude:   true,
				featureflags.CopilotSWEAgentRuntimeEntryPointCodex:    true,
			},
			expectedEntryPoint: "dist-cca/index.js",
		},
		{
			name: "cca v3 app opt-out falls through to cca entry point",
			featureFlags: map[string]bool{
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV3App:       true,
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV3AppOptOut: true,
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV2:          true,
			},
			expectedEntryPoint: "dist-cca/index.js",
		},
		{
			name: "cca v3 app opt-out falls through to default entry point",
			featureFlags: map[string]bool{
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV3App:       true,
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV3AppOptOut: true,
			},
			expectedEntryPoint: "dist/index.js",
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
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV3App: false,
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV2:    false,
				featureflags.CopilotSWEAgentRuntimeEntryPointClaude:   false,
				featureflags.CopilotSWEAgentRuntimeEntryPointCodex:    false,
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
			expectedSetup:      agenticapp.CodexSetupCommand,
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
			assert.Equal(t, tt.expectedSetup, data.RuntimeSetup, "RuntimeSetup should match expected value")
		})
	}
}

func TestRuntimeEntryPoint_CCAv3DoesNotOverridePartnerAgents(t *testing.T) {
	ctx := context.Background()

	t.Run("claude agent uses claude runtime even when cca v3 flag is enabled", func(t *testing.T) {
		launcher := &ActionsLauncher{
			ffClient: featureflags.NewNoopClient(map[string]bool{
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV3App: true,
			}),
		}
		claude := agenticapp.NewClaude(1, "claude-app", 2, "claude-bot", "commit-login", "commit@email.com")
		opts := &LaunchAgentOpts{
			ActorID:           12345,
			GitHubRepoID:      67890,
			GitHubRepoOwnerID: 11111,
			Agent:             claude,
		}
		data := &workflowData{}
		launcher.applyRuntimeSetup(ctx, opts, data)
		assert.Equal(t, "dist-claude/index.js", data.RuntimeEntryPoint)
	})

	t.Run("codex agent uses codex runtime even when cca v3 flag is enabled", func(t *testing.T) {
		launcher := &ActionsLauncher{
			ffClient: featureflags.NewNoopClient(map[string]bool{
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV3App: true,
			}),
		}
		codex := agenticapp.NewCodex(1, "codex-app", 2, "codex-bot", "commit-login", "commit@email.com")
		opts := &LaunchAgentOpts{
			ActorID:           12345,
			GitHubRepoID:      67890,
			GitHubRepoOwnerID: 11111,
			Agent:             codex,
		}
		data := &workflowData{}
		launcher.applyRuntimeSetup(ctx, opts, data)
		assert.Equal(t, "dist-codex/index.js", data.RuntimeEntryPoint)
	})

	t.Run("third-party agent uses cca v3 runtime when cca v3 flag is enabled", func(t *testing.T) {
		launcher := &ActionsLauncher{
			ffClient: featureflags.NewNoopClient(map[string]bool{
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV3App: true,
			}),
		}
		thirdParty := agenticapp.NewThirdParty(1, "third-party-agent", "", 2, "third-party-agent-bot", "commit-login", "commit@email.com", nil, nil)
		opts := &LaunchAgentOpts{
			ActorID:           12345,
			GitHubRepoID:      67890,
			GitHubRepoOwnerID: 11111,
			Agent:             thirdParty,
		}
		data := &workflowData{}
		launcher.applyRuntimeSetup(ctx, opts, data)
		assert.Equal(t, "dist-cca-v3/index.js", data.RuntimeEntryPoint)
	})

	t.Run("third-party agent uses default Copilot runtime when cca v3 flag is disabled", func(t *testing.T) {
		launcher := &ActionsLauncher{
			ffClient: featureflags.NewNoopClient(map[string]bool{
				featureflags.CopilotSWEAgentRuntimeEntryPointCCAV3App: false,
			}),
		}
		thirdParty := agenticapp.NewThirdParty(1, "third-party-agent", "", 2, "third-party-agent-bot", "commit-login", "commit@email.com", nil, nil)
		opts := &LaunchAgentOpts{
			ActorID:           12345,
			GitHubRepoID:      67890,
			GitHubRepoOwnerID: 11111,
			Agent:             thirdParty,
		}
		data := &workflowData{}
		launcher.applyRuntimeSetup(ctx, opts, data)
		assert.Equal(t, "dist/index.js", data.RuntimeEntryPoint)
	})
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
			name:                         "MCP uses GITHUB_COPILOT_GITHUB_TOKEN",
			featureFlags:                 map[string]bool{},
			expectedGitHubMCPTokenSecret: "GITHUB_COPILOT_GITHUB_TOKEN",
		},
		{
			name: "shell token permissions does not affect MCP token",
			featureFlags: map[string]bool{
				featureflags.CopilotSWEAgentShellTokenPermissions: true,
			},
			expectedGitHubMCPTokenSecret: "GITHUB_COPILOT_GITHUB_TOKEN",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ffClient := featureflags.NewNoopClient(tt.featureFlags)
			launcher := &ActionsLauncher{
				ffClient: ffClient,
				obsv:     observability.NewNoopExporters(),
				opts: ActionsLauncherOpts{
					ActionsDefaultRunsOnLabels: runnerlabels.UbuntuLatestLabel,
				},
			}

			opts := &LaunchAgentOpts{
				ActorID:           actorID,
				GitHubRepoID:      67890,
				GitHubRepoOwnerID: 11111,
				Agent:             agenticapptest.NewTestCopilot(t),
			}

			data := workflowData{
				RunName:          "Test workflow",
				MCPEnabled:       true,
				TokenSecretNames: getGitHubTokenSecretNames(ctx, ffClient, opts),
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML(runnerlabels.UbuntuLatestLabel),
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

func TestLaunchAgent_BranchlessUsesDefaultBranchAsRef(t *testing.T) {
	ctx := context.Background()

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

	launcher := &ActionsLauncher{
		obsv:                observability.NewNoopExporters(),
		ffClient:            featureflags.NewNoopClient(map[string]bool{}),
		githubClientFactory: clientFactory,
		ghTwirp:             mockTwirp,
		spokes:              spokestest.NewClient(t),
		appProvider:         agenticapptest.NewTestProvider(t),
		opts: ActionsLauncherOpts{
			ActionsDefaultRunsOnLabels: runnerlabels.UbuntuLatestLabel,
			AgentLauncherOpts: AgentLauncherOpts{
				CopilotAPIURL:     "https://api.githubcopilot.com",
				AgentCallbackURL:  "https://api.githubcopilot.com/agents/swe/agent",
				UploadsURL:        "https://uploads.github.com/user-attachments/assets",
				DownloadsURL:      "https://downloads.github.com",
				SecretScanningURL: "https://scanning-api.github.com/api/v1/scan/multipart",
				Environment:       "production",
				AgentTimeoutMin:   60,
			},
		},
	}

	// Launch with BranchName set to the default branch (resolved upstream by executor)
	opts := &LaunchAgentOpts{
		JobID:             "branchless-job-123",
		SessionID:         "branchless-session-456",
		ActorLogin:        "test-actor",
		ActorID:           12345,
		GitHubToken:       "test-token",
		GitHubRepo:        "github/sweagentd",
		GitHubRepoOwner:   "github",
		GitHubRepoName:    "sweagentd",
		GitHubRepoID:      67890,
		GitHubRepoOwnerID: 11111,
		BranchName:        "main", // Resolved to default branch by executor
		Agent:             agenticapptest.NewTestProvider(t).CopilotApp(),
	}

	_, err := launcher.LaunchAgent(ctx, opts)
	require.NoError(t, err)

	// Find the CreateDynamicWorkflowRun call and verify it used the default branch as Ref
	var ref string
	for _, call := range noopClient.MethodCalls {
		if call.Method != "CreateDynamicWorkflowRun" {
			continue
		}
		workflowOpts := call.Args[4].(*github.NewDynamicWorkflowRun)
		ref = *workflowOpts.Ref
		break
	}

	require.Equal(t, "main", ref, "CreateDynamicWorkflowRun should use DefaultBranch as Ref when BranchName is empty")
}

func TestLaunchAgent_OrgRunnerSettings(t *testing.T) {
	ctx := context.Background()

	setupStepsNoRunsOn := []byte(`
name: "Test"
on:
  workflow_dispatch:
permissions: {}
jobs:
  copilot-setup-steps:
    steps:
      - name: some setup step
        run: echo hello
`)

	setupStepsWithRunsOn := []byte(`
name: "Test"
on:
  workflow_dispatch:
permissions: {}
jobs:
  copilot-setup-steps:
    runs-on: custom-runner
    steps:
      - name: some setup step
        run: echo hello
`)

	const ccrAppID int64 = 946600
	ccrApp := agenticapp.NewCopilotCodeReview(ccrAppID, agenticapp.CopilotCodeReviewComputeSlug, ccrAppID+1, "github-copilot-code-review-bot", "commit-login", "commit@email.com")

	tests := []struct {
		name                        string
		setupStepsContent           []byte
		orgRunnerSettings           *sweagentdTwirp.GetOrganizationCCARunnerSettingsResponse
		agent                       sweagentd.AgenticApp
		features                    environmentfeatures.Features
		extraFlags                  map[string]bool
		expectedRunsOn              string
		expectedWorkflowContains    string
		expectedWorkflowNotContains string
	}{
		{
			name:              "setup steps with no runs-on uses org labeled runner",
			setupStepsContent: setupStepsNoRunsOn,
			orgRunnerSettings: &sweagentdTwirp.GetOrganizationCCARunnerSettingsResponse{
				Runner: &sweagentdTwirp.GetOrganizationCCARunnerSettingsResponse_LabeledRunner{
					LabeledRunner: &sweagentdTwirp.LabeledRunner{
						Labels: []string{runnerlabels.SelfHostedLabel},
					},
				},
			},
			expectedRunsOn:           "custom",
			expectedWorkflowContains: "labels: self-hosted",
		},
		{
			name:              "setup steps with custom runs-on reset by AllowRepositoryCustomization=false",
			setupStepsContent: setupStepsWithRunsOn,
			orgRunnerSettings: &sweagentdTwirp.GetOrganizationCCARunnerSettingsResponse{
				AllowRepositoryCustomization: false,
				Runner: &sweagentdTwirp.GetOrganizationCCARunnerSettingsResponse_LabeledRunner{
					LabeledRunner: &sweagentdTwirp.LabeledRunner{
						Labels: []string{runnerlabels.SelfHostedLabel},
					},
				},
			},
			expectedRunsOn:              "custom",
			expectedWorkflowContains:    "labels: self-hosted",
			expectedWorkflowNotContains: "custom-runner",
		},
		{
			name:              "CCR agent with setup steps disabled and kill switch on skips org labeled runner override",
			setupStepsContent: setupStepsWithRunsOn,
			orgRunnerSettings: &sweagentdTwirp.GetOrganizationCCARunnerSettingsResponse{
				Runner: &sweagentdTwirp.GetOrganizationCCARunnerSettingsResponse_LabeledRunner{
					LabeledRunner: &sweagentdTwirp.LabeledRunner{
						Labels: []string{runnerlabels.SelfHostedLabel},
					},
				},
			},
			agent: ccrApp,
			features: environmentfeatures.Features{
				CopilotSetupSteps: &environmentfeatures.CopilotSetupSteps{Skip: true},
			},
			extraFlags: map[string]bool{
				featureflags.CopilotSWEAgentCCRDisableRunsOnOverride: true,
			},
			// CCR uses an Autofind entry point, so the custom-image fallback is gated off and
			// runs-on stays empty; the rendered workflow falls back to the default runs-on
			// expression (COPILOT_AGENT_RUNS_ON_LABELS) instead of the SHR org override.
			expectedRunsOn:              "",
			expectedWorkflowContains:    "COPILOT_AGENT_RUNS_ON_LABELS",
			expectedWorkflowNotContains: "labels: self-hosted",
		},
		{
			name:              "CCR agent with setup steps enabled and kill switch on still skips org labeled runner override",
			setupStepsContent: setupStepsNoRunsOn,
			orgRunnerSettings: &sweagentdTwirp.GetOrganizationCCARunnerSettingsResponse{
				Runner: &sweagentdTwirp.GetOrganizationCCARunnerSettingsResponse_LabeledRunner{
					LabeledRunner: &sweagentdTwirp.LabeledRunner{
						Labels: []string{runnerlabels.SelfHostedLabel},
					},
				},
			},
			agent: ccrApp,
			// No features.CopilotSetupSteps.Skip — setup steps are enabled. The kill switch
			// should still apply, proving the gate is CCR-scoped and not setup-steps-scoped.
			extraFlags: map[string]bool{
				featureflags.CopilotSWEAgentCCRDisableRunsOnOverride: true,
			},
			expectedRunsOn:              "",
			expectedWorkflowContains:    "COPILOT_AGENT_RUNS_ON_LABELS",
			expectedWorkflowNotContains: "labels: self-hosted",
		},
		{
			name:              "CCR agent with setup steps disabled and kill switch off still applies org labeled runner override",
			setupStepsContent: setupStepsWithRunsOn,
			orgRunnerSettings: &sweagentdTwirp.GetOrganizationCCARunnerSettingsResponse{
				Runner: &sweagentdTwirp.GetOrganizationCCARunnerSettingsResponse_LabeledRunner{
					LabeledRunner: &sweagentdTwirp.LabeledRunner{
						Labels: []string{runnerlabels.SelfHostedLabel},
					},
				},
			},
			agent: ccrApp,
			features: environmentfeatures.Features{
				CopilotSetupSteps: &environmentfeatures.CopilotSetupSteps{Skip: true},
			},
			expectedRunsOn:           "custom",
			expectedWorkflowContains: "labels: self-hosted",
		},
		{
			name:              "non-CCR agent with setup steps disabled and kill switch on still applies org labeled runner override",
			setupStepsContent: setupStepsWithRunsOn,
			orgRunnerSettings: &sweagentdTwirp.GetOrganizationCCARunnerSettingsResponse{
				Runner: &sweagentdTwirp.GetOrganizationCCARunnerSettingsResponse_LabeledRunner{
					LabeledRunner: &sweagentdTwirp.LabeledRunner{
						Labels: []string{runnerlabels.SelfHostedLabel},
					},
				},
			},
			features: environmentfeatures.Features{
				CopilotSetupSteps: &environmentfeatures.CopilotSetupSteps{Skip: true},
			},
			extraFlags: map[string]bool{
				featureflags.CopilotSWEAgentCCRDisableRunsOnOverride: true,
			},
			// Kill switch is CCR-scoped and must not affect CCA / other agents that disable
			// setup steps.
			expectedRunsOn:           "custom",
			expectedWorkflowContains: "labels: self-hosted",
		},
		{
			name:              "CCR agent with setup steps providing runs-on and kill switch on drops setup-steps runs-on",
			setupStepsContent: setupStepsWithRunsOn,
			agent:             ccrApp,
			extraFlags: map[string]bool{
				featureflags.CopilotSWEAgentCCRDisableRunsOnOverride: true,
			},
			// Setup-steps yml specifies runs-on: custom-runner. The kill switch must drop that
			// in addition to skipping the org override, falling back to the default expression.
			expectedRunsOn:              "",
			expectedWorkflowContains:    "COPILOT_AGENT_RUNS_ON_LABELS",
			expectedWorkflowNotContains: "custom-runner",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
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
			mockTwirp.NoopSweagentdAPI.MockGetOrganizationCCARunnerSettings = func(ctx context.Context, req *sweagentdTwirp.GetOrganizationCCARunnerSettingsRequest) (*sweagentdTwirp.GetOrganizationCCARunnerSettingsResponse, error) {
				return tt.orgRunnerSettings, nil
			}

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

			provider := agenticapp.NewProvider(agenticapptest.NewTestCopilot(t), ccrApp)

			launcher := &ActionsLauncher{
				obsv: observability.NewNoopExporters(),
				ffClient: func() featureflags.Client {
					flags := map[string]bool{
						featureflags.CopilotSWEAgentRunnerControlSettings: true,
					}
					maps.Copy(flags, tt.extraFlags)
					return featureflags.NewNoopClient(flags)
				}(),
				githubClientFactory: clientFactory,
				ghTwirp:             mockTwirp,
				spokes:              spokestest.NewClient(t, spokestest.WithBlob(".github/workflows/copilot-setup-steps.yml", tt.setupStepsContent)),
				appProvider:         provider,
				opts: ActionsLauncherOpts{
					ActionsDefaultRunsOnLabels: runnerlabels.UbuntuLatestLabel,
					AgentLauncherOpts: AgentLauncherOpts{
						CopilotAPIURL:     "https://api.githubcopilot.com",
						AgentCallbackURL:  "https://api.githubcopilot.com/agents/swe/agent",
						UploadsURL:        "https://uploads.github.com/user-attachments/assets",
						DownloadsURL:      "https://downloads.github.com",
						SecretScanningURL: "https://scanning-api.github.com/api/v1/scan/multipart",
						Environment:       "production",
						AgentTimeoutMin:   60,
					},
				},
			}

			agent := tt.agent
			if agent == nil {
				agent = provider.CopilotApp()
			}
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
				Agent:             agent,
				OwnerType:         sweagentd.OwnerTypeOrganization,
				Features:          tt.features,
			}

			result, err := launcher.LaunchAgent(ctx, opts)
			require.NoError(t, err)
			assert.Equal(t, tt.expectedRunsOn, result.RunsOn, "LaunchResult.RunsOn should match expected value")

			var workflowContent string
			for _, call := range noopClient.MethodCalls {
				if call.Method == "CreateDynamicWorkflowRun" {
					workflowOpts := call.Args[4].(*github.NewDynamicWorkflowRun)
					workflowContent = *workflowOpts.Workflow
					break
				}
			}

			require.NotEmpty(t, workflowContent, "CreateDynamicWorkflowRun should have been called with workflow content")
			assert.Contains(t, workflowContent, tt.expectedWorkflowContains,
				"workflow content should contain the expected runs-on value")
			if tt.expectedWorkflowNotContains != "" {
				assert.NotContains(t, workflowContent, tt.expectedWorkflowNotContains,
					"workflow content should not contain the overridden runs-on value")
			}
		})
	}
}

func TestApplyEngineMode(t *testing.T) {
	ctx := context.Background()

	tests := []struct {
		name                   string
		isDev                  bool
		flagEnabled            bool
		expectEnabled          bool
		expectRepoNWO          string
		expectDownloadURLMatch string
	}{
		{
			name:                   "enabled in dev with flag on",
			isDev:                  true,
			flagEnabled:            true,
			expectEnabled:          true,
			expectRepoNWO:          "github/agent-platform-engine-example",
			expectDownloadURLMatch: "http://codeload.github.localhost/github/agent-platform-engine-example/tar.gz/main",
		},
		{
			name:          "disabled when flag is off",
			isDev:         true,
			flagEnabled:   false,
			expectEnabled: false,
		},
		{
			name:          "disabled in non-dev even with flag on",
			isDev:         false,
			flagEnabled:   true,
			expectEnabled: false,
		},
		{
			name:          "disabled in non-dev with flag off",
			isDev:         false,
			flagEnabled:   false,
			expectEnabled: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			launcher := &ActionsLauncher{
				ffClient: featureflags.NewNoopClient(map[string]bool{
					featureflags.CopilotSWEAgentEngineMode: tt.flagEnabled,
				}),
				opts: ActionsLauncherOpts{
					AgentLauncherOpts: AgentLauncherOpts{
						IsDevelopmentEnvironment: tt.isDev,
					},
				},
			}

			data := &workflowData{}
			launcher.applyEngineMode(ctx, &LaunchAgentOpts{}, data)

			assert.Equal(t, tt.expectEnabled, data.EngineEnabled, "EngineEnabled")

			if tt.expectEnabled {
				assert.Equal(t, tt.expectRepoNWO, data.EngineRepoNWO, "EngineRepoNWO")
				assert.Equal(t, tt.expectDownloadURLMatch, data.EngineDownloadURL, "EngineDownloadURL")
			} else {
				assert.Empty(t, data.EngineRepoNWO, "EngineRepoNWO should be empty when disabled")
				assert.Empty(t, data.EngineDownloadURL, "EngineDownloadURL should be empty when disabled")
			}
		})
	}
}

func TestWorkflowContent_EngineMode(t *testing.T) {
	launcher := &ActionsLauncher{
		opts: ActionsLauncherOpts{
			ActionsDefaultRunsOnLabels: runnerlabels.UbuntuLatestLabel,
		},
	}

	tests := []struct {
		name       string
		data       workflowData
		expected   []string
		unexpected []string
	}{
		{
			name: "engine enabled renders engine steps",
			data: workflowData{
				JobName:           "copilot",
				RunName:           "Test engine mode",
				Secrets:           []string{},
				Variables:         []string{},
				EngineEnabled:     true,
				EngineRepoNWO:     "github/agent-platform-engine-example",
				EngineDownloadURL: "http://codeload.github.localhost/github/agent-platform-engine-example/tar.gz/main",
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML(runnerlabels.UbuntuLatestLabel),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"Download and Run Engine",
				"Downloading engine from github/agent-platform-engine-example",
				"http://codeload.github.localhost/github/agent-platform-engine-example/tar.gz/main",
				"engine/engine.yaml",
				"Processing requests (engine mode)",
			},
			unexpected: []string{
				"Processing Request (Linux)",
			},
		},
		{
			name: "engine disabled renders standard runtime",
			data: workflowData{
				JobName:       "copilot",
				RunName:       "Test standard mode",
				Secrets:       []string{},
				Variables:     []string{},
				EngineEnabled: false,
				Customization: map[string]template.HTML{
					"runs-on":         template.HTML(runnerlabels.UbuntuLatestLabel),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"Processing Request (Linux)",
			},
			unexpected: []string{
				"Download and Run Engine",
				"engine/engine.yaml",
				"Processing requests (engine mode)",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, err := launcher.workflowContent(context.Background(), &tt.data, workflowTemplate, nil)
			require.NoError(t, err, "workflowContent should not return an error")

			for _, expected := range tt.expected {
				assert.Contains(t, result, expected, "workflow should contain: %s", expected)
			}
			for _, unexpected := range tt.unexpected {
				assert.NotContains(t, result, unexpected, "workflow should NOT contain: %s", unexpected)
			}
		})
	}
}

func TestLaunchAgent_CustomImage(t *testing.T) {
	tests := []struct {
		name               string
		disableFlagOn      bool
		expectPreinstalled bool
		expectedRunsOn     string
		unexpectedRunsOn   string
	}{
		{
			name:               "custom image applied by default",
			disableFlagOn:      false,
			expectPreinstalled: true,
			expectedRunsOn:     runnerlabels.CustomImageLabel,
			unexpectedRunsOn:   "COPILOT_AGENT_RUNS_ON_LABELS",
		},
		{
			name:               "custom image disabled via disable flag",
			disableFlagOn:      true,
			expectPreinstalled: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := context.Background()

			ffFlags := map[string]bool{}
			if tt.disableFlagOn {
				ffFlags[featureflags.CopilotSWEAgentDisableCustomImage] = true
			}
			ffClient := featureflags.NewNoopClient(ffFlags)

			mockTwirp := githubtwirp.NewNoopClient()
			mockTwirp.NoopSweagentdAPI.MockMCPConfigurationForRepository = func(ctx context.Context, req *sweagentdTwirp.MCPConfigurationForRepositoryRequest) (*sweagentdTwirp.MCPConfigurationForRepositoryResponse, error) {
				return &sweagentdTwirp.MCPConfigurationForRepositoryResponse{
					McpConfigurationJson: "{}",
					IsMcpEnabled:         false,
				}, nil
			}

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

			var counterKeys []string
			obsv := observability.NewNoopExporters()
			obsv.Statter = &observability.MockStatter{
				MockCounter: func(key string, _ stats.Tags, _ int64) {
					counterKeys = append(counterKeys, key)
				},
			}

			launcher := &ActionsLauncher{
				obsv:                obsv,
				ffClient:            ffClient,
				githubClientFactory: clientFactory,
				ghTwirp:             mockTwirp,
				spokes:              spokestest.NewClient(t),
				appProvider:         agenticapptest.NewTestProvider(t),
				opts: ActionsLauncherOpts{
					ActionsDefaultRunsOnLabels: runnerlabels.UbuntuLatestLabel,
					AgentLauncherOpts: AgentLauncherOpts{
						CopilotAPIURL:     "https://api.githubcopilot.com",
						AgentCallbackURL:  "https://api.githubcopilot.com/agents/swe/agent",
						UploadsURL:        "https://uploads.github.com/user-attachments/assets",
						DownloadsURL:      "https://downloads.github.com",
						SecretScanningURL: "https://scanning-api.github.com/api/v1/scan/multipart",
						Environment:       "staging",
						AgentTimeoutMin:   60,
					},
				},
			}

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

			result, err := launcher.LaunchAgent(ctx, opts)
			require.NoError(t, err)

			var workflowContent string
			for _, call := range noopClient.MethodCalls {
				if call.Method == "CreateDynamicWorkflowRun" {
					workflowOpts := call.Args[4].(*github.NewDynamicWorkflowRun)
					workflowContent = *workflowOpts.Workflow
					break
				}
			}

			require.NotEmpty(t, workflowContent, "CreateDynamicWorkflowRun should have been called with workflow content")

			if tt.expectPreinstalled {
				assert.Contains(t, workflowContent, "name: Use pre-installed runtime (Linux)",
					"Workflow should contain pre-installed runtime step when custom image is enabled")
				assert.Contains(t, workflowContent, "name: Pre-seed mkcert CA (Linux)",
					"Workflow should contain pre-seed mkcert CA step when custom image is enabled")
			} else {
				assert.NotContains(t, workflowContent, "name: Use pre-installed runtime (Linux)",
					"Workflow should not contain pre-installed runtime step when custom image is disabled")
				assert.Contains(t, workflowContent, "COPILOT_AGENT_RUNS_ON_LABELS",
					"Workflow should contain default runs-on template variable when custom image is disabled")
				assert.Empty(t, result.RunsOn,
					"LaunchResult.RunsOn should be empty when custom image is disabled")
			}

			if tt.expectedRunsOn != "" {
				assert.Equal(t, tt.expectedRunsOn, result.RunsOn,
					"LaunchResult.RunsOn should reflect the custom image runs-on label")
				assert.Contains(t, workflowContent, tt.expectedRunsOn,
					"Workflow should contain the custom image runs-on label")
			}

			if tt.unexpectedRunsOn != "" {
				assert.NotContains(t, workflowContent, tt.unexpectedRunsOn,
					"Workflow should not contain the default runs-on template variable")
			}

			if !tt.disableFlagOn {
				assert.Contains(t, counterKeys, "custom_image.enabled",
					"custom_image.enabled counter should be emitted when custom image is used")
			} else {
				assert.NotContains(t, counterKeys, "custom_image.enabled",
					"custom_image.enabled counter should not be emitted when custom image is disabled")
			}
		})
	}
}

// scopedDisableFFClient is a featureflags.Client that returns true for
// CopilotSWEAgentDisableCustomImage only when the actor matches
// disabledUserID, verifying per-user scoping of the safety-valve flag.
type scopedDisableFFClient struct {
	disabledUserID int64
}

func (c *scopedDisableFFClient) IsEnabled(context.Context, string, ...vexi.Actor) bool {
	return false
}
func (c *scopedDisableFFClient) IsEnabledForUser(context.Context, string, int64) bool {
	return false
}
func (c *scopedDisableFFClient) IsEnabledForRepo(context.Context, string, int64) bool {
	return false
}
func (c *scopedDisableFFClient) IsEnabledForUserOrRepo(context.Context, string, int64, int64) bool {
	return false
}
func (c *scopedDisableFFClient) IsEnabledForOrganization(context.Context, string, int64) bool {
	return false
}
func (c *scopedDisableFFClient) IsEnabledForOwner(context.Context, string, int64) bool {
	return false
}
func (c *scopedDisableFFClient) IsEnabledForRepoOrOwner(context.Context, string, sweagentd.Repository) bool {
	return false
}
func (c *scopedDisableFFClient) IsEnabledForRepoOrOwnerWithDefaultValue(_ context.Context, _ string, defaultValue bool, _ sweagentd.Repository) bool {
	return defaultValue
}
func (c *scopedDisableFFClient) IsEnabledForUserOrRepoOrOwner(_ context.Context, flag string, actors sweagentd.RepositoryWithActor) bool {
	return flag == featureflags.CopilotSWEAgentDisableCustomImage && actors.GetActorID() == c.disabledUserID
}
func (c *scopedDisableFFClient) IsEnabledForGitHubApp(context.Context, string, int64) bool {
	return false
}
func (c *scopedDisableFFClient) IsEnabledForOAuthApp(context.Context, string, int64) bool {
	return false
}

func TestUseCustomImage(t *testing.T) {
	copilotAgent := agenticapp.NewCopilot(0, "copilot", 0, "copilot-bot", "commit", "commit@email.com")
	codeReviewAgent := agenticapp.NewCopilotCodeReview(0, "code-review", 0, "cr-bot", "commit", "commit@email.com")
	codeScanningAgent := agenticapp.NewCodeScanning(0, "code-scanning", 0, "cs-bot", "commit", "commit@email.com")

	tests := []struct {
		name           string
		autofindFlagOn bool
		runsOn         string
		agent          sweagentd.AgenticApp
		expected       bool
	}{
		{"runsOn empty, copilot agent", false, "", copilotAgent, true},
		{"runsOn ubuntu-latest, copilot agent", false, runnerlabels.UbuntuLatestLabel, copilotAgent, true},
		{"runsOn custom runner from setup-steps", false, runnerlabels.SelfHostedLabel, copilotAgent, false},
		{"runsOn windows-latest from setup-steps", false, runnerlabels.WindowsLatestLabel, copilotAgent, false},
		{"runsOn empty, nil agent", false, "", nil, true},
		{"runsOn empty, code-review agent without autofind flag", false, "", codeReviewAgent, false},
		{"runsOn empty, code-scanning agent without autofind flag", false, "", codeScanningAgent, false},
		{"autofind flag on, code-review agent", true, "", codeReviewAgent, true},
		{"autofind flag on, code-scanning agent", true, "", codeScanningAgent, true},
		{"autofind flag on, copilot agent (unaffected)", true, "", copilotAgent, true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ffFlags := map[string]bool{}
			if tt.autofindFlagOn {
				ffFlags[featureflags.CopilotSWEAgentUseCustomImageAutofind] = true
			}

			launcher := &ActionsLauncher{
				obsv:     observability.NewNoopExporters(),
				ffClient: featureflags.NewNoopClient(ffFlags),
			}

			opts := &LaunchAgentOpts{Agent: tt.agent}
			assert.Equal(t, tt.expected, launcher.useCustomImage(context.Background(), tt.runsOn, opts))
		})
	}

	t.Run("disable flag scoped to specific user disables custom image for that user only", func(t *testing.T) {
		launcher := &ActionsLauncher{
			obsv: observability.NewNoopExporters(),
			ffClient: &scopedDisableFFClient{
				disabledUserID: 12345,
			},
		}

		assert.False(t, launcher.useCustomImage(context.Background(), "", &LaunchAgentOpts{
			ActorID: 12345,
			Agent:   copilotAgent,
		}), "custom image should be disabled for the targeted user")

		assert.True(t, launcher.useCustomImage(context.Background(), "", &LaunchAgentOpts{
			ActorID: 99999,
			Agent:   copilotAgent,
		}), "custom image should remain enabled for other users")
	})
}

func TestWorkflowContent_MaterializedFirewall(t *testing.T) {
	launcher := &ActionsLauncher{
		opts: ActionsLauncherOpts{
			ActionsDefaultRunsOnLabels: runnerlabels.UbuntuLatestLabel,
		},
	}

	baseData := func() workflowData {
		return workflowData{
			JobName:                              "copilot",
			RunName:                              "Fixing issue #123",
			Secrets:                              []string{},
			Variables:                            []string{},
			MCPEnabled:                           false,
			AgentFirewallEnabledDefault:          true,
			AgentFirewallRequiredAllowList:       "https://github.com",
			AgentFirewallRuleSetAllowListDefault: "default-rules",
			Customization: map[string]template.HTML{
				"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
				"timeout-minutes": template.HTML("59"),
			},
		}
	}

	t.Run("uses Actions Variables when UseMaterializedFirewall is false", func(t *testing.T) {
		data := baseData()
		data.UseMaterializedFirewall = false

		result, err := launcher.workflowContent(context.Background(), &data, workflowTemplate, nil)
		require.NoError(t, err)

		assert.Contains(t, result, `vars.COPILOT_AGENT_FIREWALL_ENABLED`)
		assert.Contains(t, result, `vars.COPILOT_AGENT_FIREWALL_ALLOW_LIST`)
		assert.Contains(t, result, `vars.COPILOT_AGENT_FIREWALL_ALLOW_LIST_ADDITIONS`)
		assert.NotContains(t, result, "MaterializedFirewall")
	})

	t.Run("uses materialized values when UseMaterializedFirewall is true", func(t *testing.T) {
		data := baseData()
		data.UseMaterializedFirewall = true
		data.MaterializedFirewallEnabled = true
		data.MaterializedFirewallUseDefaultRules = true
		data.MaterializedFirewallAllowedRules = "example.test,api.example.test"

		result, err := launcher.workflowContent(context.Background(), &data, workflowTemplate, nil)
		require.NoError(t, err)

		assert.Contains(t, result, "COPILOT_AGENT_FIREWALL_ENABLED: \"true\"")
		assert.Contains(t, result, "COPILOT_AGENT_FIREWALL_ENABLE_RULESET_ALLOW_LIST: \"true\"")
		assert.Contains(t, result, "example.test,api.example.test")
		// Should NOT contain Actions Variable references for firewall settings
		assert.NotContains(t, result, "vars.COPILOT_AGENT_FIREWALL_ENABLED")
		assert.NotContains(t, result, "vars.COPILOT_AGENT_FIREWALL_ALLOW_LIST_ADDITIONS")
	})

	t.Run("materialized firewall disabled produces valid YAML", func(t *testing.T) {
		data := baseData()
		data.UseMaterializedFirewall = true
		data.MaterializedFirewallEnabled = false
		data.MaterializedFirewallUseDefaultRules = false
		data.MaterializedFirewallAllowedRules = ""

		result, err := launcher.workflowContent(context.Background(), &data, workflowTemplate, nil)
		require.NoError(t, err)

		var yamlData any
		err = yaml.Unmarshal([]byte(result), &yamlData)
		require.NoError(t, err, "workflow content with materialized firewall should be valid YAML")

		assert.Contains(t, result, "COPILOT_AGENT_FIREWALL_ENABLED: \"false\"")
		assert.Contains(t, result, "COPILOT_AGENT_FIREWALL_ENABLE_RULESET_ALLOW_LIST: \"false\"")
	})

	t.Run("materialized firewall includes required allowlist", func(t *testing.T) {
		data := baseData()
		data.UseMaterializedFirewall = true
		data.MaterializedFirewallEnabled = true
		data.MaterializedFirewallUseDefaultRules = true
		data.MaterializedFirewallAllowedRules = "custom.test"
		data.AgentFirewallRequiredAllowList = "https://required.test"

		result, err := launcher.workflowContent(context.Background(), &data, workflowTemplate, nil)
		require.NoError(t, err)

		// The materialized ALLOW_LIST should include both required and materialized rules
		assert.Contains(t, result, "https://required.test,custom.test")
	})
}

func TestApplyOrgDefaultRunnerSettings(t *testing.T) {
	t.Parallel()

	launcher := &ActionsLauncher{
		obsv: observability.NewNoopExporters(),
		opts: ActionsLauncherOpts{
			ActionsDefaultRunsOnLabels: runnerlabels.UbuntuLatestLabel,
		},
	}

	tests := []struct {
		name                  string
		defaultRunnerSettings *sweagentdTwirp.GetOrganizationCCARunnerSettingsResponse
		expectedRunsOn        template.HTML
		expectedReturn        string
	}{
		{
			name: "standard runner, sets default",
			defaultRunnerSettings: &sweagentdTwirp.GetOrganizationCCARunnerSettingsResponse{
				Runner: &sweagentdTwirp.GetOrganizationCCARunnerSettingsResponse_StandardRunner{},
			},
			expectedRunsOn: launcher.defaultRunsOnValue(),
			expectedReturn: "",
		},
		{
			name: "single label runner",
			defaultRunnerSettings: &sweagentdTwirp.GetOrganizationCCARunnerSettingsResponse{
				Runner: &sweagentdTwirp.GetOrganizationCCARunnerSettingsResponse_LabeledRunner{
					LabeledRunner: &sweagentdTwirp.LabeledRunner{
						Labels: []string{runnerlabels.SelfHostedLabel},
					},
				},
			},
			expectedRunsOn: template.HTML("\n      labels: self-hosted"),
			expectedReturn: "custom",
		},
		{
			name: "multiple label runner",
			defaultRunnerSettings: &sweagentdTwirp.GetOrganizationCCARunnerSettingsResponse{
				Runner: &sweagentdTwirp.GetOrganizationCCARunnerSettingsResponse_LabeledRunner{
					LabeledRunner: &sweagentdTwirp.LabeledRunner{
						Labels: []string{runnerlabels.SelfHostedLabel, "linux", "x64"},
					},
				},
			},
			expectedRunsOn: template.HTML("\n      labels: [self-hosted, linux, x64]"),
			expectedReturn: "custom",
		},
		{
			name: "labeled runner with group and labels",
			defaultRunnerSettings: &sweagentdTwirp.GetOrganizationCCARunnerSettingsResponse{
				Runner: &sweagentdTwirp.GetOrganizationCCARunnerSettingsResponse_LabeledRunner{
					LabeledRunner: &sweagentdTwirp.LabeledRunner{
						Group:  "my-runners",
						Labels: []string{runnerlabels.SelfHostedLabel, "linux"},
					},
				},
			},
			expectedRunsOn: template.HTML("\n      group: my-runners\n      labels: [self-hosted, linux]"),
			expectedReturn: "custom",
		},
		{
			name: "labeled runner with group only",
			defaultRunnerSettings: &sweagentdTwirp.GetOrganizationCCARunnerSettingsResponse{
				Runner: &sweagentdTwirp.GetOrganizationCCARunnerSettingsResponse_LabeledRunner{
					LabeledRunner: &sweagentdTwirp.LabeledRunner{
						Group: "my-runners",
					},
				},
			},
			expectedRunsOn: template.HTML("\n      group: my-runners"),
			expectedReturn: "custom",
		},
		{
			name: "labeled runner with empty group and labels, no change",
			defaultRunnerSettings: &sweagentdTwirp.GetOrganizationCCARunnerSettingsResponse{
				Runner: &sweagentdTwirp.GetOrganizationCCARunnerSettingsResponse_LabeledRunner{
					LabeledRunner: &sweagentdTwirp.LabeledRunner{
						Labels: []string{},
					},
				},
			},
			expectedRunsOn: launcher.defaultRunsOnValue(),
			expectedReturn: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			initialRunsOn := template.HTML("${{ 'custom-runner' }}")
			data := &workflowData{
				Customization: map[string]template.HTML{
					"runs-on": initialRunsOn,
				},
			}

			result := launcher.applyOrgDefaultRunnerSettings(context.Background(), tt.defaultRunnerSettings, data)

			assert.Equal(t, tt.expectedReturn, result)
			assert.Equal(t, tt.expectedRunsOn, data.Customization["runs-on"])
		})
	}
}

func TestActionsLauncher_ApplyMCPSettingsMCPPermissionGateExpandsDefaults(t *testing.T) {
	ctx := requestctx.NewContext(context.Background())

	// MCP returns no agent / repo permissions — the gate FF should cause
	// the launcher to mint a token with MCPWriteDefault instead of Default.
	mcpMock := func(ctx context.Context, req *sweagentdTwirp.MCPConfigurationForRepositoryRequest) (*sweagentdTwirp.MCPConfigurationForRepositoryResponse, error) {
		mcpConfig := map[string]any{}
		configJSON, err := json.Marshal(mcpConfig)
		if err != nil {
			t.Fatalf("failed to marshal MCP config in test: %v", err)
		}
		return &sweagentdTwirp.MCPConfigurationForRepositoryResponse{
			IsMcpEnabled:         true,
			McpConfigurationJson: string(configJSON),
		}, nil
	}

	tests := []struct {
		name                string
		ffEnabled           bool
		expectedContents    string
		expectedDiscussions string
		expectedIssues      string
		expectedPRs         string
		expectedActions     string
	}{
		{
			name:                "FF off — read-only defaults (Default)",
			ffEnabled:           false,
			expectedContents:    "read",
			expectedDiscussions: "read",
			expectedIssues:      "read",
			expectedPRs:         "read",
			expectedActions:     "read",
		},
		{
			name:                "FF on — read-write defaults (MCPWriteDefault)",
			ffEnabled:           true,
			expectedContents:    "write",
			expectedDiscussions: "write",
			expectedIssues:      "write",
			expectedPRs:         "write",
			expectedActions:     "write",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			noopClient := githubtwirp.NewNoopClient()
			noopClient.NoopSweagentdAPI.MockMCPConfigurationForRepository = mcpMock

			launcher := &ActionsLauncher{
				obsv: observability.NewNoopExporters(),
				ffClient: featureflags.NewNoopClient(map[string]bool{
					featureflags.CopilotSWEAgentMCPPermissionGate: tt.ffEnabled,
				}),
				ghTwirp:     noopClient,
				appProvider: agenticapptest.NewTestProvider(t),
			}

			data := &workflowData{}
			opts := &LaunchAgentOpts{
				Agent: agenticapptest.NewTestCopilot(t),
				// No CustomAgent permissions provider — agent perms remain Unset.
				SessionID: "session-123",
			}

			_, _, effectivePerms, err := launcher.applyMCPSettings(ctx, data, opts, false)
			require.NoError(t, err)

			var perms map[string]string
			err = json.Unmarshal([]byte(effectivePerms), &perms)
			require.NoError(t, err)

			assert.Equal(t, tt.expectedContents, perms["contents"])
			assert.Equal(t, tt.expectedDiscussions, perms["discussions"])
			assert.Equal(t, tt.expectedIssues, perms["issues"])
			assert.Equal(t, tt.expectedPRs, perms["pull_requests"])
			assert.Equal(t, tt.expectedActions, perms["actions"])
			// Metadata is always read.
			assert.Equal(t, "read", perms["metadata"])
		})
	}
}

// TestActionsLauncher_GitTokenIncludeWorkflowsInput exercises the workflow
// scoping helper that produces the COPILOT_AGENT_GIT_TOKEN_INCLUDE_WORKFLOWS
// dynamic-workflow input value.
func TestActionsLauncher_GitTokenIncludeWorkflowsInput(t *testing.T) {
	ctx := requestctx.NewContext(context.Background())
	truth := true
	falsehood := false

	tests := []struct {
		name        string
		flags       map[string]bool
		canModify   *bool
		expected    string
		description string
	}{
		{
			name:        "FF off — returns empty (legacy behavior)",
			flags:       map[string]bool{featureflags.CopilotSWEAgentScopeGitTokenWorkflows: false},
			canModify:   &truth,
			expected:    "",
			description: "FF off must omit the input so dotcom falls back to legacy GIT_TOKEN_PERMISSIONS",
		},
		{
			name:        "FF on + CanWriteWorkflows nil — returns empty",
			flags:       map[string]bool{featureflags.CopilotSWEAgentScopeGitTokenWorkflows: true},
			canModify:   nil,
			expected:    "",
			description: "nil ⇒ no check was performed; do not change the wire format",
		},
		{
			name:        "FF on + &true — returns true",
			flags:       map[string]bool{featureflags.CopilotSWEAgentScopeGitTokenWorkflows: true},
			canModify:   &truth,
			expected:    "true",
			description: "credential is allowed; dotcom keeps workflows:write",
		},
		{
			name:        "FF on + &false — returns false",
			flags:       map[string]bool{featureflags.CopilotSWEAgentScopeGitTokenWorkflows: true},
			canModify:   &falsehood,
			expected:    "false",
			description: "credential is denied; dotcom drops workflows:write",
		},
		{
			name: "FF on + MCP disabled + &false — still returns false (regression)",
			flags: map[string]bool{
				featureflags.CopilotSWEAgentScopeGitTokenWorkflows: true,
				"sweagentd_mcp_disable":                            true,
			},
			canModify:   &falsehood,
			expected:    "false",
			description: "scoping helper must be independent of applyMCPSettings mcp_disable short-circuit",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			launcher := &ActionsLauncher{
				obsv:     observability.NewNoopExporters(),
				ffClient: featureflags.NewNoopClient(tt.flags),
			}
			opts := &LaunchAgentOpts{
				CanWriteWorkflows: tt.canModify,
			}

			got := launcher.gitTokenIncludeWorkflowsInput(ctx, opts)
			assert.Equal(t, tt.expected, got, tt.description)
		})
	}
}
