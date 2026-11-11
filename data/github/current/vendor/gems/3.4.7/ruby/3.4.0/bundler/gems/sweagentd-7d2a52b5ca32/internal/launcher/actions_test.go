package launcher

import (
	"context"
	"encoding/json"
	"fmt"
	"html/template"
	"regexp"
	"strings"
	"testing"

	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/stretchr/testify/assert"
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
	}{
		{
			name: "basic",
			data: workflowData{
				RunName:    "Fixing issue #123",
				Secrets:    []string{},
				Variables:  []string{},
				MCPEnabled: false,
				Customization: &map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"run-name: 'Fixing issue #123'",
				"runs-on: ${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}",
				"timeout-minutes: 59",
			},
			unexpected: []string{},
		},
		{
			name: "run-name not encoded",
			data: workflowData{
				RunName:    "Quote ' should not be encoded",
				Secrets:    []string{},
				Variables:  []string{},
				MCPEnabled: false,
				Customization: &map[string]template.HTML{
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
		},
		{
			name: "different runner via labels",
			data: workflowData{
				RunName:   "PR Review #456",
				Secrets:   []string{},
				Variables: []string{},
				Customization: &map[string]template.HTML{
					"runs-on":         template.HTML("windows-latest"),
					"timeout-minutes": template.HTML("59"),
				},
				MCPEnabled: false,
			},
			expected: []string{
				"run-name: 'PR Review #456'",
				"runs-on: windows-latest",
			},
			unexpected: []string{},
		},
		{
			name: "secrets",
			data: workflowData{
				RunName: "Fixing issue #123",
				Secrets: []string{
					"TEST_SECRET_ONE",
					"TEST_SECRET_TWO",
				},
				Variables:  []string{},
				MCPEnabled: false,
				Customization: &map[string]template.HTML{
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
			unexpected: []string{},
		},
		{
			name: "variables",
			data: workflowData{
				RunName: "Fixing issue #123",
				Secrets: []string{},
				Variables: []string{
					"TEST_VARIABLE_ONE",
					"TEST_VARIABLE_TWO",
				},
				MCPEnabled: false,
				Customization: &map[string]template.HTML{
					"runs-on": template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
				},
			},
			expected: []string{
				"run-name: 'Fixing issue #123'",
				"runs-on: ${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}",
				"TEST_VARIABLE_ONE: ${{ vars.TEST_VARIABLE_ONE }}",
				"TEST_VARIABLE_TWO: ${{ vars.TEST_VARIABLE_TWO }}",
			},
			unexpected: []string{},
		},
		{
			name: "secrets and variables",
			data: workflowData{
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
				Customization: &map[string]template.HTML{
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
			unexpected: []string{},
		},
		{
			name: "secrets take precedence over variables",
			data: workflowData{
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
				Customization: &map[string]template.HTML{
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
		},
		{
			name: "MCP disabled",
			data: workflowData{
				RunName: "Fixing issue #123",
				Secrets: []string{
					"COPILOT_MCP_SECRET_ONE",
				},
				Variables: []string{
					"COPILOT_MCP_VARIABLE_ONE",
				},
				MCPEnabled: false,
				Customization: &map[string]template.HTML{
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
				"if: ${{ env.SHOULD_CONTINUE == 'true' && false }}",
			},
			unexpected: []string{
				"COPILOT_MCP_ENABLED: true",
			},
		},
		{
			name: "MCP enabled, 3P disabled",
			data: workflowData{
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
				Customization: &map[string]template.HTML{
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
				"if: ${{ env.SHOULD_CONTINUE == 'true' && true }}",
				// "Start downloading Playwright MCP server in the background" step is configured with the correct version
				"PLAYWRIGHT_VERSION: \"foo\"",
			},
			unexpected: []string{
				"COPILOT_MCP_ENABLED: false",
				"GITHUB_COPILOT_3P_MCP_ENABLED: true",
				"GITHUB_COPILOT_REMOTE_MCP_ENABLED: true",
			},
		},
		{
			name: "MCP enabled, 3P enabled",
			data: workflowData{
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
				Customization: &map[string]template.HTML{
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
				"if: ${{ env.SHOULD_CONTINUE == 'true' && true }}",
				// "Start downloading Playwright MCP server in the background" step is configured with the correct version
				"PLAYWRIGHT_VERSION: \"foo\"",
			},
			unexpected: []string{
				"COPILOT_MCP_ENABLED: false",
				"GITHUB_COPILOT_3P_MCP_ENABLED: false",
				"GITHUB_COPILOT_REMOTE_MCP_ENABLED: true",
			},
		},
		{
			name: "MCP enabled, 3P enabled, remote enabled",
			data: workflowData{
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
				Customization: &map[string]template.HTML{
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
				"if: ${{ env.SHOULD_CONTINUE == 'true' && true }}",
				// "Start downloading Playwright MCP server in the background" step is configured with the correct version
				"PLAYWRIGHT_VERSION: \"foo\"",
			},
			unexpected: []string{
				"COPILOT_MCP_ENABLED: false",
				"GITHUB_COPILOT_3P_MCP_ENABLED: false",
				"GITHUB_COPILOT_REMOTE_MCP_ENABLED: false",
			},
		},
		{
			name: "development variables appear",
			data: workflowData{
				RunName:                  "Fixing issue #123",
				IsDevelopmentEnvironment: true,
				MCPEnabled:               false,
				Customization: &map[string]template.HTML{
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
		},
		{
			name: "development variables do not appear",
			data: workflowData{
				RunName:                  "Fixing issue #123",
				IsDevelopmentEnvironment: false,
				MCPEnabled:               false,
				Customization: &map[string]template.HTML{
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
		},
		{
			name: "known step names are included",
			data: workflowData{
				RunName:    "Fixing issue #123",
				MCPEnabled: true,
				Customization: &map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected:   ActionsWorkflowJobKnownSteps(),
			unexpected: []string{},
		},
		{
			name: "continues if custom setup steps fail",
			data: workflowData{
				RunName:    "Fixing issue #123",
				MCPEnabled: true,
				Customization: &map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"if: ${{ env.SHOULD_CONTINUE == 'true' && (success() || !cancelled()) }}",
			},
		},
		{
			name: "default entry point is dist/index.js",
			data: workflowData{
				RunName:           "Fixing issue #123",
				MCPEnabled:        false,
				RuntimeEntryPoint: "dist/index.js",
				Customization: &map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"${{ runner.temp }}/copilot-developer-action-main/dist/index.js",
			},
		},
		{
			name: "claude entry point is dist-claude/index.js",
			data: workflowData{
				RunName:           "Fixing issue #123",
				MCPEnabled:        false,
				RuntimeEntryPoint: "dist-claude/index.js",
				Customization: &map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"${{ runner.temp }}/copilot-developer-action-main/dist-claude/index.js",
			},
		},
		{
			name: "codex entry point is dist-codex/index.js",
			data: workflowData{
				RunName:           "Fixing issue #123",
				MCPEnabled:        false,
				RuntimeEntryPoint: "dist-codex/index.js",
				Customization: &map[string]template.HTML{
					"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
					"timeout-minutes": template.HTML("59"),
				},
			},
			expected: []string{
				"${{ runner.temp }}/copilot-developer-action-main/dist-codex/index.js",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			launcher := &ActionsLauncher{
				opts: ActionsLauncherOpts{
					ActionsDefaultRunsOnLabels: "ubuntu-latest",
				},
			}

			result, err := launcher.workflowContent(tt.data, workflowTemplate)
			assert.NoError(t, err, "workflowContent should not return an error")

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
		RunName:    "Fixing issue #123",
		MCPEnabled: true,
		Customization: &map[string]template.HTML{
			"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
			"timeout-minutes": template.HTML("59"),
		},
	}

	result, err := launcher.workflowContent(data, workflowTemplate)
	assert.NoError(t, err, "workflowContent should not return an error")

	stepNameRegex := regexp.MustCompile(`^\s*-\s+name:\s*(.+)$`)

	var stepNames []string
	lines := strings.Split(result, "\n")
	for _, line := range lines {
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
			result := GenerateRunName(tt.opts)
			assert.Equal(t, tt.expected, result, "GenerateRunName should return the expected run name")
		})
	}
}

func TestGenerateSetupStepsErrorComment(t *testing.T) {
	testErr := fmt.Errorf("Oopsie-doo")
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
		err := launcher.handleActionsSetupStepsError(ctx, gh, testErr, opts)
		assert.NoError(t, err, "processCustomActionsWorkflow should not return an error")

		var createCommentCall *github.MethodCall
		for _, call := range gh.(*github.NoopClient).MethodCalls {
			switch call.Method {
			case "CreateComment":
				createCommentCall = &call
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
		err := launcher.handleActionsSetupStepsError(ctx, gh, testErr, opts)
		assert.NoError(t, err, "processCustomActionsWorkflow should not return an error")

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
			Customization: &map[string]template.HTML{
				"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
				"timeout-minutes": template.HTML("59"),
			},
		}
		opts := LaunchAgentOpts{
			CommitCount: 5,
			GitHubRepo:  "legit/repo",
			BranchName:  "legit-branch",
		}
		updatedCustomization, err := launcher.processSetupStepsWorkflow(context.Background(), workflow, data.Customization, opts)
		assert.NoError(t, err, "processCustomActionsWorkflow should not return an error")
		data.Customization = updatedCustomization
		content, err := launcher.workflowContent(data, workflowTemplate)
		assert.NoError(t, err, "workflowContent should not return an error")

		// Note deployments: write should be automatically added here
		assert.Contains(t, content, "    permissions: \n      contents: read\n      deployments: write\n      id-token: write", "permissions are incorrect")

		assert.Contains(t, content, "    runs-on: custom-runner", "runs-on is incorrect")

		// The yaml will be alphabetized, so just check each line - spacing covers the dupes
		expectedLines := strings.Split(workflowMisc, "\n")
		for _, line := range expectedLines {
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
			Customization: &map[string]template.HTML{
				"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
				"timeout-minutes": template.HTML("59"),
			},
		}
		opts := LaunchAgentOpts{
			CommitCount: 5,
			GitHubRepo:  "legit/repo",
			BranchName:  "legit-branch",
		}
		updatedCustomization, err := launcher.processSetupStepsWorkflow(context.Background(), workflow, data.Customization, opts)
		assert.NoError(t, err, "processCustomActionsWorkflow should not return an error")
		data.Customization = updatedCustomization
		content, err := launcher.workflowContent(data, workflowTemplate)
		assert.NoError(t, err, "workflowContent should not return an error")

		// Note deployments: write should be automatically added here
		assert.Contains(t, content, "    permissions: \n      contents: write\n      deployments: write\n", "permissions are incorrect")

		assert.Contains(t, content, "    runs-on: custom-runner", "runs-on is incorrect")

		// The yaml will be alphabetized, so just check each line - spacing covers the dupes
		expectedLines := strings.Split(workflowMisc, "\n")
		for _, line := range expectedLines {
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
			Customization: &map[string]template.HTML{
				"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
				"timeout-minutes": template.HTML("59"),
			},
		}
		opts := LaunchAgentOpts{
			CommitCount: 5,
			GitHubRepo:  "legit/repo",
			BranchName:  "legit-branch",
		}
		updatedCustomization, err := launcher.processSetupStepsWorkflow(context.Background(), workflow, data.Customization, opts)
		assert.NoError(t, err, "processCustomActionsWorkflow should not return an error")
		data.Customization = updatedCustomization
		content, err := launcher.workflowContent(data, workflowTemplate)
		assert.NoError(t, err, "workflowContent should not return an error")

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
			Customization: &map[string]template.HTML{
				"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
				"timeout-minutes": template.HTML("59"),
			},
		}
		opts := LaunchAgentOpts{
			CommitCount: 5,
			GitHubRepo:  "legit/repo",
			BranchName:  "legit-branch",
		}
		updatedCustomization, err := launcher.processSetupStepsWorkflow(context.Background(), workflow, data.Customization, opts)
		assert.NoError(t, err, "processCustomActionsWorkflow should not return an error")
		data.Customization = updatedCustomization
		content, err := launcher.workflowContent(data, workflowTemplate)
		assert.NoError(t, err, "workflowContent should not return an error")

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
			Customization: &map[string]template.HTML{
				"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
				"timeout-minutes": template.HTML("59"),
			},
		}
		opts := LaunchAgentOpts{
			CommitCount: 5,
			GitHubRepo:  "legit/repo",
			BranchName:  "legit-branch",
		}
		updatedCustomization, err := launcher.processSetupStepsWorkflow(context.Background(), workflow, data.Customization, opts)
		assert.Error(t, err, "processCustomActionsWorkflow should return an error")
		assert.Contains(t, err.Error(), "Calling a reusable workflow with the `uses:` keyword is not supported in `copilot-setup-steps` jobs", "error message is incorrect")
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
			Customization: &map[string]template.HTML{
				"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
				"timeout-minutes": template.HTML("59"),
			},
		}
		opts := LaunchAgentOpts{
			CommitCount: 5,
			GitHubRepo:  "legit/repo",
			BranchName:  "legit-branch",
		}
		updatedCustomization, err := launcher.processSetupStepsWorkflow(context.Background(), workflow, data.Customization, opts)
		assert.NoError(t, err, "processCustomActionsWorkflow should not return an error")
		data.Customization = updatedCustomization
		content, err := launcher.workflowContent(data, workflowTemplate)
		assert.NoError(t, err, "workflowContent should not return an error")

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
			Customization: &map[string]template.HTML{
				"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
				"timeout-minutes": template.HTML("59"),
			},
		}
		opts := LaunchAgentOpts{
			CommitCount: 5,
			GitHubRepo:  "legit/repo",
			BranchName:  "legit-branch",
		}
		updatedCustomization, err := launcher.processSetupStepsWorkflow(context.Background(), workflow, data.Customization, opts)
		assert.NoError(t, err, "processCustomActionsWorkflow should not return an error")
		data.Customization = updatedCustomization
		content, err := launcher.workflowContent(data, workflowTemplate)
		assert.NoError(t, err, "workflowContent should not return an error")

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
			Customization: &map[string]template.HTML{
				"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
				"timeout-minutes": template.HTML("59"),
			},
		}
		opts := LaunchAgentOpts{
			CommitCount: 5,
			GitHubRepo:  "legit/repo",
			BranchName:  "legit-branch",
		}
		updatedCustomization, err := launcher.processSetupStepsWorkflow(context.Background(), workflow, data.Customization, opts)
		assert.NoError(t, err, "processCustomActionsWorkflow should not return an error")
		data.Customization = updatedCustomization
		content, err := launcher.workflowContent(data, workflowTemplate)
		assert.NoError(t, err, "workflowContent should not return an error")

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
			Customization: &map[string]template.HTML{
				"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
				"timeout-minutes": template.HTML("59"),
			},
		}
		opts := LaunchAgentOpts{
			CommitCount: 5,
			GitHubRepo:  "legit/repo",
			BranchName:  "legit-branch",
		}
		updatedCustomization, err := launcher.processSetupStepsWorkflow(context.Background(), workflow, data.Customization, opts)
		assert.NoError(t, err, "processCustomActionsWorkflow should not return an error")
		data.Customization = updatedCustomization
		content, err := launcher.workflowContent(data, workflowTemplate)
		assert.NoError(t, err, "workflowContent should not return an error")

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
			Customization: &map[string]template.HTML{
				"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
				"timeout-minutes": template.HTML("59"),
			},
		}
		opts := LaunchAgentOpts{
			CommitCount: 5,
			GitHubRepo:  "legit/repo",
			BranchName:  "legit-branch",
		}
		updatedCustomization, err := launcher.processSetupStepsWorkflow(context.Background(), workflow, data.Customization, opts)
		assert.NoError(t, err, "processCustomActionsWorkflow should not return an error")
		data.Customization = updatedCustomization
		content, err := launcher.workflowContent(data, workflowTemplate)
		assert.NoError(t, err, "workflowContent should not return an error")

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
			data.Customization = &map[string]template.HTML{
				"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
				"timeout-minutes": template.HTML("59"),
			}
			workflow := workflowPrefix + checkoutStep
			updatedCustomization, err := launcher.processSetupStepsWorkflow(context.Background(), workflow, data.Customization, opts)
			assert.NoError(t, err, "processCustomActionsWorkflow should not return an error")
			data.Customization = updatedCustomization
			content, err := launcher.workflowContent(data, workflowTemplate)
			assert.NoError(t, err, "workflowContent should not return an error")

			// Verify actions steps
			assert.Contains(t, content, "      - uses: actions/checkout@v4\n        with:\n", "uses is incorrect")
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
			data.Customization = &map[string]template.HTML{
				"runs-on":         template.HTML("${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}"),
				"timeout-minutes": template.HTML("59"),
			}
			workflow := workflowPrefix + checkoutStep
			updatedCustomization, err := launcher.processSetupStepsWorkflow(context.Background(), workflow, data.Customization, opts)
			assert.NoError(t, err, "processCustomActionsWorkflow should not return an error")
			data.Customization = updatedCustomization
			content, err := launcher.workflowContent(data, workflowTemplate)
			assert.NoError(t, err, "workflowContent should not return an error")

			// Verify actions steps
			assert.Contains(t, content, "      - uses: actions/checkout@v4\n        with:\n", "uses is incorrect")
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
			Customization: &map[string]template.HTML{
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
		updatedCustomization, err := launcher.processSetupStepsWorkflow(context.Background(), workflow, data.Customization, opts)
		assert.NoError(t, err, "processCustomActionsWorkflow should not return an error")
		data.Customization = updatedCustomization
		content, err := launcher.workflowContent(data, workflowTemplate)
		assert.NoError(t, err, "workflowContent should not return an error")

		// Verify properties are correct - but order can be different so check each individually
		assert.Contains(t, content, "      - uses: actions/checkout@v4\n        with:\n", "uses is incorrect")
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
		assert.Contains(t, content, fmt.Sprintf("%s: ${{ '' }}", name), fmt.Sprintf("variable %s is not correct", name))
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
			obsv: observability.NewNoopExporters(),
			ffClient: featureflags.NewNoopClient(map[string]bool{
				"copilot_swe_agent_safe_runtime_deploy": true,
			}),
			opts: ActionsLauncherOpts{
				AgentLauncherOpts: AgentLauncherOpts{
					CopilotAPIURL:     "https://api.original.com",
					AgentCallbackURL:  "https://callback.original.com",
					UploadsURL:        "https://uploads.github.com/user-attachments/assets",
					GitHubCommitLogin: "original-user",
					GitHubCommitEmail: "original@example.com",
					ModelOverride:     "",
					AgentDebug:        false,
					Environment:       "test",
					MCPEnabled:        false,
					AgentTimeoutMin:   60,
					RuntimeVersion:    "runtime-original-sha",
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
		}

		// Create overrides that should take precedence
		overrides := &variables{
			"COPILOT_AGENT_CALLBACK_URL": {Value: "https://callback.override.com"},
			"COPILOT_AGENT_JOB_ID":       {Value: "override-job-999"},
			"COPILOT_AGENT_MODEL":        {Value: "gpt-4-override"},
			"CUSTOM_OVERRIDE_VAR":        {Value: "custom-value"},
		}

		result, err := launcher.environmentVariables(context.Background(), opts, overrides)
		assert.NoError(t, err, "environmentVariables should not return an error")

		// Verify that the result contains the expected top-level inputs
		assert.Contains(t, result, "COPILOT_AGENT_INPUTS", "should contain COPILOT_AGENT_INPUTS")
		assert.Contains(t, result, "COPILOT_AGENT_ACTOR_ID", "should contain COPILOT_AGENT_ACTOR_ID")
		assert.Contains(t, result, "COPILOT_AGENT_RUNTIME_VERSION", "should contain COPILOT_AGENT_RUNTIME_VERSION")

		// Parse the COPILOT_AGENT_INPUTS JSON to check the actual variables
		inputsJSON := result["COPILOT_AGENT_INPUTS"]
		assert.NotEmpty(t, inputsJSON, "COPILOT_AGENT_INPUTS should not be empty")

		var inputs map[string]string
		err = json.Unmarshal([]byte(inputsJSON), &inputs)
		assert.NoError(t, err, "should be able to unmarshal COPILOT_AGENT_INPUTS")

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
			"COPILOT_AGENT_RUNTIME_VERSION should use original value")

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
		}

		result, err := launcher.environmentVariables(context.Background(), opts, nil)
		assert.NoError(t, err, "environmentVariables should handle nil overrides")
		assert.Contains(t, result, "COPILOT_AGENT_INPUTS", "should still contain COPILOT_AGENT_INPUTS")
	})

	t.Run("empty overrides should not affect variables", func(t *testing.T) {
		launcher := &ActionsLauncher{
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
		}

		emptyOverrides := &variables{}

		result, err := launcher.environmentVariables(context.Background(), opts, emptyOverrides)
		assert.NoError(t, err, "environmentVariables should handle empty overrides")

		inputsJSON := result["COPILOT_AGENT_INPUTS"]
		var inputs map[string]string
		err = json.Unmarshal([]byte(inputsJSON), &inputs)
		assert.NoError(t, err, "should be able to unmarshal COPILOT_AGENT_INPUTS")

		// Verify original values are preserved
		assert.Equal(t, "test-job-original", inputs["COPILOT_AGENT_JOB_ID"],
			"COPILOT_AGENT_JOB_ID should use original value when no override")
	})
}

func TestProblemStatementGzip(t *testing.T) {
	// Test that the problem statement is gzipped correctly.
	al := &ActionsLauncher{
		ffClient: featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentGZipProblemStatement: true,
		}),
	} // Don't need many env vars
	ps := strings.Repeat("This is a test problem statement that should be gzipped correctly. ", 10000)
	opts := LaunchAgentOpts{
		SessionID:        "i-should-not-be-gzipped",
		ProblemStatement: ps,
	}
	vars, err := al.environmentVariables(context.Background(), opts, nil)
	assert.NoError(t, err)
	assert.NotEmpty(t, vars)
	assert.Contains(t, vars, "COPILOT_AGENT_INPUTS")

	// Expected compressed length is 3931 instead of the giant 894100 base64 encoded string.
	assert.Len(t, vars["COPILOT_AGENT_INPUTS"], 3931)

	// Make sure the prompt has a "gz:" prefix
	assert.Contains(t, vars["COPILOT_AGENT_INPUTS"], "COPILOT_AGENT_PROMPT\":\"gz:")
	// Make sure not everything is gzipped
	assert.Contains(t, vars["COPILOT_AGENT_INPUTS"], "COPILOT_AGENT_SESSION_ID\":\"i-should-not-be-gzipped")
}

func TestProblemStatementWithoutGzip(t *testing.T) {
	// Test that the problem statement is gzipped correctly.
	al := &ActionsLauncher{
		ffClient: featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentGZipProblemStatement: false,
		}),
	} // Don't need many env vars
	ps := strings.Repeat("This is a test problem statement that should be gzipped correctly. ", 10000)
	opts := LaunchAgentOpts{
		SessionID:        "i-should-not-be-gzipped",
		ProblemStatement: ps,
	}
	vars, err := al.environmentVariables(context.Background(), opts, nil)
	assert.NoError(t, err)
	assert.NotEmpty(t, vars)
	assert.Contains(t, vars, "COPILOT_AGENT_INPUTS")

	// The problem statement here is giant, so the total length is BIG.
	assert.Len(t, vars["COPILOT_AGENT_INPUTS"], 894100)

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
			expectedAgentCallbackURL:  "https://callback.example.com",
			expectedUploadURL:         "https://uploads.github.com/user-attachments/assets",
			expectedDownloadURL:       "https://api.githubcopilot.com/agents/swe-staging/runtime",
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
			expectedAgentCallbackURL:  "https://callback.example.com",
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
			expectedAgentCallbackURL:  "https://callback.example.com",
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
		},
		{
			name:                      "development environment (default case)",
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
			expectedAgentCallbackURL:  "https://callback.example.com",
			expectedUploadURL:         "https://uploads.github.com/user-attachments/assets",
			expectedDownloadURL:       "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := context.Background()

			// Set up tenant slug in context if provided
			if tt.tenantSlug != "" {
				ctx = requestctx.AddData(ctx, &requestctx.CtxData{})
				err := requestctx.AddTenantSlug(ctx, tt.tenantSlug)
				assert.NoError(t, err)
			}

			// Create ActionsLauncher with test options
			launcher := &ActionsLauncher{
				opts: ActionsLauncherOpts{
					AgentLauncherOpts: AgentLauncherOpts{
						CopilotAPIURL:    tt.copilotAPIURL,
						AgentCallbackURL: tt.agentCallbackURL,
						UploadsURL:       tt.expectedUploadURL,
						DownloadsURL:     tt.expectedDownloadURL,
					},
				},
			}

			// Call the method under test

			copilotAPIURL, actionDownloadURL, agentCallbackURL, uploadURL, downloadURL, err := launcher.getURLsForEnvironment(ctx, tt.environment, tt.environmentName)

			// Assert error expectation
			if tt.expectError {
				assert.Error(t, err)
				assert.Empty(t, copilotAPIURL)
				assert.Empty(t, actionDownloadURL)
				assert.Empty(t, agentCallbackURL)
				assert.Empty(t, uploadURL)
				assert.Empty(t, downloadURL)
			} else {
				assert.NoError(t, err)
				assert.Equal(t, tt.expectedCopilotAPIURL, copilotAPIURL)
				assert.Equal(t, tt.expectedActionDownloadURL, actionDownloadURL)
				assert.Equal(t, tt.expectedAgentCallbackURL, agentCallbackURL)
				assert.Equal(t, tt.expectedUploadURL, uploadURL)
				assert.Equal(t, tt.expectedDownloadURL, downloadURL)
			}
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
			result, err := ReplaceFirewallTenantPlaceholders(ctx, opts)

			// Assert results
			if tt.expectError {
				assert.Error(t, err)
				assert.Contains(t, err.Error(), tt.expectedErrorMsg)
			} else {
				assert.NoError(t, err)
				assert.Equal(t, tt.expectedRequiredAllowList, result.AgentFirewallRequiredAllowList)
			}
		})
	}
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
			name: "claude takes precedence when both feature flags are enabled",
			featureFlags: map[string]bool{
				featureflags.CopilotSWEAgentRuntimeEntryPointClaude: true,
				featureflags.CopilotSWEAgentRuntimeEntryPointCodex:  true,
			},
			expectedEntryPoint: "dist-claude/index.js",
		},
		{
			name: "default entry point when both feature flags are disabled",
			featureFlags: map[string]bool{
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

			data := &workflowData{}
			launcher.applyRuntimeSetup(ctx, actorID, data)
			assert.Equal(t, tt.expectedEntryPoint, data.RuntimeEntryPoint)
		})
	}
}
