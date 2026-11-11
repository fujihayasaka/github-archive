package launcher

import (
	"bytes"
	"context"
	_ "embed"
	"errors"
	"fmt"
	"html/template"
	"maps"
	"net/url"
	"path"
	"regexp"
	"strings"

	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/joberrors"
	"github.com/github/sweagentd/internal/proxima"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/spokes"
	"github.com/google/uuid"
	"gopkg.in/yaml.v3"
)

// Will accept .yml or .yaml
const customSetupStepsFileName = ".github/workflows/copilot-setup-steps"

// Env, var, secret names or name regex strings that need to be scrubbed out of any injected custom Actions steps
var secretsToScrub = []string{
	"GITHUB_COPILOT_API_TOKEN",
	"GITHUB_COPILOT_GIT_TOKEN",
	"GITHUB_COPILOT_INTEGRATION_ID",
	"GITHUB_COPILOT_ACTION_DOWNLOAD_URL",
	"GITHUB_COPILOT_[a-zA-Z0-9_]*",
	"COPILOT_MCP_ENABLED",
	"COPILOT_MCP_[a-zA-Z0-9_]*",
	"COPILOT_INTEGRATION_ID_OVERRIDE",
	"CAPI_HMAC_KEY_OVERRIDE",
}

// Map of customizable properties and whether or not the property name is already in actions_workflow.yaml
var actionsCustomizationProperties = map[string]bool{
	"steps":           true,
	"runs-on":         true,
	"timeout-minutes": true,
	"permissions":     false,
	"snapshot":        false,
	"container":       false,
	"services":        false,
}

// The real regexp is generated from the above list
var scrubbingRegexp *regexp.Regexp

// SetupStepsResult contains the result of applying custom setup steps.
type SetupStepsResult struct {
	// Customization contains the customized workflow properties.
	Customization map[string]template.HTML
	// WasApplied indicates whether custom setup steps were successfully applied.
	WasApplied bool
	// RunsOn contains the actual runs-on value from the setup steps, or empty if not specified.
	RunsOn string
}

func (a *ActionsLauncher) applySetupSteps(ctx context.Context, client github.ClientInterface, opts *LaunchAgentOpts, data *workflowData, copilotAPIURL string) (*SetupStepsResult, error) {
	logger := a.obsv.LoggerWithTelemetry(ctx)

	logger.Info("Processing copilot-setup-steps.yml/yaml in repo if present.")
	content, err := a.downloadSetupStepsWorkflow(ctx, opts)
	if err != nil {
		return nil, goerrors.Errorf("failed to download copilot-setup-steps.yml/yaml from repo: %w", err)
	}
	if len(content) == 0 {
		return nil, nil
	}

	// If we found content, process it, otherwise just continue on
	updatedCustomization, runsOnValue, err := a.processSetupStepsWorkflow(ctx, string(content), data.Customization, opts, copilotAPIURL)
	if err != nil {
		logger.WithError(err).Info("Failed to process content in copilot-setup-steps.yml/yaml.")
		// Gracefully handle this scenario and exit - can be due to a user error, so consider it info
		innerError := a.handleActionsSetupStepsError(ctx, client, err, opts)
		if innerError != nil {
			return nil, goerrors.Errorf("unable to comment on PR or issue about copilot-setup-steps.yml/yaml processing failure: %w; failed to handle the error: %w", err, innerError)
		}
		return nil, goerrors.Errorf("failed to process copilot-setup-steps.yml/yaml: %w", err)
	}

	logger.Info("Successfully scrubbed copilot-setup-steps.yml/yaml.")

	return &SetupStepsResult{
		Customization: updatedCustomization,
		WasApplied:    true,
		RunsOn:        runsOnValue,
	}, nil
}

func (a *ActionsLauncher) downloadSetupStepsWorkflow(ctx context.Context, opts *LaunchAgentOpts) ([]byte, error) {
	// We will try to get ".github/workflows/copilot-setup-steps.yml" or ".github/workflows/copilot-setup-steps.yaml"
	// from the repo. This location requires higher privs to modify and we'll parse it in a way it can still have
	// "workflow_dispatch" in it so you can quickly run and test it. However, we should always get the contents from
	// the default branch to avoid the agent breaking itself and other exploits.
	var lastErr error
	for _, ext := range []string{"yml", "yaml"} {
		filePath := fmt.Sprintf("%s.%s", customSetupStepsFileName, ext)
		blob, _, err := a.spokes.ReadBlob(ctx, uint64(opts.GitHubRepoID), filePath)
		if err == nil {
			return blob, nil
		}
		if errors.Is(err, spokes.ErrNotFound) {
			// Try the next extension
			lastErr = err
			continue
		}
		// For non-NotFound errors, return immediately
		return nil, goerrors.Errorf("failed to read setup steps workflow file %s: %w", filePath, err)
	}
	return nil, goerrors.Errorf("failed to download setup steps workflow file: %w", lastErr)
}

func (a *ActionsLauncher) handleActionsSetupStepsError(ctx context.Context, client github.ClientInterface, originalErr error, opts *LaunchAgentOpts) error {
	// TODO(colbylwilliams): Move some of this to joberrors
	var tmpl *template.Template
	var tmplErr error
	var telemetryKey string
	if opts.Action == "fix" {
		telemetryKey = "comment-setup-steps-invalid"
		tmpl, tmplErr = template.New("setup_steps_error_fix").Parse(setupStepsErrorFixTemplate)
	} else {
		telemetryKey = "issue-setup-steps-invalid"
		tmpl, tmplErr = template.New("setup_steps_error_fix_comment").Parse(setupStepsErrorFixCommentTemplate)
	}
	if tmplErr != nil {
		return goerrors.Errorf("failed to parse template: %w", tmplErr)
	}

	var buf bytes.Buffer
	err := tmpl.Execute(&buf, &struct {
		Login       string
		Error       template.HTML
		IssueNumber int
		Telemetry   template.HTML
	}{
		Login:       opts.ActorLogin,
		Error:       template.HTML(fmt.Sprintf("%v", originalErr)), //nolint:gosec // This is controlled input
		IssueNumber: opts.IssueNumber,
		Telemetry:   template.HTML(joberrors.GetTelemetryHTMLComment(telemetryKey)), //nolint:gosec // This is controlled input
	})
	if err != nil {
		return goerrors.Errorf("failed to execute template: %w", err)
	}
	body := buf.String()
	if body == "" {
		return goerrors.New("failed to generate comment body")
	}

	tags, _, _ := requestctx.ToTelemetry(ctx, nil)
	a.obsv.Statter.Counter("actionsSetupSteps.processingFailed", tags, 1)

	if opts.PRNumber != 0 {
		err = joberrors.CreateErrorComment(ctx, a.obsv, client, opts.GitHubRepoID, opts.PRNumber, body)
		if err != nil {
			a.obsv.LogAndReportError(ctx, err, "failed to create setup steps error comment on PR")
		}
	}

	return nil
}

func (a *ActionsLauncher) processSetupStepsWorkflow(ctx context.Context, content string, customization map[string]template.HTML, opts *LaunchAgentOpts, copilotAPIURL string) (map[string]template.HTML, string, error) {
	logger := a.obsv.LoggerWithTelemetry(ctx)

	// Clone the customization map so we don't modify the original
	updatedCustomization := map[string]template.HTML{}
	maps.Copy(updatedCustomization, customization)

	// Track the actual runs-on value
	runsOnValue := ""

	var err error
	if scrubbingRegexp == nil {
		scrubbingRegexp, err = generateScrubbingRegexp()
		if scrubbingRegexp == nil || err != nil {
			return nil, "", goerrors.Errorf("failed to generate scrubbing regex: %w", err)
		}
	}

	var rawYaml map[string]any
	err = yaml.Unmarshal([]byte(content), &rawYaml)
	if err != nil {
		return nil, "", goerrors.Errorf("failed to unmarshal copilot-setup-steps.yaml: %w", err)
	}

	// Extract jobs section
	jobs, ok := rawYaml["jobs"].(map[string]any)
	if !ok {
		return nil, "", goerrors.New("no valid jobs found in copilot-setup-steps.yaml")
	}

	// Find the prep steps job
	customizationJob, ok := jobs["copilot-setup-steps"].(map[string]any)
	if !ok {
		return nil, "", goerrors.New("no `copilot-setup-steps` job found in your `copilot-setup-steps.yml` workflow file. Please ensure you have a single job named `copilot-setup-steps`. For more details, see https://gh.io/copilot/actions-setup-steps")
	}

	// Error if there is a uses: key in the job
	if _, ok := customizationJob["uses"]; ok {
		logger.Info("Found unsupported `uses:` keyword in copilot-setup-steps job")
		return nil, "", goerrors.New("calling a reusable workflow with the `uses:` keyword is not supported in `copilot-setup-steps` jobs. Please specify the `steps` directly. For more details, see https://gh.io/copilot/actions-setup-steps")
	}

	// Go through properties we want and scrub them
	for propName := range actionsCustomizationProperties {
		propYaml, ok := customizationJob[propName]
		if !ok {
			continue
		}
		switch propName {
		case "runs-on": // if runs-on is being customized and store its value
			runsOnValue = "custom" // if it's not a string (e.g., array or object), serialize it
			if runsOnStr, ok := propYaml.(string); ok {
				runsOnValue = runsOnStr
			}
		case "steps": // adjust any actions/checkout steps to force disable cred persistence, commit count
			propYaml, err = adjustActionsCheckoutSteps(propYaml, opts)
			if err != nil {
				return nil, "", goerrors.Errorf("failed to adjust actions/checkout steps: %w", err)
			}
		case "permissions": // set deployments to write if permissions is set - need this to deploy to Copilot
			propYaml = addDeploymentWriteToPermissionVal(propYaml)
		default:
			// No special handling
		}

		propYaml = scrubNode(propYaml, scrubbingRegexp)

		if propName == "steps" {
			propYaml, err = a.addActionsLogging(ctx, propYaml, opts, copilotAPIURL)
			if err != nil {
				return nil, "", goerrors.Errorf("failed to add logging to actions steps: %w", err)
			}
		}

		formattedProp, err := formatProperty(propYaml, propName)
		if err != nil {
			return nil, "", goerrors.Errorf("failed to format property %s: %w", propName, err)
		}

		updatedCustomization[propName] = formattedProp
	}

	// If updatedCustomization does not have a permissions property, see if there's a value at the top level and use that instead
	if _, ok := updatedCustomization["permissions"]; !ok {
		if propYaml, ok := rawYaml["permissions"]; ok {
			// Set deployments to write if permissions is set - need this to deploy to Copilot
			propYaml = addDeploymentWriteToPermissionVal(propYaml)
			formattedProp, err := formatProperty(scrubNode(propYaml, scrubbingRegexp), "permissions")
			if err != nil {
				return nil, "", goerrors.Errorf("failed to format property permissions: %w", err)
			}
			updatedCustomization["permissions"] = formattedProp
		}
	}

	return updatedCustomization, runsOnValue, nil
}

// Set deployments to write if permissions is set - need this to deploy to Copilot
func addDeploymentWriteToPermissionVal(permissions any) any {
	switch v := permissions.(type) {
	case map[string]any:
		v["deployments"] = "write"
		return v
	case string:
		switch v {
		case "write-all":
			return v
		case "read-all":
			// Reset it to just deployments write if we don't know what to do
			return map[string]string{
				"deployments":     "write",
				"actions":         "read",
				"attestations":    "read",
				"checks":          "read",
				"contents":        "read",
				"issues":          "read",
				"models":          "read",
				"discussions":     "read",
				"packages":        "read",
				"pages":           "read",
				"pull-requests":   "read",
				"security-events": "read",
				"statuses":        "read",
			}
		default:
			// Reset it to just deployments write if we don't know what to do
			return map[string]string{
				"deployments": "write",
			}
		}
	default:
		return map[string]string{
			"deployments": "write",
		}
	}
}

func formatProperty(scrubbedProp any, propName string) (template.HTML, error) {
	// If actionsCustomizationProperties[propName] is true if the property name is already in actions_workflow.yaml
	prefix := ""
	if !actionsCustomizationProperties[propName] {
		prefix = fmt.Sprintf("%s: ", propName)
	}
	switch v := scrubbedProp.(type) {
	case nil:
		// Do nothing - wasn't specified in workflow
	case bool, int, int64:
		return template.HTML(fmt.Sprintf("%s%v", prefix, v)), nil //nolint:gosec // This is controlled input
	case string:
		if v != "" {
			return template.HTML(fmt.Sprintf("%s%s", prefix, v)), nil //nolint:gosec // This is controlled input
		}
	default:
		scrubbedYaml, err := yaml.Marshal(v)
		if err != nil {
			return template.HTML(""), goerrors.Errorf("failed to marshal property %s: %w", propName, err)
		}
		// Fix explicit indentation indicators like |4, |6, |8 that break GitHub Actions
		// Replace them with simple |- which is always valid
		re := regexp.MustCompile(`\|\d+[+-]?`)
		scrubbedYaml = re.ReplaceAll(scrubbedYaml, []byte("|-"))
		// Handle "{}" which comes across like an empty interface
		if string(scrubbedYaml) == "{}\n" {
			return template.HTML(fmt.Sprintf("%s{}\n", prefix)), nil //nolint:gosec // This is controlled input
		}
		scrubbedText := fmt.Sprintf("%s\n%s", prefix, strings.TrimSpace(string(scrubbedYaml)))
		// Properly indent for the correct spot in the actions_workflow.yaml file
		// while preserving YAML block scalar syntax
		scrubbedText = indentYAMLForWorkflow(scrubbedText)
		return template.HTML(scrubbedText), nil //nolint:gosec // This is controlled input
	}
	return template.HTML(""), goerrors.Errorf("failed to format property %s", propName)
}

func indentYAMLForWorkflow(yamlText string) string {
	// Use improved indentation
	lines := strings.Split(yamlText, "\n")
	result := make([]string, len(lines))

	for i, line := range lines {
		switch {
		case i == 0:
			result[i] = line
		case strings.TrimSpace(line) == "":
			result[i] = ""
		default:
			result[i] = "      " + line
		}
	}

	return strings.Join(result, "\n")
}

func generateScrubbingRegexp() (*regexp.Regexp, error) {
	if len(secretsToScrub) == 0 {
		return nil, nil
	}

	// Build patterns
	prefixPatterns := []string{}
	for _, name := range secretsToScrub {
		for _, prefix := range []string{"secrets", "env", "vars"} {
			prefixPatterns = append(prefixPatterns,
				fmt.Sprintf("%s\\.%s", prefix, name),                            // Handle the common <prefix>.NAMEGOESHERE pattern
				fmt.Sprintf("%s\\s*\\[\\s*['\"]?%s['\"]?\\s*\\]", prefix, name)) // Handle the less common secrets['NAMEGOESHERE'] pattern
		}
		// Handle the following by removing the name itself from any strings
		// - id: my-secret-name
		//   run: echo "name=GITHUB_COPILOT_API_TOKEN" >> "$GITHUB_OUTPUT"
		// - name: Dump a token
		//   run: echo "${{ secrets[steps.my-secret-name.outputs.name] }}" | rev
		prefixPatterns = append(prefixPatterns, name)
	}
	// Remove json dumping patterns - e.g. ${{ toJson(secrets) }}
	for _, prefix := range []string{"secrets", "env", "vars"} {
		prefixPatterns = append(prefixPatterns, fmt.Sprintf("toJson\\s*\\(\\s*%s\\s*\\)", prefix))
	}

	scrubRegexp, err := regexp.Compile(fmt.Sprintf("(?i)(%s)", strings.Join(prefixPatterns, "|")))
	if err != nil {
		return nil, goerrors.Errorf("failed to compile regex: %w", err)
	}
	return scrubRegexp, nil
}

func scrubNode(node any, scrubRegexp *regexp.Regexp) any {
	if node == nil {
		return nil
	}

	switch v := node.(type) {
	case string:
		return scrubRegexp.ReplaceAllString(v, "''")
	case []any:
		for i, item := range v {
			v[i] = scrubNode(item, scrubRegexp)
		}
		return v
	case []map[string]any:
		for i, item := range v {
			scrubbedItem, ok := scrubNode(item, scrubRegexp).(map[string]any)
			if ok {
				v[i] = scrubbedItem
			}
		}
		return v
	case map[string]any:
		// Handle both map types in a common way
		for k, val := range v {
			v[k] = scrubNode(val, scrubRegexp)
		}
		return v
	case map[any]any:
		// Handle both map types in a common way
		for k, val := range v {
			v[k] = scrubNode(val, scrubRegexp)
		}
		return v
	default:
		// For all other types (int, bool, etc.) just return as is
		return v
	}
}

func adjustActionsCheckoutSteps(stepsYaml any, opts *LaunchAgentOpts) ([]any, error) {
	var steps []any
	switch v := stepsYaml.(type) {
	case []any:
		steps = v
	default:
		return nil, goerrors.New("steps is not a slice")
	}
	result := make([]any, len(steps))
	repoRegexp := regexp.MustCompile(fmt.Sprintf("(?i)({\\s*github\\.repository\\s*})|({\\s*github\\[\\s*['\"]?repository['\"]?\\s*\\]\\s*})|(^\\s*['\"]?%s['\"]?\\s*$)", opts.GitHubRepo))
	refRegexp := regexp.MustCompile(fmt.Sprintf("(?i)({\\s*github\\.ref_name\\s*})|({\\s*github\\[\\s*['\"]?ref_name['\"]?\\s*\\]\\s*})|({\\s*github\\.head_ref\\s*})|({\\s*github\\[\\s*['\"]?head_ref['\"]?\\s*\\]\\s*})|({\\s*github\\.ref\\s*})|({\\s*github\\[\\s*['\"]?ref['\"]?\\s*\\]\\s*})|(^\\s*['\"]?%s['\"]?\\s*$)", opts.BranchName))

	for i, stepInterface := range steps {
		var step map[string]any
		switch v := stepInterface.(type) {
		case map[string]any:
			step = v
		default:
			return nil, goerrors.New("step is not a map")
		}

		// Process actions/checkout steps
		uses, ok := step["uses"].(string)
		if ok && strings.HasPrefix(uses, "actions/checkout@") {
			// Get or create a "with" property
			var with map[string]any
			switch v := step["with"].(type) {
			case map[string]any:
				with = make(map[string]any)
				maps.Copy(with, v)
			default:
				with = make(map[string]any)
			}
			step["with"] = with
			// Always force persist-credentials to false
			with["persist-credentials"] = false
			// Set the fetch depth to the PR commit count if this is for the current repository and branch
			repository, repoOK := with["repository"].(string)
			ref, refOK := with["ref"].(string)
			if (!repoOK || repository == "" || repoRegexp.MatchString(repository)) &&
				(!refOK || ref == "" || refRegexp.MatchString(ref)) {
				// We want to increase the commit count by 1 to get the commit right before the PR, so the LLM can completely restart if prompted.
				// Use a minimum of depth 2 rather than 1 since we expect push. See  https://stackoverflow.com/questions/66431436/pushing-to-github-after-a-shallow-clone-is-horribly-slow
				// This logic also exists in the runtime for if scenarios where it performs the clone - including evals, but won't happen if its already cloned.
				commitCount := max(opts.CommitCount+1, 2)
				with["fetch-depth"] = commitCount
			}
		}

		result[i] = step
	}
	return result, nil
}

func (a *ActionsLauncher) addActionsLogging(ctx context.Context, stepsYaml any, opts *LaunchAgentOpts, copilotAPIURL string) (any, error) {
	steps, ok := stepsYaml.([]any)
	if !ok {
		return nil, goerrors.New("steps is not a slice")
	}

	u, err := url.Parse(copilotAPIURL)
	if err != nil {
		return nil, goerrors.Errorf("error parsing copilot API URL: %w", err)
	}

	u.Host, err = proxima.ReplaceTenantPlaceholder(ctx, u.Host)
	if err != nil {
		return nil, goerrors.Errorf("error replacing tenant placeholder in copilot API URL: %w", err)
	}

	u.Path = path.Join(u.Path, "agents/sessions/"+opts.SessionID+"/logs")

	sessionURL := u.String()
	result := make([]any, 0, len(steps)*5) // Capacity for OS-specific steps (2 before + 1 original + 2 after per step)
	for _, stepInterface := range steps {
		step, ok := stepInterface.(map[string]any)
		if !ok {
			return nil, goerrors.New("step is not a map")
		}

		// Each step has a session log step before it
		stepName, ok := step["name"].(string)
		if !ok || stepName == "" {
			stepName, _ = step["uses"].(string)
		}

		// Make sure related steps share the same ID and tool call ID
		id := uuid.NewString()
		toolCallID := uuid.NewString()
		// Add OS-specific session log steps (before the user step)
		result = append(result,
			sessionLogStepLinux(id, toolCallID, stepName, sessionURL, false),
			sessionLogStepWindows(id, toolCallID, stepName, sessionURL, false))
		// Short-circuit if a prerequisite step failed
		if step["if"] != nil {
			existingCondition := fmt.Sprintf("%v", step["if"])
			existingCondition = strings.TrimSpace(existingCondition)
			existingCondition = strings.TrimPrefix(existingCondition, "${{")
			existingCondition = strings.TrimSuffix(existingCondition, "}}")
			existingCondition = strings.TrimSpace(existingCondition)
			step["if"] = fmt.Sprintf("${{ env.SHOULD_CONTINUE == 'true' && %s }}", existingCondition)
		} else {
			step["if"] = "${{ env.SHOULD_CONTINUE == 'true' }}"
		}
		result = append(result, step,
			// Add OS-specific session log steps (after the user step)
			sessionLogStepLinux(id, toolCallID, stepName, sessionURL, true),
			sessionLogStepWindows(id, toolCallID, stepName, sessionURL, true))
	}
	return result, nil
}

// sessionLogStepLinux generates a Linux-specific session logging step.
func sessionLogStepLinux(id, tcID, stepName, sessionURL string, isFinished bool) map[string]any {
	logStepName := "Starting User Configured Setup Step (Linux)"
	if isFinished {
		logStepName = "Finished User Configured Setup Step (Linux)"
	}

	var runCommand string
	if isFinished {
		successOutput := "Finished successfully - for the full output, see the verbose logs"
		failureOutput := "<error>An error occurred while running this setup step. See verbose log for details.</error>"
		const errorReportedVar = "GITHUB_COPILOT_SETUP_ERROR_REPORTED"

		successCommand := generateSessionLogCommandLinux(sessionURL, stepName, successOutput)
		failureCommand := generateSessionLogCommandLinux(sessionURL, stepName, failureOutput)
		runCommand = fmt.Sprintf("if [ \"${{ job.status }}\" = \"failure\" ]; then if [ -n \"$%s\" ]; then exit; else echo \"%s=1\" >> $GITHUB_ENV; %s; fi else %s; fi",
			errorReportedVar, errorReportedVar, failureCommand, successCommand)
	} else {
		runCommand = generateSessionLogCommandLinux(sessionURL, stepName, "")
	}

	return map[string]any{
		"name":  logStepName,
		"run":   runCommand,
		"shell": "bash",
		"env": map[string]any{
			"GITHUB_COPILOT_LOG_ID":       id,
			"GITHUB_COPILOT_TOOL_CALL_ID": tcID,
			"GITHUB_COPILOT_API_TOKEN":    "${{ secrets.GITHUB_COPILOT_API_TOKEN }}",
		},
		"if": "${{ runner.os == 'Linux' && env.SHOULD_CONTINUE == 'true' }}",
	}
}

// sessionLogStepWindows generates a Windows-specific session logging step using PowerShell.
func sessionLogStepWindows(id, tcID, stepName, sessionURL string, isFinished bool) map[string]any {
	logStepName := "Starting User Configured Setup Step (Windows)"
	if isFinished {
		logStepName = "Finished User Configured Setup Step (Windows)"
	}

	var runCommand string
	if isFinished {
		successOutput := "Finished successfully - for the full output, see the verbose logs"
		failureOutput := "<error>An error occurred while running this setup step. See verbose log for details.</error>"
		// Set the error reported variable before the session logs command to avoid subsequent steps reporting again
		const errorReportedVar = "GITHUB_COPILOT_SETUP_ERROR_REPORTED"

		successCommand := generateSessionLogCommandWindows(sessionURL, stepName, successOutput)
		failureCommand := generateSessionLogCommandWindows(sessionURL, stepName, failureOutput)
		runCommand = fmt.Sprintf(`if ("${{ job.status }}" -eq "failure") { if ($env:%s) { exit } else { echo "%s=1" >> $env:GITHUB_ENV; %s } } else { %s }`,
			errorReportedVar, errorReportedVar, failureCommand, successCommand)
	} else {
		runCommand = generateSessionLogCommandWindows(sessionURL, stepName, "")
	}

	return map[string]any{
		"name":  logStepName,
		"run":   runCommand,
		"shell": "pwsh",
		"env": map[string]any{
			"GITHUB_COPILOT_LOG_ID":       id,
			"GITHUB_COPILOT_TOOL_CALL_ID": tcID,
			"GITHUB_COPILOT_API_TOKEN":    "${{ secrets.GITHUB_COPILOT_API_TOKEN }}",
		},
		"if": "${{ runner.os == 'Windows' && env.SHOULD_CONTINUE == 'true' }}",
	}
}

func generateSessionLogCommandLinux(sessionURL, name, output string) string {
	return fmt.Sprintf("\"$RUNNER_TEMP/copilot-developer-action-main/script/session-log.sh\" %s %q %q", sessionURL, name, output)
}

func generateSessionLogCommandWindows(sessionURL, name, output string) string {
	return fmt.Sprintf("& \"$env:RUNNER_TEMP\\copilot-developer-action-main\\script\\session-log.ps1\" %s %q %q", sessionURL, name, output)
}

//go:embed setup_steps_error_fix.md
var setupStepsErrorFixTemplate string

//go:embed setup_steps_error_fix_comment.md
var setupStepsErrorFixCommentTemplate string
