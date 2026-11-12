// Package skills provides operations for listing and fetching skills.
package skills

import (
	"regexp"
	"strings"
	"unicode/utf8"

	"github.com/github/sweagentd/internal/goerrors"
	"gopkg.in/yaml.v3"
)

var (
	// ErrMalformedConfig is returned when the skill configuration is not well-formed
	// (e.g., invalid YAML frontmatter, validation failures). This error is treated as
	// non-fatal during skill resolution, allowing fallback to other sources.
	ErrMalformedConfig = goerrors.New("malformed skill configuration")

	// SkillNameRegex matches valid skill names: starts with alphanumeric,
	// then allows alphanumeric, dots, underscores, hyphens, and spaces.
	// Matches CLI: /^[a-zA-Z0-9][a-zA-Z0-9._\- ]*$/
	SkillNameRegex = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9._\- ]*$`)
)

const (
	// MaxNameLength is the maximum length of the name field (matches CLI).
	MaxNameLength = 64
	// MaxDescriptionLength is the maximum length of the description field (matches CLI).
	MaxDescriptionLength = 1024
	// MaxContentLength is the maximum length of the skill content/prompt.
	MaxContentLength = 30000
	// MaxAllowedToolsCount is the maximum number of allowed tools.
	MaxAllowedToolsCount = 200
	// MaxToolNameLength is the maximum length of a tool name.
	MaxToolNameLength = 63
)

// parseSkillConfig parses the SKILL.md content and extracts configuration.
func parseSkillConfig(contents, defaultName string) (*Config, error) {
	// Normalize CRLF to LF for consistent frontmatter parsing
	contents = strings.ReplaceAll(contents, "\r\n", "\n")

	cfg := &Config{
		Name:          defaultName,
		UserInvocable: true, // Default
		Content:       contents,
	}

	// Check for YAML frontmatter
	if !strings.HasPrefix(contents, "---") {
		// No frontmatter, just content
		return cfg, nil
	}

	// Find the end of frontmatter
	rest := contents[3:]
	endIdx := strings.Index(rest, "\n---")
	if endIdx == -1 {
		// No closing ---, treat as no frontmatter
		return cfg, nil
	}

	frontmatter := rest[:endIdx]

	// Parse YAML frontmatter
	var fm skillFrontmatter
	err := yaml.Unmarshal([]byte(frontmatter), &fm)
	if err != nil {
		return nil, goerrors.Errorf("%w: failed to parse YAML frontmatter: %w", ErrMalformedConfig, err)
	}

	// Apply frontmatter values
	if fm.Name != "" {
		cfg.Name = fm.Name
	}
	if fm.Description != "" {
		cfg.Description = fm.Description
	}
	if fm.AllowedTools != "" {
		cfg.AllowedTools = parseAllowedTools(fm.AllowedTools)
	}
	if fm.UserInvocable != nil {
		cfg.UserInvocable = *fm.UserInvocable
	}
	if fm.DisableModelInvocation != nil {
		cfg.DisableModelInvocation = *fm.DisableModelInvocation
	}

	// Validate field constraints (matching CLI validation)
	// Validate name format: must start with alphanumeric, then allow alphanumeric, dots, underscores, hyphens, spaces
	if cfg.Name != "" && !SkillNameRegex.MatchString(cfg.Name) {
		return nil, goerrors.Errorf("%w: \"name\" must contain only letters, numbers, hyphens, underscores, dots, and spaces, and must start with a letter or number", ErrMalformedConfig)
	}
	if utf8.RuneCountInString(cfg.Name) > MaxNameLength {
		return nil, goerrors.Errorf("%w: \"name\" exceeds max length of %d", ErrMalformedConfig, MaxNameLength)
	}
	if utf8.RuneCountInString(cfg.Description) > MaxDescriptionLength {
		return nil, goerrors.Errorf("%w: \"description\" exceeds max length of %d", ErrMalformedConfig, MaxDescriptionLength)
	}
	if utf8.RuneCountInString(cfg.Content) > MaxContentLength {
		return nil, goerrors.Errorf("%w: content exceeds max length of %d", ErrMalformedConfig, MaxContentLength)
	}
	if len(cfg.AllowedTools) > MaxAllowedToolsCount {
		return nil, goerrors.Errorf("%w: more than %d allowed-tools specified", ErrMalformedConfig, MaxAllowedToolsCount)
	}
	for _, tool := range cfg.AllowedTools {
		if utf8.RuneCountInString(tool) > MaxToolNameLength {
			return nil, goerrors.Errorf("%w: tool name exceeds max length of %d", ErrMalformedConfig, MaxToolNameLength)
		}
	}

	return cfg, nil
}

// skillFrontmatter represents the YAML frontmatter structure in SKILL.md.
type skillFrontmatter struct {
	Name                   string `yaml:"name"`
	Description            string `yaml:"description"`
	AllowedTools           string `yaml:"allowed-tools"` // Comma-separated string like "Read, Grep"
	UserInvocable          *bool  `yaml:"user-invocable"`
	DisableModelInvocation *bool  `yaml:"disable-model-invocation"`
}

// parseAllowedTools parses a comma-separated list of tool names.
func parseAllowedTools(s string) []string {
	if s == "" {
		return nil
	}
	parts := strings.Split(s, ",")
	result := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			result = append(result, p)
		}
	}
	return result
}
