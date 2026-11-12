package memoryhttp

import (
	"bytes"
	"fmt"
	"strconv"
	"strings"
	"text/template"

	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/memory/core"
)

const (
	// maxMemoriesForContext is the maximum number of recent memories included in the context prompt.
	maxMemoriesForContext = 20

	// storeInstructionsPromptVersion is the version of the store-instructions prompt.
	storeInstructionsPromptVersion PromptVersion = "1.0.4"

	// storeInstructionsPromptVersionWithVoting is the version of the store-instructions prompt when voting guidance is enabled.
	storeInstructionsPromptVersionWithVoting PromptVersion = "1.1.4"

	// storeInstructionsPromptVersionWithScope is the version of the store-instructions prompt when user-scoped memory language is enabled.
	storeInstructionsPromptVersionWithScope PromptVersion = "1.2.4"

	// storeInstructionsPromptVersionWithVotingAndScope is the version of the store-instructions prompt when both voting guidance and user-scoped memory language are enabled.
	storeInstructionsPromptVersionWithVotingAndScope PromptVersion = "1.3.4"

	// memoriesContextPromptVersion is the version of the memories context prompt.
	memoriesContextPromptVersion PromptVersion = "1.0.5"

	// memoriesContextPromptVersionWithVoting is the version of the memories context prompt when voting guidance is enabled.
	memoriesContextPromptVersionWithVoting PromptVersion = "1.1.5"

	// combinedStoreInstructionsPromptVersion is the version of the store-instructions prompt for the combined endpoint.
	combinedStoreInstructionsPromptVersion PromptVersion = "2.0.4"

	// combinedStoreInstructionsPromptVersionWithVoting is the version of the store-instructions prompt for the combined endpoint when voting guidance is enabled.
	combinedStoreInstructionsPromptVersionWithVoting PromptVersion = "2.1.4"

	// combinedStoreInstructionsPromptVersionWithScope is the version of the store-instructions prompt for the combined endpoint when user-scoped memory language is enabled.
	combinedStoreInstructionsPromptVersionWithScope PromptVersion = "2.2.4"

	// combinedStoreInstructionsPromptVersionWithVotingAndScope is the version of the store-instructions prompt for the combined endpoint when both voting guidance and user-scoped memory language are enabled.
	combinedStoreInstructionsPromptVersionWithVotingAndScope PromptVersion = "2.3.4"

	// combinedMemoriesContextPromptVersion is the version of the memories context prompt for the combined endpoint.
	combinedMemoriesContextPromptVersion PromptVersion = "2.0.5"

	// combinedMemoriesContextPromptVersionWithVoting is the version of the memories context prompt for the combined endpoint when voting guidance is enabled.
	combinedMemoriesContextPromptVersionWithVoting PromptVersion = "2.1.5"

	// storeToolDefinitionVersion is the version of the store_memory tool definition schema.
	storeToolDefinitionVersion PromptVersion = "1.0.2"

	// storeToolDefinitionVersionWithScope is the version of the store_memory tool definition schema when user-scoped memory is enabled.
	// The runtime uses this version to select the input schema that includes the "scope" parameter.
	storeToolDefinitionVersionWithScope PromptVersion = "1.1.2"

	// voteToolDefinitionVersion is the version of the vote_memory tool definition schema.
	voteToolDefinitionVersion PromptVersion = "1.1.0"

	// storeMemoryToolName is the canonical tool name referenced in prompts.
	storeMemoryToolName = "store_memory"

	// voteMemoryToolName is the canonical tool name referenced in prompts when memory voting is enabled.
	voteMemoryToolName = "vote_memory"

	// copilotSettingsURL is the personal Copilot Memory settings URL referenced
	// in memory-deletion guidance.
	copilotSettingsURL = "https://github.com/settings/copilot/memory"

	// copilotMemoryDocsURL is the public docs URL for Copilot Memory referenced
	// in memory-deletion guidance.
	copilotMemoryDocsURL = "https://docs.github.com/en/copilot/how-tos/use-copilot-agents/copilot-memory"
)

const (
	votingFeatureMinorVersionOffset                = 1
	storeInstructionsUserScopeMinorVersionOffset   = 2
	storeToolDefinitionUserScopeMinorVersionOffset = 1
)

// storeMemoryToolDescription is the short description for the store_memory tool sent to the LLM.
// When UserScopedEnabled is true, the description mentions user preferences;
// when false, it steers the agent away from storing user preferences as repository memories.
const storeMemoryToolDescription = `Store a fact in memory, so that it can be used in future code generation or review tasks. The fact should be a clear and concise statement about the codebase's conventions, structure, logic, or usage{{if .UserScopedEnabled}}, or about the current user's preferences{{end}}. It may be based on the code itself or on information provided by the user{{if not .UserScopedEnabled}} about the codebase{{end}}.`

// voteMemoryToolDescription is the short description for the vote_memory tool sent to the LLM.
const voteMemoryToolDescription = `Vote on an existing memory by passing its exact fact text; the tool requires an exact string match. Use direction "upvote" for memories you have verified as useful and correct. Use direction "downvote" for memories that are incorrect or outdated, or that the user has asked you to delete, remove, or forget.`

const storeInstructionsTemplateSource = backtickTemplateHelper + `If you come across an important fact that could help in future code generation or review tasks, beyond the current task, use the {{.StoreToolName}} tool to store it. Facts may be gleaned from the codebase itself or learned from user input or feedback. 
Such facts might include:
* Conventions, preferences, or best practices that are specific to this codebase{{if .UserScopedEnabled}} or to the current user's workflow{{end}}.
* Important information about the structure or logic of the codebase.
* Commands for linting, building the code, or running tests which have been verified through a successful run.{{if .UserScopedEnabled}}
* User-provided preferences, instructions the current user explicitly asks you to remember, or high-confidence patterns learned implicitly from the current user's inputs.{{end}}

Examples:
* "Use ErrKind wrapper for every public API error"
* "Prefer ExpectNoLog helper over silent nil checks in tests"
* "Always use Python typing"
* "Use html_escape as a sanitizer to avoid cross site scripting vulnerabilities"
* "The code can be built with npm run build and tested with npm run test"{{if .UserScopedEnabled}}
* "Branch names should be prepended with the author's username"{{end}}

{{if .UserScopedEnabled}}Call {{.StoreToolName}} before your reply whenever the user:
- States a preference, rule, or workflow expectation phrased as a general directive that applies across tasks (e.g., "Never rewrite git history", "Always run lint before committing", "Branch names should start with my username")
- Asks you to remember something explicitly ("Remember that…", "From now on…", "Going forward…")
- Corrects your behavior with a generalizing qualifier ("from now on", "always when…", "in general") rather than as a one-off or task-related correction ("let's choose X over Y", "skip lint for now")
- Describes durable context about their tooling, conventions, or how they work — provided it is generally applicable and likely to remain true across all sessions

Remember: **If you don't store a memory, the preference is lost the moment this session ends.** Do not tell the user you will remember a preference without also calling {{.StoreToolName}} when one of the triggers above applies. "Got it, I'll remember" without a tool call is a bug.
{{end -}}
Only store facts that meet the following criteria:
* are likely to have actionable implications to a future task
* are independent of changes you are making as part of your current task, and will remain relevant if your current code isn't merged
* are unlikely to change over time
* can't always be inferred from a limited code sample{{if not .UserScopedEnabled}}
* are relevant to the codebase and all users who contribute to the codebase, not one specific user's preferences{{end}}
* contain no secrets or sensitive data.

Do not store:
* Ephemeral or task-specific instructions ("for this PR, use commit message X", "skip lint for now", "I prefer the second option")
* Anything qualified with "for now", "in this case", "this session", "temporarily", or similar — these are explicitly ephemeral even when phrased as "remember…"
* Anything the user explicitly asks you not to remember
* Personal data covered by GDPR Article 9, including health, religion, ethnicity, sexual orientation, political views, biometrics, and union membership
* Secrets, credentials, tokens, API keys; employer-confidential information; personally identifiable information; financial, legal, or other sensitive personal information; or anything the user shared in confidence or may reasonably expect to remain private
{{- if .VotingEnabled}}

Before calling {{.StoreToolName}}, first check whether the same fact already appears in the list of recent memories shown in the prompt. If it does, do not store a duplicate; use {{.VoteToolName}} instead — direction "upvote" if you have verified the existing memory is useful and correct, direction "downvote" if it is incorrect, outdated, or if the user has asked you to delete, remove, or forget it.

Use {{.StoreToolName}} only for genuinely new facts that are not already represented in the list of recent memories shown in the prompt, or to store a new memory reflecting the current reality for an outdated fact you down-voted.{{end}}{{if not .HasMemories}}

If the user asks you to delete, remove, or forget a memory, you cannot delete it yourself. Direct the user to delete the memory manually from the appropriate GitHub Copilot Memory UI: repository memories can be deleted from the repository's Settings > Copilot > Memory page, and user memories can be deleted from personal Copilot settings at {{.CopilotSettingsURL}}. You can also point them to the Copilot Memory documentation at {{.CopilotMemoryDocsURL}}.{{end}}
{{if .UserScopedEnabled}}
{{if .UserLogin}}The current user is @{{.UserLogin}}. {{end}}Only store user preferences for the current user — do not infer user preferences from other users' observed behavior.

**Choose scope based on who the fact applies to, not who stated it.** The same words can map to different scopes depending on intent — "never rewrite git history in this repository" is a repository fact, while "I prefer concise commit messages" is a user preference. When intent is genuinely ambiguous, ask the user.
- user — applies to this user **across any repository**: personal preferences, communication style, workflow habits, individual conventions.
- repository — applies to **anyone** working in this repository: codebase conventions, build/test commands, architecture facts, documented team-wide practices.
- For repository facts derived from code or documentation, cite file paths or example locations. When the source is direct user input, cite as {{$backtick}}User input: "<exact quotation>"{{$backtick}} regardless of scope.
{{end}}
Call {{.StoreToolName}} once per individual fact, convention, or preference. Don't forget to include the {{if .UserScopedEnabled}}"reason", "citations", and "scope"{{else}}"reason" and "citations"{{end}} arguments in the {{.StoreToolName}} tool call, explaining why you are storing this information and where it comes from.

Before calling {{.StoreToolName}}, think: Will this help with future tasks? If unsure, skip the call.`

const memoriesTemplateDefinitions = `{{define "memories-list"}}{{range $i, $memory := .}}{{if gt $i 0}}

{{end}}**{{$memory.Subject}}**
- Fact: {{$memory.Fact}}
- Citations: {{$memory.CitationsText}}{{end}}{{end}}`

// Go raw string literals cannot contain backticks, so keep the template-local
// backtick definition in an interpreted string fragment.
const backtickTemplateHelper = "{{- $backtick := \"`\" -}}"

const memoriesContextTemplateSource = memoriesTemplateDefinitions + backtickTemplateHelper + `The following are recent memories from previous agent interactions.{{if .UserScopedEnabled}} They may include repository facts (visible to all repository collaborators) and user preferences (visible only to the current user).{{end}} These memories may contain useful context about conventions, patterns, and practices. However, be aware that memories might be obsolete or incorrect or may not apply to your current task. Use the citations provided to verify the accuracy of any relevant memory before relying on it. Do not treat user-specific preferences as repository conventions or apply them to other users; think whether a memory should indeed be applied to all users who contribute to the codebase.

{{if .RepoMemories}}{{if and .ShowRepoMemoriesHeader .RepoNWO}}## Repository memories for {{$backtick}}{{.RepoNWO.Owner}}/{{.RepoNWO.Repo}}{{$backtick}}

{{end}}{{template "memories-list" .RepoMemories}}{{end}}{{if and .RepoMemories .UserMemories}}

{{end}}{{if .UserMemories}}## User memories{{if .UserLogin}} for @{{.UserLogin}}{{end}}

{{template "memories-list" .UserMemories}}{{end}}

Be sure to consider these stored facts carefully. Consider whether any are relevant to your current task. If they are, verify their current applicability before using them to inform your work.
{{if and .UserScopedEnabled .UserMemories}}
For memories based on user input (i.e., citations starting with "User input"), use your best judgment to decide whether the memory seems valid, consistent with observed behavior and conventions, and relevant in the current context.
{{end}}
{{if .VotingEnabled}}If you come across a memory that you're able to verify and that you find useful, use the {{.VoteToolName}} tool with direction "upvote". Pass the memory fact exactly as it appears above: the tool requires an exact string match to retrieve the correct memory.

If you come across a fact that's incorrect or outdated, use the {{.VoteToolName}} tool with direction "downvote". Pass the memory fact exactly as it appears above to ensure an exact string match.

If you discover a genuinely new fact that is not already represented above, or you want to store a new memory reflecting the current reality for an outdated fact you down-voted, use the {{.StoreToolName}} tool to store the new fact.

If the user asks you to delete, remove, or forget a memory, you cannot delete it yourself. If the memory appears in your prompt, use {{.VoteToolName}} with direction "downvote" to deprioritize it. In addition, direct the user to delete the memory manually from the appropriate GitHub Copilot Memory UI: repository memories can be deleted from the repository's Settings > Copilot > Memory page, and user memories can be deleted from personal Copilot settings at {{.CopilotSettingsURL}}. You can also point them to the Copilot Memory documentation at {{.CopilotMemoryDocsURL}}.{{else}}If you come across a memory that you're able to verify and that you find useful, you should use the {{.StoreToolName}} tool to store the same fact again. Only recent memories are retained, so storing the fact again will cause it to be retained longer.

If you come across a fact that's incorrect or outdated, you should use the {{.StoreToolName}} tool to store a new fact that reflects the current reality.

If the user asks you to delete, remove, or forget a memory, you cannot delete it yourself. Direct the user to delete the memory manually from the appropriate GitHub Copilot Memory UI: repository memories can be deleted from the repository's Settings > Copilot > Memory page, and user memories can be deleted from personal Copilot settings at {{.CopilotSettingsURL}}. You can also point them to the Copilot Memory documentation at {{.CopilotMemoryDocsURL}}.{{end}}`

type promptMemoryTemplateData struct {
	Subject       string
	Fact          string
	CitationsText string
}

type storeInstructionsTemplateData struct {
	StoreToolName        string
	VoteToolName         string
	UserScopedEnabled    bool
	VotingEnabled        bool
	HasMemories          bool
	UserLogin            string
	CopilotSettingsURL   string
	CopilotMemoryDocsURL string
}

type memoriesContextTemplateData struct {
	StoreToolName          string
	VoteToolName           string
	VotingEnabled          bool
	UserScopedEnabled      bool
	ShowRepoMemoriesHeader bool
	RepoMemories           []promptMemoryTemplateData
	UserMemories           []promptMemoryTemplateData
	RepoNWO                *core.RepoNWO
	UserLogin              string
	CopilotSettingsURL     string
	CopilotMemoryDocsURL   string
}

type promptOptions struct {
	votingEnabled     bool
	userScopedEnabled bool
}

type promptOption func(*promptOptions)

func withVoting(votingEnabled bool) promptOption {
	return func(opts *promptOptions) {
		opts.votingEnabled = votingEnabled
	}
}

// withUserScoped enables user-scoped memory language in the prompt.
// When enabled, the preamble references the user's workflow, examples include
// user-scoped facts, and the call guidance mentions the "scope" argument.
func withUserScoped(enabled bool) promptOption {
	return func(opts *promptOptions) {
		opts.userScopedEnabled = enabled
	}
}

func resolvePromptOptions(opts ...promptOption) promptOptions {
	options := promptOptions{}
	for _, opt := range opts {
		if opt != nil {
			opt(&options)
		}
	}
	return options
}

// promptBuilder builds a single-scope MemoryPromptResponse from a flat list of memories.
type promptBuilder struct {
	memories []*core.Memory
	options  promptOptions
}

func newPromptBuilder(memories []*core.Memory, opts ...promptOption) promptBuilder {
	return promptBuilder{
		memories: memories,
		options:  resolvePromptOptions(opts...),
	}
}

func (b promptBuilder) memoriesCount() int { return len(b.memories) }
func (b promptBuilder) hasMemories() bool  { return b.memoriesCount() > 0 }

func (b promptBuilder) buildResponse() (MemoryPromptResponse, error) {
	prompt := ""
	var err error
	if b.hasMemories() {
		prompt, err = renderMemoriesContext(b.memories, b.options.votingEnabled)
		if err != nil {
			return MemoryPromptResponse{}, err
		}
	}

	storeInstructions, err := resolveStoreInstructions(b.options.votingEnabled, b.hasMemories(), b.options.userScopedEnabled, "")
	if err != nil {
		return MemoryPromptResponse{}, err
	}

	storeToolDef, err := storeToolDefinition(b.options.userScopedEnabled)
	if err != nil {
		return MemoryPromptResponse{}, err
	}
	return MemoryPromptResponse{
		StoreInstructions: StoreInstructionsPrompt{
			Prompt:        storeInstructions,
			PromptVersion: resolveStoreInstructionsVersion(b.options.votingEnabled, b.hasMemories(), b.options.userScopedEnabled),
		},
		MemoriesContext: MemoriesContextPrompt{
			Prompt:        prompt,
			PromptVersion: resolveMemoriesContextVersion(memoriesContextPromptVersion, b.options.votingEnabled, b.hasMemories()),
			MemoriesCount: b.memoriesCount(),
		},
		ToolDefinition:      storeToolDef,
		StoreToolDefinition: storeToolDef,
		VoteToolDefinition:  voteToolDefinition(b.options.votingEnabled),
	}, nil
}

// combinedPromptBuilder builds a multi-scope MemoryPromptResponse with separate
// repository and user memory sections.
type combinedPromptBuilder struct {
	repoMemories []*core.Memory
	userMemories []*core.Memory
	repoNWO      *core.RepoNWO
	userLogin    string
	options      promptOptions
}

func newCombinedPromptBuilder(repoMemories, userMemories []*core.Memory, repoNWO *core.RepoNWO, userLogin string, opts ...promptOption) combinedPromptBuilder {
	// Repo memories cannot be rendered without a repo NWO, so clear them
	// to keep counts consistent with prompt content.
	if repoNWO == nil {
		repoMemories = nil
	}
	return combinedPromptBuilder{
		repoMemories: repoMemories,
		userMemories: userMemories,
		repoNWO:      repoNWO,
		userLogin:    userLogin,
		options:      resolvePromptOptions(opts...),
	}
}

func (b combinedPromptBuilder) hasMemories() bool {
	return len(b.repoMemories)+len(b.userMemories) > 0
}

func (b combinedPromptBuilder) buildResponse() (MemoryPromptResponse, error) {
	prompt := ""
	var err error
	if b.hasMemories() {
		prompt, err = renderCombinedMemoriesContext(b.repoMemories, b.userMemories, b.repoNWO, b.userLogin, b.options.votingEnabled, b.options.userScopedEnabled)
		if err != nil {
			return MemoryPromptResponse{}, err
		}
	}

	repoMemoriesCount := len(b.repoMemories)
	userMemoriesCount := len(b.userMemories)

	storeInstructions, err := resolveStoreInstructions(b.options.votingEnabled, b.hasMemories(), b.options.userScopedEnabled, b.userLogin)
	if err != nil {
		return MemoryPromptResponse{}, err
	}
	storeInstructionsVersion := resolveCombinedStoreInstructionsVersion(b.options.votingEnabled, b.hasMemories(), b.options.userScopedEnabled)

	storeToolDef, err := storeToolDefinition(b.options.userScopedEnabled)
	if err != nil {
		return MemoryPromptResponse{}, err
	}

	return MemoryPromptResponse{
		StoreInstructions: StoreInstructionsPrompt{
			Prompt:        storeInstructions,
			PromptVersion: storeInstructionsVersion,
		},
		MemoriesContext: MemoriesContextPrompt{
			Prompt:            prompt,
			PromptVersion:     resolveMemoriesContextVersion(combinedMemoriesContextPromptVersion, b.options.votingEnabled, b.hasMemories()),
			MemoriesCount:     repoMemoriesCount + userMemoriesCount,
			RepoMemoriesCount: &repoMemoriesCount,
			UserMemoriesCount: &userMemoriesCount,
		},
		ToolDefinition:      storeToolDef,
		StoreToolDefinition: storeToolDef,
		VoteToolDefinition:  voteToolDefinition(b.options.votingEnabled),
	}, nil
}

// --- Shared helpers ---

func resolveStoreInstructions(votingEnabled, hasMemories, userScopedEnabled bool, userLogin string) (string, error) {
	tmpl, err := parsePromptTemplate("store-instructions", storeInstructionsTemplateSource)
	if err != nil {
		return "", err
	}
	return renderTemplate(tmpl, storeInstructionsTemplateData{
		StoreToolName:        storeMemoryToolName,
		VoteToolName:         voteMemoryToolName,
		UserScopedEnabled:    userScopedEnabled,
		VotingEnabled:        votingEnabled && hasMemories,
		HasMemories:          hasMemories,
		UserLogin:            userLogin,
		CopilotSettingsURL:   copilotSettingsURL,
		CopilotMemoryDocsURL: copilotMemoryDocsURL,
	})
}

func resolveStoreInstructionsVersion(votingEnabled, hasMemories, userScopedEnabled bool) PromptVersion {
	return incrementPromptMinorVersion(storeInstructionsPromptVersion, storeInstructionsMinorVersionOffset(votingEnabled, hasMemories, userScopedEnabled))
}

func resolveCombinedStoreInstructionsVersion(votingEnabled, hasMemories, userScopedEnabled bool) PromptVersion {
	return incrementPromptMinorVersion(combinedStoreInstructionsPromptVersion, storeInstructionsMinorVersionOffset(votingEnabled, hasMemories, userScopedEnabled))
}

func storeInstructionsMinorVersionOffset(votingEnabled, hasMemories, userScopedEnabled bool) int {
	offset := 0
	if votingEnabled && hasMemories {
		offset += votingFeatureMinorVersionOffset
	}
	if userScopedEnabled {
		offset += storeInstructionsUserScopeMinorVersionOffset
	}
	return offset
}

func resolveMemoriesContextVersion(base PromptVersion, votingEnabled, hasMemories bool) PromptVersion {
	if votingEnabled && hasMemories {
		return incrementPromptMinorVersion(base, votingFeatureMinorVersionOffset)
	}
	return base
}

func renderMemoriesContext(memories []*core.Memory, votingEnabled bool) (string, error) {
	tmpl, err := parsePromptTemplate("memories-context", memoriesContextTemplateSource)
	if err != nil {
		return "", err
	}
	return renderTemplate(tmpl, memoriesContextTemplateData{
		StoreToolName:        storeMemoryToolName,
		VoteToolName:         voteMemoryToolName,
		VotingEnabled:        votingEnabled,
		RepoMemories:         toPromptMemories(memories),
		CopilotSettingsURL:   copilotSettingsURL,
		CopilotMemoryDocsURL: copilotMemoryDocsURL,
	})
}

func renderCombinedMemoriesContext(repoMemories, userMemories []*core.Memory, repoNWO *core.RepoNWO, userLogin string, votingEnabled, userScopedEnabled bool) (string, error) {
	if repoNWO == nil {
		repoMemories = nil
	}
	tmpl, err := parsePromptTemplate("memories-context", memoriesContextTemplateSource)
	if err != nil {
		return "", err
	}
	data := memoriesContextTemplateData{
		StoreToolName:          storeMemoryToolName,
		VoteToolName:           voteMemoryToolName,
		VotingEnabled:          votingEnabled,
		UserScopedEnabled:      userScopedEnabled,
		ShowRepoMemoriesHeader: repoNWO != nil,
		RepoMemories:           toPromptMemories(repoMemories),
		UserMemories:           toPromptMemories(userMemories),
		RepoNWO:                repoNWO,
		UserLogin:              userLogin,
		CopilotSettingsURL:     copilotSettingsURL,
		CopilotMemoryDocsURL:   copilotMemoryDocsURL,
	}
	return renderTemplate(tmpl, data)
}

func toPromptMemories(memories []*core.Memory) []promptMemoryTemplateData {
	if len(memories) == 0 {
		return nil
	}
	result := make([]promptMemoryTemplateData, 0, len(memories))
	for _, m := range memories {
		result = append(result, toPromptMemory(m))
	}
	return result
}

func toPromptMemory(memory *core.Memory) promptMemoryTemplateData {
	return promptMemoryTemplateData{
		Subject:       memory.Subject,
		Fact:          memory.Fact,
		CitationsText: renderMemoryCitations(memory),
	}
}

func renderMemoryCitations(memory *core.Memory) string {
	if len(memory.Citations) == 0 {
		return "<none>"
	}
	return strings.Join(memory.Citations, ", ")
}

func renderTemplate(tmpl *template.Template, data any) (string, error) {
	var buf bytes.Buffer
	err := tmpl.Execute(&buf, data)
	if err != nil {
		return "", goerrors.Errorf("failed to render prompt template %q: %w", tmpl.Name(), err)
	}
	return buf.String(), nil
}

func parsePromptTemplate(name, source string) (*template.Template, error) {
	tmpl, err := template.New(name).Option("missingkey=error").Parse(source)
	if err != nil {
		return nil, goerrors.Errorf("failed to parse prompt template %q: %w", name, err)
	}
	return tmpl, nil
}

func incrementPromptMinorVersion(base PromptVersion, minorIncrement int) PromptVersion {
	parts := strings.Split(string(base), ".")
	if len(parts) != 3 {
		panic(fmt.Sprintf("invalid prompt version %q", base))
	}

	major, err := strconv.Atoi(parts[0])
	if err != nil {
		panic(fmt.Sprintf("invalid prompt version %q: %v", base, err))
	}
	minor, err := strconv.Atoi(parts[1])
	if err != nil {
		panic(fmt.Sprintf("invalid prompt version %q: %v", base, err))
	}
	patch, err := strconv.Atoi(parts[2])
	if err != nil {
		panic(fmt.Sprintf("invalid prompt version %q: %v", base, err))
	}

	return PromptVersion(fmt.Sprintf("%d.%d.%d", major, minor+minorIncrement, patch))
}

func storeToolDefinition(userScopedEnabled bool) (ToolDefinition, error) {
	version := storeToolDefinitionVersion
	if userScopedEnabled {
		version = incrementPromptMinorVersion(version, storeToolDefinitionUserScopeMinorVersionOffset)
	}
	description, err := resolveStoreToolDescription(userScopedEnabled)
	if err != nil {
		return ToolDefinition{}, goerrors.Errorf("failed to resolve store tool description: %w", err)
	}
	return ToolDefinition{
		Name:              storeMemoryToolName,
		Description:       description,
		DefinitionVersion: version,
	}, nil
}

func resolveStoreToolDescription(userScopedEnabled bool) (string, error) {
	tmpl, err := parsePromptTemplate("store-tool-description", storeMemoryToolDescription)
	if err != nil {
		return "", err
	}
	return renderTemplate(tmpl, struct{ UserScopedEnabled bool }{UserScopedEnabled: userScopedEnabled})
}

func voteToolDefinition(votingEnabled bool) *ToolDefinition {
	if !votingEnabled {
		return nil
	}
	return &ToolDefinition{
		Name:              voteMemoryToolName,
		Description:       voteMemoryToolDescription,
		DefinitionVersion: voteToolDefinitionVersion,
	}
}
