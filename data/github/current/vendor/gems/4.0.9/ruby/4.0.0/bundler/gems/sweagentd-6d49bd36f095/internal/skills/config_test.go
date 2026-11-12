package skills

import (
	"fmt"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestParseSkillConfig(t *testing.T) {
	t.Run("no frontmatter returns defaults", func(t *testing.T) {
		contents := "This is just content with no frontmatter."
		cfg, err := parseSkillConfig(contents, "default-name")

		require.NoError(t, err)
		assert.Equal(t, "default-name", cfg.Name)
		assert.Equal(t, "", cfg.Description)
		assert.True(t, cfg.UserInvocable)
		assert.False(t, cfg.DisableModelInvocation)
		assert.Nil(t, cfg.AllowedTools)
		assert.Equal(t, contents, cfg.Content)
	})

	t.Run("unclosed frontmatter returns defaults", func(t *testing.T) {
		contents := "---\nname: test\nThis has no closing delimiter"
		cfg, err := parseSkillConfig(contents, "default-name")

		require.NoError(t, err)
		assert.Equal(t, "default-name", cfg.Name)
	})

	t.Run("basic frontmatter with name and description", func(t *testing.T) {
		contents := `---
name: my-skill
description: A helpful skill
---
This is the skill content.`

		cfg, err := parseSkillConfig(contents, "default-name")

		require.NoError(t, err)
		assert.Equal(t, "my-skill", cfg.Name)
		assert.Equal(t, "A helpful skill", cfg.Description)
		assert.True(t, cfg.UserInvocable)
		assert.False(t, cfg.DisableModelInvocation)
		assert.Equal(t, contents, cfg.Content)
	})

	t.Run("frontmatter with allowed-tools comma-separated", func(t *testing.T) {
		contents := `---
name: code-review
description: Reviews code
allowed-tools: Read, Grep, View
---
Review the code carefully.`

		cfg, err := parseSkillConfig(contents, "default-name")

		require.NoError(t, err)
		assert.Equal(t, "code-review", cfg.Name)
		assert.Equal(t, []string{"Read", "Grep", "View"}, cfg.AllowedTools)
	})

	t.Run("frontmatter with allowed-tools single tool", func(t *testing.T) {
		contents := `---
name: simple-skill
allowed-tools: Read
---
Content.`

		cfg, err := parseSkillConfig(contents, "default-name")

		require.NoError(t, err)
		assert.Equal(t, []string{"Read"}, cfg.AllowedTools)
	})

	t.Run("frontmatter with empty allowed-tools", func(t *testing.T) {
		contents := `---
name: no-tools
allowed-tools: 
---
Content.`

		cfg, err := parseSkillConfig(contents, "default-name")

		require.NoError(t, err)
		assert.Nil(t, cfg.AllowedTools)
	})

	t.Run("frontmatter with user-invocable false", func(t *testing.T) {
		contents := `---
name: model-only
description: Only the model should invoke this
user-invocable: false
---
Content.`

		cfg, err := parseSkillConfig(contents, "default-name")

		require.NoError(t, err)
		assert.Equal(t, "model-only", cfg.Name)
		assert.False(t, cfg.UserInvocable)
	})

	t.Run("frontmatter with user-invocable true", func(t *testing.T) {
		contents := `---
name: user-skill
user-invocable: true
---
Content.`

		cfg, err := parseSkillConfig(contents, "default-name")

		require.NoError(t, err)
		assert.True(t, cfg.UserInvocable)
	})

	t.Run("frontmatter with disable-model-invocation true", func(t *testing.T) {
		contents := `---
name: user-only
description: Only users can invoke this
disable-model-invocation: true
---
Content.`

		cfg, err := parseSkillConfig(contents, "default-name")

		require.NoError(t, err)
		assert.Equal(t, "user-only", cfg.Name)
		assert.True(t, cfg.DisableModelInvocation)
	})

	t.Run("frontmatter with disable-model-invocation false", func(t *testing.T) {
		contents := `---
name: any-skill
disable-model-invocation: false
---
Content.`

		cfg, err := parseSkillConfig(contents, "default-name")

		require.NoError(t, err)
		assert.False(t, cfg.DisableModelInvocation)
	})

	t.Run("frontmatter with all fields", func(t *testing.T) {
		contents := `---
name: full-skill
description: A complete skill with all options
allowed-tools: Read, Write, Grep
user-invocable: false
disable-model-invocation: true
---
This is a comprehensive skill.

It has multiple paragraphs.`

		cfg, err := parseSkillConfig(contents, "default-name")

		require.NoError(t, err)
		assert.Equal(t, "full-skill", cfg.Name)
		assert.Equal(t, "A complete skill with all options", cfg.Description)
		assert.Equal(t, []string{"Read", "Write", "Grep"}, cfg.AllowedTools)
		assert.False(t, cfg.UserInvocable)
		assert.True(t, cfg.DisableModelInvocation)
		assert.Equal(t, contents, cfg.Content)
	})

	t.Run("name from frontmatter overrides default", func(t *testing.T) {
		contents := `---
name: frontmatter-name
---
Content.`

		cfg, err := parseSkillConfig(contents, "directory-name")

		require.NoError(t, err)
		assert.Equal(t, "frontmatter-name", cfg.Name)
	})

	t.Run("missing name uses default", func(t *testing.T) {
		contents := `---
description: No name specified
---
Content.`

		cfg, err := parseSkillConfig(contents, "default-from-dir")

		require.NoError(t, err)
		assert.Equal(t, "default-from-dir", cfg.Name)
		assert.Equal(t, "No name specified", cfg.Description)
	})

	t.Run("malformed YAML returns error", func(t *testing.T) {
		contents := `---
name: bad yaml
invalid: [unclosed
---
Content.`

		cfg, err := parseSkillConfig(contents, "default-name")

		require.Error(t, err)
		require.ErrorIs(t, err, ErrMalformedConfig)
		assert.Nil(t, cfg)
	})

	t.Run("allowed-tools with extra whitespace", func(t *testing.T) {
		contents := `---
name: whitespace-test
allowed-tools:   Read  ,   Grep   ,  View  
---
Content.`

		cfg, err := parseSkillConfig(contents, "default-name")

		require.NoError(t, err)
		assert.Equal(t, []string{"Read", "Grep", "View"}, cfg.AllowedTools)
	})

	t.Run("allowed-tools with trailing comma", func(t *testing.T) {
		contents := `---
name: trailing-comma
allowed-tools: Read, Grep,
---
Content.`

		cfg, err := parseSkillConfig(contents, "default-name")

		require.NoError(t, err)
		assert.Equal(t, []string{"Read", "Grep"}, cfg.AllowedTools)
	})

	t.Run("empty frontmatter uses defaults", func(t *testing.T) {
		contents := `---
---
Content.`

		cfg, err := parseSkillConfig(contents, "default-name")

		require.NoError(t, err)
		assert.Equal(t, "default-name", cfg.Name)
		assert.Equal(t, "", cfg.Description)
		assert.True(t, cfg.UserInvocable)
		assert.False(t, cfg.DisableModelInvocation)
	})

	t.Run("frontmatter with extra fields ignores them", func(t *testing.T) {
		contents := `---
name: with-extras
description: Has extra fields
unknown-field: should be ignored
another-unknown: also ignored
---
Content.`

		cfg, err := parseSkillConfig(contents, "default-name")

		require.NoError(t, err)
		assert.Equal(t, "with-extras", cfg.Name)
		assert.Equal(t, "Has extra fields", cfg.Description)
	})

	t.Run("multiline description", func(t *testing.T) {
		contents := `---
name: multiline
description: |
  This is a multiline
  description that spans
  multiple lines.
---
Content.`

		cfg, err := parseSkillConfig(contents, "default-name")

		require.NoError(t, err)
		assert.Contains(t, cfg.Description, "multiline")
		assert.Contains(t, cfg.Description, "description that spans")
	})

	t.Run("content preserves markdown", func(t *testing.T) {
		contents := `---
name: markdown-skill
---
# Heading

This is **bold** and *italic*.

- List item 1
- List item 2

` + "```go\nfunc main() {}\n```"

		cfg, err := parseSkillConfig(contents, "default-name")

		require.NoError(t, err)
		assert.Contains(t, cfg.Content, "# Heading")
		assert.Contains(t, cfg.Content, "**bold**")
		assert.Contains(t, cfg.Content, "```go")
	})

	t.Run("properly parses content with CRLF line endings", func(t *testing.T) {
		// CRLF (Windows line endings)
		crlf := "---\r\nname: test-skill\r\ndescription: A skill with CRLF\r\nallowed-tools: Read, Write\r\n---\r\nSkill content\r\n"
		cfg, err := parseSkillConfig(crlf, "default-name")

		require.NoError(t, err, "parsing with CRLF line endings should not error")
		assert.Equal(t, "test-skill", cfg.Name, "name should match for CRLF")
		assert.Equal(t, "A skill with CRLF", cfg.Description, "description should match for CRLF")
		assert.Equal(t, []string{"Read", "Write"}, cfg.AllowedTools, "allowed-tools should match for CRLF")

		// LF (Unix line endings)
		lf := "---\nname: test-skill\ndescription: A skill with LF\nallowed-tools: Read, Write\n---\nSkill content\n"
		cfg, err = parseSkillConfig(lf, "default-name")

		require.NoError(t, err, "parsing with LF line endings should not error")
		assert.Equal(t, "test-skill", cfg.Name, "name should match for LF")
		assert.Equal(t, "A skill with LF", cfg.Description, "description should match for LF")
		assert.Equal(t, []string{"Read", "Write"}, cfg.AllowedTools, "allowed-tools should match for LF")

		// Mixed line endings
		mixed := "---\r\nname: test-skill\ndescription: A skill with mixed\r\nallowed-tools: Read, Write\n---\r\nSkill content\n"
		cfg, err = parseSkillConfig(mixed, "default-name")

		require.NoError(t, err, "parsing with mixed line endings should not error")
		assert.Equal(t, "test-skill", cfg.Name, "name should match for mixed line endings")
		assert.Equal(t, "A skill with mixed", cfg.Description, "description should match for mixed line endings")
		assert.Equal(t, []string{"Read", "Write"}, cfg.AllowedTools, "allowed-tools should match for mixed line endings")
	})
}

func TestParseAllowedTools(t *testing.T) {
	t.Run("empty string returns nil", func(t *testing.T) {
		result := parseAllowedTools("")
		assert.Nil(t, result)
	})

	t.Run("single tool", func(t *testing.T) {
		result := parseAllowedTools("Read")
		assert.Equal(t, []string{"Read"}, result)
	})

	t.Run("multiple tools", func(t *testing.T) {
		result := parseAllowedTools("Read, Write, Execute")
		assert.Equal(t, []string{"Read", "Write", "Execute"}, result)
	})

	t.Run("trims whitespace", func(t *testing.T) {
		result := parseAllowedTools("  Read  ,  Write  ")
		assert.Equal(t, []string{"Read", "Write"}, result)
	})

	t.Run("filters empty entries", func(t *testing.T) {
		result := parseAllowedTools("Read,,Write,,,")
		assert.Equal(t, []string{"Read", "Write"}, result)
	})

	t.Run("whitespace only entries filtered", func(t *testing.T) {
		result := parseAllowedTools("Read,   ,Write")
		assert.Equal(t, []string{"Read", "Write"}, result)
	})
}

func TestParseSkillConfigValidation(t *testing.T) {
	t.Run("name exceeds max length", func(t *testing.T) {
		longName := strings.Repeat("a", MaxNameLength+1)
		contents := fmt.Sprintf("---\nname: %s\ndescription: test\n---\nContent.", longName)

		_, err := parseSkillConfig(contents, "default-name")

		require.Error(t, err)
		assert.Contains(t, err.Error(), "name")
		assert.Contains(t, err.Error(), "exceeds max length")
	})

	t.Run("name at max length is valid", func(t *testing.T) {
		maxName := strings.Repeat("a", MaxNameLength)
		contents := fmt.Sprintf("---\nname: %s\ndescription: test\n---\nContent.", maxName)

		cfg, err := parseSkillConfig(contents, "default-name")

		require.NoError(t, err)
		assert.Equal(t, maxName, cfg.Name)
	})

	t.Run("description exceeds max length", func(t *testing.T) {
		longDesc := strings.Repeat("a", MaxDescriptionLength+1)
		contents := fmt.Sprintf("---\nname: test\ndescription: %s\n---\nContent.", longDesc)

		_, err := parseSkillConfig(contents, "default-name")

		require.Error(t, err)
		assert.Contains(t, err.Error(), "description")
		assert.Contains(t, err.Error(), "exceeds max length")
	})

	t.Run("description at max length is valid", func(t *testing.T) {
		maxDesc := strings.Repeat("a", MaxDescriptionLength)
		contents := fmt.Sprintf("---\nname: test\ndescription: %s\n---\nContent.", maxDesc)

		cfg, err := parseSkillConfig(contents, "default-name")

		require.NoError(t, err)
		assert.Equal(t, maxDesc, cfg.Description)
	})

	t.Run("content exceeds max length", func(t *testing.T) {
		longContent := strings.Repeat("a", MaxContentLength+1)
		contents := fmt.Sprintf("---\nname: test\ndescription: test\n---\n%s", longContent)

		_, err := parseSkillConfig(contents, "default-name")

		require.Error(t, err)
		assert.Contains(t, err.Error(), "content")
		assert.Contains(t, err.Error(), "exceeds max length")
	})

	t.Run("content at max length is valid", func(t *testing.T) {
		// Account for frontmatter size
		frontmatter := "---\nname: test\ndescription: test\n---\n"
		maxContent := strings.Repeat("a", MaxContentLength-len(frontmatter))
		contents := frontmatter + maxContent

		cfg, err := parseSkillConfig(contents, "default-name")

		require.NoError(t, err)
		assert.Equal(t, contents, cfg.Content)
	})

	t.Run("too many allowed-tools", func(t *testing.T) {
		tools := make([]string, MaxAllowedToolsCount+1)
		for i := range tools {
			tools[i] = fmt.Sprintf("tool%d", i)
		}
		toolsStr := strings.Join(tools, ", ")
		contents := fmt.Sprintf("---\nname: test\ndescription: test\nallowed-tools: %s\n---\nContent.", toolsStr)

		_, err := parseSkillConfig(contents, "default-name")

		require.Error(t, err)
		assert.Contains(t, err.Error(), "allowed-tools")
	})

	t.Run("max allowed-tools count is valid", func(t *testing.T) {
		tools := make([]string, MaxAllowedToolsCount)
		for i := range tools {
			tools[i] = fmt.Sprintf("t%d", i)
		}
		toolsStr := strings.Join(tools, ", ")
		contents := fmt.Sprintf("---\nname: test\ndescription: test\nallowed-tools: %s\n---\nContent.", toolsStr)

		cfg, err := parseSkillConfig(contents, "default-name")

		require.NoError(t, err)
		assert.Len(t, cfg.AllowedTools, MaxAllowedToolsCount)
	})

	t.Run("tool name exceeds max length", func(t *testing.T) {
		longTool := strings.Repeat("a", MaxToolNameLength+1)
		contents := fmt.Sprintf("---\nname: test\ndescription: test\nallowed-tools: Read, %s\n---\nContent.", longTool)

		_, err := parseSkillConfig(contents, "default-name")

		require.Error(t, err)
		assert.Contains(t, err.Error(), "tool name")
		assert.Contains(t, err.Error(), "exceeds max length")
	})

	t.Run("tool name at max length is valid", func(t *testing.T) {
		maxTool := strings.Repeat("a", MaxToolNameLength)
		contents := fmt.Sprintf("---\nname: test\ndescription: test\nallowed-tools: %s\n---\nContent.", maxTool)

		cfg, err := parseSkillConfig(contents, "default-name")

		require.NoError(t, err)
		assert.Equal(t, []string{maxTool}, cfg.AllowedTools)
	})

	t.Run("unicode characters not allowed in name (matches CLI)", func(t *testing.T) {
		// CLI regex only allows: [a-zA-Z0-9][a-zA-Z0-9._\- ]*
		// Unicode characters like emoji are not allowed
		unicodeName := strings.Repeat("🎉", 10)
		contents := fmt.Sprintf("---\nname: %s\ndescription: test\n---\nContent.", unicodeName)

		_, err := parseSkillConfig(contents, "default-name")

		require.Error(t, err)
		assert.Contains(t, err.Error(), "must contain only letters, numbers")
	})

	t.Run("valid name with allowed characters", func(t *testing.T) {
		// Test all allowed character types: letters, numbers, dots, underscores, hyphens, spaces
		validName := "My-Skill_v1.0 Test"
		contents := fmt.Sprintf("---\nname: %s\ndescription: test\n---\nContent.", validName)

		cfg, err := parseSkillConfig(contents, "default-name")

		require.NoError(t, err)
		assert.Equal(t, validName, cfg.Name)
	})

	t.Run("name must start with alphanumeric", func(t *testing.T) {
		// Name starting with hyphen is invalid
		invalidName := "-invalid-start"
		contents := fmt.Sprintf("---\nname: %s\ndescription: test\n---\nContent.", invalidName)

		_, err := parseSkillConfig(contents, "default-name")

		require.Error(t, err)
		assert.Contains(t, err.Error(), "must contain only letters, numbers")
	})

	t.Run("name exceeding max length", func(t *testing.T) {
		// 65 characters (max is 64)
		longName := strings.Repeat("a", MaxNameLength+1)
		contents := fmt.Sprintf("---\nname: %s\ndescription: test\n---\nContent.", longName)

		_, err := parseSkillConfig(contents, "default-name")

		require.Error(t, err)
		assert.Contains(t, err.Error(), "name")
	})
}
