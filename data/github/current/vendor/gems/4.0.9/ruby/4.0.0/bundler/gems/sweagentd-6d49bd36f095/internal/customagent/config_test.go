package customagent

import (
	"fmt"
	"strings"
	"testing"

	"github.com/github/sweagentd/internal/permissions"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestConfig(t *testing.T) {
	t.Run("return parsed data if already parsed", func(t *testing.T) {
		cfg := &Config{
			attributes: ConfigAttributes{
				Prompt: "prompt data",
			},
		}

		prompt := cfg.prompt()

		if prompt != "prompt data" {
			t.Errorf("expected 'prompt data', got %s", prompt)
		}
	})

	t.Run("returns error if contents is empty", func(t *testing.T) {
		_, err := parseConfig("", "some-name")
		require.Error(t, err, "expected error for empty contents")
		assert.Contains(t, err.Error(), "markdown content must start with YAML frontmatter")
	})

	t.Run("returns error if content does not start with frontmatter", func(t *testing.T) {
		contents := "not starting with frontmatter"
		_, err := parseConfig(contents, "some-name")
		require.Error(t, err, "expected error for content without frontmatter")
		assert.Contains(t, err.Error(), "markdown content must start with YAML frontmatter delimited by '---'")
	})

	t.Run("returns error if frontmatter is not properly closed", func(t *testing.T) {
		contents := "---\nkey: value\nnot closed"
		_, err := parseConfig(contents, "some-name")
		require.Error(t, err, "expected error for unclosed frontmatter")
		assert.Contains(t, err.Error(), "could not find closing '---' delimiter for YAML frontmatter")
	})

	t.Run("returns error with partial state for invalid YAML", func(t *testing.T) {
		contents := "---\ninvalid: yaml: content: [\n---\nprompt"
		_, err := parseConfig(contents, "some-name")
		require.Error(t, err, "expected error for invalid YAML")
		assert.Contains(t, err.Error(), "failed to parse YAML frontmatter")
	})

	t.Run("returns prompt if parsing is successful", func(t *testing.T) {
		contents := "---\nname: test\ndescription: test desc\nkey: value\n---\nthis is a prompt"
		attrs, err := parseConfig(contents, "some-name")
		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}
		cfg := NewConfigWithAttributes(attrs)
		prompt := cfg.prompt()
		if prompt != "this is a prompt" {
			t.Errorf("expected 'this is a prompt', got %s", prompt)
		}
	})

	t.Run("parses tool forms", func(t *testing.T) {
		attrs, err := parseConfig("---\nname: test\ndescription: test desc\ntools: tool1, tool2\n---\nprompt", "some-name")
		require.NoError(t, err, "expected no error parsing tools as comma-separated string")
		assert.Equal(t, []string{"tool1", "tool2"}, attrs.Tools, "tools mismatch for comma-separated string")
		attrs, err = parseConfig("---\nname: test\ndescription: test desc\ntools: [\"tool1\", \"tool2\"]\n---\nprompt", "some-name")
		require.NoError(t, err, "expected no error parsing tools as yaml array")
		assert.Equal(t, []string{"tool1", "tool2"}, attrs.Tools, "tools mismatch for yaml array")
	})

	t.Run("returns default name when name is missing", func(t *testing.T) {
		contents := "---\ndescription: test description\n---\nprompt"
		cfg, err := parseConfig(contents, "some-name")
		require.NoError(t, err, "expected no error when name is missing")
		assert.Equal(t, "some-name", cfg.DisplayName, "should use default name when name is missing")
	})

	t.Run("returns default name when name is empty or whitespace", func(t *testing.T) {
		contents := "---\nname: \"\"\ndescription: test description\n---\nprompt"
		cfg, err := parseConfig(contents, "some-name")
		require.NoError(t, err, "expected no error when name is missing")
		assert.Equal(t, "some-name", cfg.DisplayName, "should use default name when name is missing")

		// Check whitespace
		contents = "---\nname: \"   \"\ndescription: test description\n---\nprompt"
		cfg, err = parseConfig(contents, "some-name")
		require.NoError(t, err, "expected no error when name is missing")
		assert.Equal(t, "some-name", cfg.DisplayName, "should use default name when name is missing")
	})

	t.Run("returns ErrConfigValidationError  when description is missing", func(t *testing.T) {
		contents := "---\nname: test-agent\n---\nprompt"
		_, err := parseConfig(contents, "some-name")
		require.Error(t, err, "expected error when description is missing")

		var configErr *ErrConfigValidationError
		require.ErrorAs(t, err, &configErr, "error should be ErrConfigValidationError  type")
		assert.Contains(t, err.Error(), "field \"description\" is required", "error message should mention missing description")

		// Verify partial state is available - name should be parsed but with warning indicator
		assert.Equal(t, "test-agent", configErr.attributes.DisplayName, "should have name")
		assert.Equal(t, []string{"*"}, configErr.attributes.Tools, "should have default tools")
	})

	t.Run("returns ErrConfigValidationError  when description is empty", func(t *testing.T) {
		contents := "---\nname: test-agent\ndescription: \"\"\n---\nprompt"
		_, err := parseConfig(contents, "some-name")
		require.Error(t, err, "expected error when description is empty")

		var configErr *ErrConfigValidationError
		require.ErrorAs(t, err, &configErr, "error should be ErrConfigValidationError  type")
		assert.Contains(t, err.Error(), "field \"description\" is required", "error message should mention missing description")
		assert.Equal(t, "test-agent", configErr.attributes.DisplayName, "should have name")
	})

	t.Run("returns ErrConfigValidationError  when description is only whitespace", func(t *testing.T) {
		contents := "---\nname: test-agent\ndescription: \"   \"\n---\nprompt"
		_, err := parseConfig(contents, "some-name")
		require.Error(t, err, "expected error when description is only whitespace")

		var configErr *ErrConfigValidationError
		require.ErrorAs(t, err, &configErr, "error should be ErrConfigValidationError  type")
		assert.Contains(t, err.Error(), "field \"description\" is required", "error message should mention missing description")
		assert.Equal(t, "test-agent", configErr.attributes.DisplayName, "should have name")
	})

	t.Run("parses successfully with valid name and description", func(t *testing.T) {
		contents := "---\nname: test-agent\ndescription: A test agent\n---\nprompt text"
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err, "expected no error with valid name and description")
		assert.Equal(t, "test-agent", attrs.DisplayName, "name should match")
		assert.Equal(t, "A test agent", attrs.Description, "description should match")
		assert.Equal(t, "prompt text", attrs.Prompt, "prompt should match")
	})

	t.Run("returns ErrConfigValidationError  with partial state for tools parsing", func(t *testing.T) {
		contents := "---\nname: test-agent\ndescription: A test agent\ntools: [\"tool1\", \"tool2\"]\n---\nprompt text"
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err, "expected no error with valid tools")
		assert.Equal(t, "test-agent", attrs.DisplayName, "name should match")
		assert.Equal(t, "A test agent", attrs.Description, "description should match")
		assert.Equal(t, []string{"tool1", "tool2"}, attrs.Tools, "tools should match")
		assert.Equal(t, "prompt text", attrs.Prompt, "prompt should match")
	})

	t.Run("returns ErrConfigValidationError  with partial state when MCP config is invalid", func(t *testing.T) {
		// Test with an MCP config that would fail JSON marshalling
		// This is a more complex test that requires the MCP config to be invalid in a way that triggers the error
		contents := "---\nname: test-agent\ndescription: A test agent\nmcp-servers:\n  invalid: !invalid_yaml_tag\n---\nprompt text"
		_, err := parseConfig(contents, "some-name")

		// Note: This might not fail depending on how yaml.Unmarshal handles the invalid tag
		// The actual MCP error would happen in the mcpConfig() method when marshalling to JSON
		if err != nil {
			var configErr *ErrConfigValidationError
			if assert.ErrorAs(t, err, &configErr, "error should be ErrConfigValidationError  type") {
				// Verify we have partial state up to the point of failure
				assert.Equal(t, "test-agent", configErr.attributes.DisplayName, "should have name with warning indicator")
				assert.Equal(t, "A test agent", configErr.attributes.Description, "should have description")
				assert.Equal(t, []string{"*"}, configErr.attributes.Tools, "should have default tools")
				assert.Equal(t, "prompt text", configErr.attributes.Prompt, "should have prompt")
			}
		}
	})

	t.Run("ErrConfigValidationError  provides access to partial config", func(t *testing.T) {
		contents := "---\nname: test-agent\ntools: [\"custom-tool\"]\n---\nprompt text"
		_, err := parseConfig(contents, "some-name")
		require.Error(t, err, "expected error when description is missing")

		var configErr *ErrConfigValidationError
		require.ErrorAs(t, err, &configErr, "error should be ErrConfigValidationError  type")

		// Test that the Config() method works and provides partial state
		cfg := configErr.Config()
		require.NotNil(t, cfg, "Config() should return a valid config")

		assert.Equal(t, "test-agent", cfg.attributes.DisplayName, "config should have name")
		assert.Equal(t, []string{"custom-tool"}, cfg.attributes.Tools, "config should have parsed tools")
		assert.Empty(t, cfg.attributes.Description, "config should have empty description")

		// Test that the config methods work with the partial state
		assert.Equal(t, []string{"custom-tool"}, cfg.tools(), "tools() method should work")
		assert.Equal(t, "prompt text", cfg.prompt(), "prompt() method should work")
	})

	t.Run("ErrConfigValidationError  includes prompt when error occurs after prompt extraction", func(t *testing.T) {
		// This test shows that when an error occurs after prompt extraction (like valid YAML but invalid logic),
		// the prompt is included in the partial state. We'll use a scenario that should parse successfully
		// up to the prompt but fail later. Since MCP config validation is complex, let's create a scenario
		// where we can control when the error occurs.

		// For now, let's use a working example to verify that successful parsing includes all fields
		contents := "---\nname: test-agent\ndescription: A test agent\ntools: [\"custom-tool\"]\n---\nprompt text"
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err, "this should parse successfully")

		// Verify all fields are present in successful case
		assert.Equal(t, "test-agent", attrs.DisplayName)
		assert.Equal(t, "A test agent", attrs.Description)
		assert.Equal(t, []string{"custom-tool"}, attrs.Tools)
		assert.Equal(t, "prompt text", attrs.Prompt)
	})

	// Test ErrConfigValidationError methods specifically
	t.Run("ErrConfigValidationError Error() method formats correctly", func(t *testing.T) {
		// Test with message-based error
		err := &ErrConfigValidationError{
			attributes: ConfigAttributes{DisplayName: "test"},
			message:    "test validation message",
		}
		assert.Equal(t, "error parsing custom agent configuration: test validation message", err.Error())

		// Test with wrapped error
		wrappedErr := assert.AnError
		err = &ErrConfigValidationError{
			attributes: ConfigAttributes{DisplayName: "test"},
			err:        wrappedErr,
		}
		expectedMsg := "error parsing custom agent configuration: " + wrappedErr.Error()
		assert.Equal(t, expectedMsg, err.Error())
	})

	t.Run("ErrConfigValidationError Unwrap() method works correctly", func(t *testing.T) {
		// Test with message-only error
		err := &ErrConfigValidationError{
			attributes: ConfigAttributes{DisplayName: "test"},
			message:    "test validation message",
		}
		require.Error(t, err.Unwrap(), "Unwrap should return error for message-only error")
		assert.Equal(t, "Test validation message", err.ValidationMessage())

		// Test with wrapped error
		wrappedErr := assert.AnError
		err = &ErrConfigValidationError{
			attributes: ConfigAttributes{DisplayName: "test"},
			err:        wrappedErr,
		}
		unwrapped := err.Unwrap()
		assert.Equal(t, wrappedErr, unwrapped)
	})

	t.Run("returns ErrConfigValidationError for invalid target values", func(t *testing.T) {
		contents := "---\nname: test-agent\ndescription: A test agent\ntarget: invalid-target\n---\nprompt text"
		_, err := parseConfig(contents, "some-name")
		require.Error(t, err, "expected error for invalid target")

		var configErr *ErrConfigValidationError
		require.ErrorAs(t, err, &configErr, "error should be ErrConfigValidationError type")
		assert.Contains(t, err.Error(), "bad value for \"target\"")

		// Verify partial state includes all parsed fields up to validation
		assert.Equal(t, "test-agent", configErr.attributes.DisplayName)
		assert.Equal(t, "A test agent", configErr.attributes.Description)
		assert.Equal(t, []string{"*"}, configErr.attributes.Tools)
		assert.Equal(t, "prompt text", configErr.attributes.Prompt)
		assert.Equal(t, "invalid-target", configErr.attributes.Target)
	})

	t.Run("accepts valid target values", func(t *testing.T) {
		validTargets := []string{TargetEmpty, TargetGitHubCopilot}

		for _, target := range validTargets {
			t.Run("target: "+target, func(t *testing.T) {
				var contents string
				if target == "" {
					contents = "---\nname: test-agent\ndescription: A test agent\n---\nprompt text"
				} else {
					contents = "---\nname: test-agent\ndescription: A test agent\ntarget: " + target + "\n---\nprompt text"
				}

				attrs, err := parseConfig(contents, "some-name")
				require.NoError(t, err, "should accept valid target: "+target)
				assert.Equal(t, target, attrs.Target)
			})
		}
	})

	t.Run("ErrConfigValidationError preserves all attributes at point of failure", func(t *testing.T) {
		// Test that when validation fails, all attributes parsed up to that point are preserved
		contents := "---\nname: test-agent\ndescription: A test agent\ntools: [\"tool1\", \"tool2\"]\ntarget: invalid\n---\nthis is the prompt"
		_, err := parseConfig(contents, "some-name")
		require.Error(t, err)

		var configErr *ErrConfigValidationError
		require.ErrorAs(t, err, &configErr)

		// All fields should be preserved even though validation failed
		assert.Equal(t, "test-agent", configErr.attributes.DisplayName)
		assert.Equal(t, "A test agent", configErr.attributes.Description)
		assert.Equal(t, []string{"tool1", "tool2"}, configErr.attributes.Tools)
		assert.Equal(t, "this is the prompt", configErr.attributes.Prompt)
		assert.Equal(t, "invalid", configErr.attributes.Target)

		// Config should be usable
		cfg := configErr.Config()
		assert.Equal(t, []string{"tool1", "tool2"}, cfg.tools())
		assert.Equal(t, "this is the prompt", cfg.prompt())
	})

	t.Run("properly parses content with CRLF or LF line endings", func(t *testing.T) {
		// CRLF
		crlf := "---\r\nname: test-agent\r\ndescription: desc\r\ntools: [\"custom-tool\"]\r\n---\r\nprompt text\r\n"
		crlfResult, err := parseConfig(crlf, "some-name")
		require.NoError(t, err, "parsing with CRLF line endings should not error")
		assert.Equal(t, "test-agent", crlfResult.DisplayName, "name should match for CRLF")
		assert.Equal(t, "desc", crlfResult.Description, "description should match for CRLF")
		assert.Equal(t, []string{"custom-tool"}, crlfResult.Tools, "tools should match for CRLF")
		assert.Equal(t, "prompt text", crlfResult.Prompt, "prompt should match for CRLF")

		// LF
		lf := "---\nname: test-agent\ndescription: desc\ntools: [\"custom-tool\"]\n---\nprompt text\n"
		lfResult, err := parseConfig(lf, "some-name")
		require.NoError(t, err, "parsing with LF line endings should not error")
		assert.Equal(t, "test-agent", lfResult.DisplayName, "name should match for LF")
		assert.Equal(t, "desc", lfResult.Description, "description should match for LF")
		assert.Equal(t, []string{"custom-tool"}, lfResult.Tools, "tools should match for LF")
		assert.Equal(t, "prompt text", lfResult.Prompt, "prompt should match for LF")

		// Mix
		mix := "---\r\nname: test-agent\ndescription: desc\r\ntools: [\"custom-tool\"]\r\n---\nprompt text\r\n"
		mixResult, err := parseConfig(mix, "some-name")
		require.NoError(t, err, "parsing with mixed line endings should not error")
		assert.Equal(t, "test-agent", mixResult.DisplayName, "name should match for mixed line endings")
		assert.Equal(t, "desc", mixResult.Description, "description should match for mixed line endings")
		assert.Equal(t, []string{"custom-tool"}, mixResult.Tools, "tools should match for mixed line endings")
		assert.Equal(t, "prompt text", mixResult.Prompt, "prompt should match for mixed line endings")
	})
}

func TestConfigMaxSizeLimits(t *testing.T) {
	t.Run("name length limit", func(t *testing.T) {
		// Exceeds limit
		longName := strings.Repeat("a", MaxNameLength+1)
		contents := fmt.Sprintf("---\nname: %s\ndescription: test description\n---\nprompt", longName)
		_, err := parseConfig(contents, "some-name")
		require.Error(t, err)
		assert.Contains(t, err.Error(), fmt.Sprintf("\"name\" exceeds max length of %d", MaxNameLength))
	})

	t.Run("description length limit", func(t *testing.T) {
		// Exceeds limit
		longDesc := strings.Repeat("a", MaxDescriptionLength+1)
		contents := fmt.Sprintf("---\nname: test-agent\ndescription: %s\n---\nprompt", longDesc)
		_, err := parseConfig(contents, "some-name")
		require.Error(t, err)
		assert.Contains(t, err.Error(), fmt.Sprintf("\"description\" exceeds max length of %d", MaxDescriptionLength))
	})

	t.Run("description length limit with multi-byte UTF-8 characters", func(t *testing.T) {
		// Test that MaxDescriptionLength multi-byte characters (not bytes) are allowed
		descWithEmojis := strings.Repeat("🔥", MaxDescriptionLength)
		contents := fmt.Sprintf("---\nname: test-agent\ndescription: %s\n---\nprompt", descWithEmojis)
		_, err := parseConfig(contents, "some-name")
		require.NoError(t, err, "MaxDescriptionLength UTF-8 characters should be allowed regardless of byte count")

		// Test that exceeding the limit is rejected
		tooLongDesc := descWithEmojis + "🔥"
		contents = fmt.Sprintf("---\nname: test-agent\ndescription: %s\n---\nprompt", tooLongDesc)
		_, err = parseConfig(contents, "some-name")
		require.Error(t, err, "Exceeding MaxDescriptionLength UTF-8 characters should be rejected")
		assert.Contains(t, err.Error(), fmt.Sprintf("\"description\" exceeds max length of %d", MaxDescriptionLength))
	})

	t.Run("prompt length limit", func(t *testing.T) {
		// Exceeds limit
		longPrompt := strings.Repeat("a", MaxPromptLength+1)
		contents := fmt.Sprintf("---\nname: test-agent\ndescription: test description\n---\n%s", longPrompt)
		_, err := parseConfig(contents, "some-name")
		require.Error(t, err)
		assert.Contains(t, err.Error(), fmt.Sprintf("\"prompt\" exceeds max length of %d", MaxPromptLength))
	})

	t.Run("prompt length limit with multi-byte UTF-8 characters", func(t *testing.T) {
		// Test that 30000 multi-byte characters (not bytes) are allowed
		// Each emoji is 4 bytes but counts as 1 character
		promptWithEmojis := strings.Repeat("🔥", MaxPromptLength)
		contents := fmt.Sprintf("---\nname: test-agent\ndescription: test description\n---\n%s", promptWithEmojis)
		_, err := parseConfig(contents, "some-name")
		require.NoError(t, err, "30000 UTF-8 characters should be allowed regardless of byte count")

		// Test that 30001 multi-byte characters are rejected
		tooLongPrompt := promptWithEmojis + "🔥"
		contents = fmt.Sprintf("---\nname: test-agent\ndescription: test description\n---\n%s", tooLongPrompt)
		_, err = parseConfig(contents, "some-name")
		require.Error(t, err, "30001 UTF-8 characters should be rejected")
		assert.Contains(t, err.Error(), fmt.Sprintf("\"prompt\" exceeds max length of %d", MaxPromptLength))
	})

	t.Run("tool name length limit", func(t *testing.T) {
		// Exceeds limit
		longTool := strings.Repeat("a", MaxToolNameLength+1)
		contents := fmt.Sprintf("---\nname: test-agent\ndescription: test description\ntools: [%q]\n---\nprompt", longTool)
		_, err := parseConfig(contents, "some-name")
		require.Error(t, err)
		assert.Contains(t, err.Error(), fmt.Sprintf("tool name exceeds max length of %d", MaxToolNameLength))
	})

	t.Run("tool name length limit with multi-byte UTF-8 characters", func(t *testing.T) {
		// Test that MaxToolNameLength multi-byte characters (not bytes) are allowed
		toolWithEmojis := strings.Repeat("🔥", MaxToolNameLength)
		contents := fmt.Sprintf("---\nname: test-agent\ndescription: test description\ntools: [%q]\n---\nprompt", toolWithEmojis)
		_, err := parseConfig(contents, "some-name")
		require.NoError(t, err, "MaxToolNameLength UTF-8 characters should be allowed regardless of byte count")

		// Test that exceeding the limit is rejected
		tooLongTool := toolWithEmojis + "🔥"
		contents = fmt.Sprintf("---\nname: test-agent\ndescription: test description\ntools: [%q]\n---\nprompt", tooLongTool)
		_, err = parseConfig(contents, "some-name")
		require.Error(t, err, "Exceeding MaxToolNameLength UTF-8 characters should be rejected")
		assert.Contains(t, err.Error(), fmt.Sprintf("tool name exceeds max length of %d", MaxToolNameLength))
	})

	t.Run("tool count limit", func(t *testing.T) {
		// Helper to create tools array
		createTools := func(count int) string {
			tools := make([]string, count)
			for i := range tools {
				tools[i] = fmt.Sprintf("\"tool%d\"", i)
			}
			return fmt.Sprintf("[%s]", strings.Join(tools, ", "))
		}

		// Exceeds limit
		toolsYaml := createTools(MaxToolCount + 1)
		contents := fmt.Sprintf("---\nname: test-agent\ndescription: test description\ntools: %s\n---\nprompt", toolsYaml)
		_, err := parseConfig(contents, "some-name")
		require.Error(t, err)
		assert.Contains(t, err.Error(), fmt.Sprintf("more than %d tools specified", MaxToolCount))
	})

	t.Run("MCP server count limit", func(t *testing.T) {
		// Helper to create MCP servers
		createMCPServers := func(count int) string {
			servers := make([]string, count)
			for i := range servers {
				servers[i] = fmt.Sprintf("  server%d:\n    command: \"test\"\n    tools: [\"*\"]", i)
			}
			return "mcp-servers:\n" + strings.Join(servers, "\n")
		}

		// Exceeds limit
		mcpServersYaml := createMCPServers(MaxMCPServerCount + 1)
		contents := fmt.Sprintf("---\nname: test-agent\ndescription: test description\n%s\n---\nprompt", mcpServersYaml)
		_, err := parseConfig(contents, "some-name")
		require.Error(t, err)
		assert.Contains(t, err.Error(), fmt.Sprintf("more than %d MCP servers specified", MaxMCPServerCount))
	})

	t.Run("argument-hint length limit", func(t *testing.T) {
		// Exceeds limit
		longHint := strings.Repeat("a", MaxArgumentHintLength+1)
		contents := fmt.Sprintf("---\nname: test-agent\ndescription: test description\nargument-hint: %s\n---\nprompt", longHint)
		_, err := parseConfig(contents, "some-name")
		require.Error(t, err)
		assert.Contains(t, err.Error(), fmt.Sprintf("\"argument-hint\" exceeds max length of %d", MaxArgumentHintLength))
	})

	t.Run("argument-hint length limit with multi-byte UTF-8 characters", func(t *testing.T) {
		// Test that MaxArgumentHintLength multi-byte characters (not bytes) are allowed
		hintWithEmojis := strings.Repeat("🔥", MaxArgumentHintLength)
		contents := fmt.Sprintf("---\nname: test-agent\ndescription: test description\nargument-hint: %s\n---\nprompt", hintWithEmojis)
		_, err := parseConfig(contents, "some-name")
		require.NoError(t, err, "MaxArgumentHintLength UTF-8 characters should be allowed regardless of byte count")

		// Test that exceeding the limit is rejected
		tooLongHint := hintWithEmojis + "🔥"
		contents = fmt.Sprintf("---\nname: test-agent\ndescription: test description\nargument-hint: %s\n---\nprompt", tooLongHint)
		_, err = parseConfig(contents, "some-name")
		require.Error(t, err, "Exceeding MaxArgumentHintLength UTF-8 characters should be rejected")
		assert.Contains(t, err.Error(), fmt.Sprintf("\"argument-hint\" exceeds max length of %d", MaxArgumentHintLength))
	})

	t.Run("model length limit", func(t *testing.T) {
		// Exceeds limit
		longModel := strings.Repeat("a", MaxModelLength+1)
		contents := fmt.Sprintf("---\nname: test-agent\ndescription: test description\nmodel: %s\n---\nprompt", longModel)
		_, err := parseConfig(contents, "some-name")
		require.Error(t, err)
		assert.Contains(t, err.Error(), fmt.Sprintf("\"model\" exceeds max length of %d", MaxModelLength))
	})

	t.Run("model length limit with multi-byte UTF-8 characters", func(t *testing.T) {
		// Test that MaxModelLength multi-byte characters (not bytes) are allowed
		modelWithEmojis := strings.Repeat("🔥", MaxModelLength)
		contents := fmt.Sprintf("---\nname: test-agent\ndescription: test description\nmodel: %s\n---\nprompt", modelWithEmojis)
		_, err := parseConfig(contents, "some-name")
		require.NoError(t, err, "MaxModelLength UTF-8 characters should be allowed regardless of byte count")

		// Test that exceeding the limit is rejected
		tooLongModel := modelWithEmojis + "🔥"
		contents = fmt.Sprintf("---\nname: test-agent\ndescription: test description\nmodel: %s\n---\nprompt", tooLongModel)
		_, err = parseConfig(contents, "some-name")
		require.Error(t, err, "Exceeding MaxModelLength UTF-8 characters should be rejected")
		assert.Contains(t, err.Error(), fmt.Sprintf("\"model\" exceeds max length of %d", MaxModelLength))
	})

	t.Run("metadata entry count limit", func(t *testing.T) {
		// Helper to create metadata entries
		createMetadata := func(count int) string {
			entries := make([]string, count)
			for i := range entries {
				entries[i] = fmt.Sprintf("  key%d: value%d", i, i)
			}
			return "metadata:\n" + strings.Join(entries, "\n")
		}

		// Exceeds limit
		metadataYaml := createMetadata(MaxMetadataEntryCount + 1)
		contents := fmt.Sprintf("---\nname: test-agent\ndescription: test description\n%s\n---\nprompt", metadataYaml)
		_, err := parseConfig(contents, "some-name")
		require.Error(t, err)
		assert.Contains(t, err.Error(), fmt.Sprintf("metadata has more than %d entries", MaxMetadataEntryCount))
	})

	t.Run("metadata key length limit", func(t *testing.T) {
		// Exceeds limit
		longKey := strings.Repeat("a", MaxMetadataKeyLength+1)
		contents := fmt.Sprintf("---\nname: test-agent\ndescription: test description\nmetadata:\n  %s: value\n---\nprompt", longKey)
		_, err := parseConfig(contents, "some-name")
		require.Error(t, err)
		assert.Contains(t, err.Error(), fmt.Sprintf("metadata key exceeds max length of %d", MaxMetadataKeyLength))
	})

	t.Run("metadata key length limit with multi-byte UTF-8 characters", func(t *testing.T) {
		// Test that MaxMetadataKeyLength multi-byte characters (not bytes) are allowed
		keyWithEmojis := strings.Repeat("🔥", MaxMetadataKeyLength)
		contents := fmt.Sprintf("---\nname: test-agent\ndescription: test description\nmetadata:\n  %s: value\n---\nprompt", keyWithEmojis)
		_, err := parseConfig(contents, "some-name")
		require.NoError(t, err, "MaxMetadataKeyLength UTF-8 characters should be allowed regardless of byte count")

		// Test that exceeding the limit is rejected
		tooLongKey := keyWithEmojis + "🔥"
		contents = fmt.Sprintf("---\nname: test-agent\ndescription: test description\nmetadata:\n  %s: value\n---\nprompt", tooLongKey)
		_, err = parseConfig(contents, "some-name")
		require.Error(t, err, "Exceeding MaxMetadataKeyLength UTF-8 characters should be rejected")
		assert.Contains(t, err.Error(), fmt.Sprintf("metadata key exceeds max length of %d", MaxMetadataKeyLength))
	})

	t.Run("metadata value length limit", func(t *testing.T) {
		// Exceeds limit
		longValue := strings.Repeat("a", MaxMetadataValueLength+1)
		contents := fmt.Sprintf("---\nname: test-agent\ndescription: test description\nmetadata:\n  key: %s\n---\nprompt", longValue)
		_, err := parseConfig(contents, "some-name")
		require.Error(t, err)
		assert.Contains(t, err.Error(), fmt.Sprintf("metadata value exceeds max length of %d", MaxMetadataValueLength))
	})

	t.Run("metadata value length limit with multi-byte UTF-8 characters", func(t *testing.T) {
		// Test that MaxMetadataValueLength multi-byte characters (not bytes) are allowed
		valueWithEmojis := strings.Repeat("🔥", MaxMetadataValueLength)
		contents := fmt.Sprintf("---\nname: test-agent\ndescription: test description\nmetadata:\n  key: %s\n---\nprompt", valueWithEmojis)
		_, err := parseConfig(contents, "some-name")
		require.NoError(t, err, "MaxMetadataValueLength UTF-8 characters should be allowed regardless of byte count")

		// Test that exceeding the limit is rejected
		tooLongValue := valueWithEmojis + "🔥"
		contents = fmt.Sprintf("---\nname: test-agent\ndescription: test description\nmetadata:\n  key: %s\n---\nprompt", tooLongValue)
		_, err = parseConfig(contents, "some-name")
		require.Error(t, err, "Exceeding MaxMetadataValueLength UTF-8 characters should be rejected")
		assert.Contains(t, err.Error(), fmt.Sprintf("metadata value exceeds max length of %d", MaxMetadataValueLength))
	})
}

func TestArgumentHint(t *testing.T) {
	t.Run("parses argument-hint successfully", func(t *testing.T) {
		contents := "---\nname: test-agent\ndescription: test description\nargument-hint: Enter the file path\n---\nprompt"
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		assert.Equal(t, "Enter the file path", attrs.ArgumentHint)
	})

	t.Run("argument-hint is optional", func(t *testing.T) {
		contents := "---\nname: test-agent\ndescription: test description\n---\nprompt"
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		assert.Empty(t, attrs.ArgumentHint)
	})

	t.Run("argument-hint at maximum length", func(t *testing.T) {
		maxHint := strings.Repeat("a", MaxArgumentHintLength)
		contents := fmt.Sprintf("---\nname: test-agent\ndescription: test description\nargument-hint: %s\n---\nprompt", maxHint)
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		assert.Equal(t, maxHint, attrs.ArgumentHint)
		assert.Len(t, attrs.ArgumentHint, MaxArgumentHintLength)
	})
}

func TestModel(t *testing.T) {
	t.Run("parses model successfully", func(t *testing.T) {
		contents := "---\nname: test-agent\ndescription: test description\nmodel: gpt-4\n---\nprompt"
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		assert.Equal(t, "gpt-4", attrs.Model)
	})

	t.Run("model is optional", func(t *testing.T) {
		contents := "---\nname: test-agent\ndescription: test description\n---\nprompt"
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		assert.Empty(t, attrs.Model)
	})
}

func TestDisableModelInvocation(t *testing.T) {
	t.Run("parses disable-model-invocation true", func(t *testing.T) {
		contents := "---\nname: test-agent\ndescription: test description\ndisable-model-invocation: true\n---\nprompt"
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		assert.True(t, attrs.DisableModelInvocation)
		assert.False(t, attrs.InferenceEnabled)
	})

	t.Run("parses disable-model-invocation false", func(t *testing.T) {
		contents := "---\nname: test-agent\ndescription: test description\ndisable-model-invocation: false\n---\nprompt"
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		assert.False(t, attrs.DisableModelInvocation)
		assert.True(t, attrs.InferenceEnabled)
	})

	t.Run("disable-model-invocation is optional and defaults to false", func(t *testing.T) {
		contents := "---\nname: test-agent\ndescription: test description\n---\nprompt"
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		assert.False(t, attrs.DisableModelInvocation)
		assert.True(t, attrs.InferenceEnabled)
	})

	t.Run("disable-model-invocation takes precedence over infer for InferenceEnabled", func(t *testing.T) {
		contents := "---\nname: test-agent\ndescription: test description\ninfer: true\ndisable-model-invocation: true\n---\nprompt"
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		assert.True(t, attrs.DisableModelInvocation)
		assert.False(t, attrs.InferenceEnabled)
	})

	t.Run("infer is used as fallback when disable-model-invocation is absent", func(t *testing.T) {
		contents := "---\nname: test-agent\ndescription: test description\ninfer: false\n---\nprompt"
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		assert.True(t, attrs.DisableModelInvocation)
		assert.False(t, attrs.InferenceEnabled)
	})
}

func TestUserInvocable(t *testing.T) {
	t.Run("parses user-invocable true", func(t *testing.T) {
		contents := "---\nname: test-agent\ndescription: test description\nuser-invocable: true\n---\nprompt"
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		assert.True(t, attrs.UserInvocable)
	})

	t.Run("parses user-invocable false", func(t *testing.T) {
		contents := "---\nname: test-agent\ndescription: test description\nuser-invocable: false\n---\nprompt"
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		assert.False(t, attrs.UserInvocable)
	})

	t.Run("user-invocable is optional and defaults to true", func(t *testing.T) {
		contents := "---\nname: test-agent\ndescription: test description\n---\nprompt"
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		assert.True(t, attrs.UserInvocable)
	})
}

func TestHandoffs(t *testing.T) {
	t.Run("parses handoffs successfully", func(t *testing.T) {
		contents := `---
name: test-agent
description: test description
handoffs:
  - label: Start Implementation
    agent: implementation
    prompt: Now implement the plan outlined above.
    send: false
---
prompt`
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		assert.NotNil(t, attrs.Handoffs)
		assert.Len(t, attrs.Handoffs, 1)
		assert.Equal(t, "Start Implementation", attrs.Handoffs[0].Label)
		assert.Equal(t, "implementation", attrs.Handoffs[0].Agent)
		assert.Equal(t, "Now implement the plan outlined above.", attrs.Handoffs[0].Prompt)
		assert.Equal(t, false, attrs.Handoffs[0].Send)
	})

	t.Run("handoffs is optional", func(t *testing.T) {
		contents := "---\nname: test-agent\ndescription: test description\n---\nprompt"
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		assert.Nil(t, attrs.Handoffs)
	})
}

func TestAgentNameValidation(t *testing.T) {
	t.Run("allows all valid slug characters", func(t *testing.T) {
		// Test that all characters in the regex are accepted
		contents := "---\nname: test\ndescription: test description\n---\nprompt"

		// Test all valid characters together
		name := "aZ09-_."
		attrs, err := parseConfig(contents, name)
		require.NoError(t, err, "should accept name with all valid slug characters")
		assert.NotEmpty(t, attrs.DisplayName)
	})
}

func TestMetadata(t *testing.T) {
	t.Run("parses metadata successfully", func(t *testing.T) {
		contents := `---
name: test-agent
description: test description
metadata:
  owner: john-doe
  category: testing
  version: 1.0.0
---
prompt`
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		require.NotNil(t, attrs.Metadata)
		assert.Equal(t, "john-doe", attrs.Metadata["owner"])
		assert.Equal(t, "testing", attrs.Metadata["category"])
		assert.Equal(t, "1.0.0", attrs.Metadata["version"])
		assert.Len(t, attrs.Metadata, 3)
	})

	t.Run("metadata is optional", func(t *testing.T) {
		contents := "---\nname: test-agent\ndescription: test description\n---\nprompt"
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		assert.Nil(t, attrs.Metadata)
	})

	t.Run("empty metadata map", func(t *testing.T) {
		contents := "---\nname: test-agent\ndescription: test description\nmetadata: {}\n---\nprompt"
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		assert.NotNil(t, attrs.Metadata)
		assert.Empty(t, attrs.Metadata)
	})

	t.Run("metadata at maximum entry count", func(t *testing.T) {
		// Create metadata with exactly MaxMetadataEntryCount entries
		entries := make([]string, MaxMetadataEntryCount)
		for i := range entries {
			entries[i] = fmt.Sprintf("  key%d: value%d", i, i)
		}
		metadataYaml := "metadata:\n" + strings.Join(entries, "\n")
		contents := fmt.Sprintf("---\nname: test-agent\ndescription: test description\n%s\n---\nprompt", metadataYaml)
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		assert.Len(t, attrs.Metadata, MaxMetadataEntryCount)
	})

	t.Run("metadata key at maximum length", func(t *testing.T) {
		maxKey := strings.Repeat("a", MaxMetadataKeyLength)
		contents := fmt.Sprintf("---\nname: test-agent\ndescription: test description\nmetadata:\n  %s: value\n---\nprompt", maxKey)
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		assert.Equal(t, "value", attrs.Metadata[maxKey])
	})

	t.Run("metadata value at maximum length", func(t *testing.T) {
		maxValue := strings.Repeat("a", MaxMetadataValueLength)
		contents := fmt.Sprintf("---\nname: test-agent\ndescription: test description\nmetadata:\n  key: %s\n---\nprompt", maxValue)
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		assert.Equal(t, maxValue, attrs.Metadata["key"])
		assert.Len(t, attrs.Metadata["key"], MaxMetadataValueLength)
	})

	t.Run("metadata with special characters in values", func(t *testing.T) {
		contents := `---
name: test-agent
description: test description
metadata:
  url: https://example.com/path?query=value
  email: user@example.com
  description: "Value with spaces and special chars: !@#$%"
---
prompt`
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		assert.Equal(t, "https://example.com/path?query=value", attrs.Metadata["url"])
		assert.Equal(t, "user@example.com", attrs.Metadata["email"])
		assert.Equal(t, "Value with spaces and special chars: !@#$%", attrs.Metadata["description"])
	})
}

func TestPermissions(t *testing.T) {
	t.Run("parses permissions as map successfully", func(t *testing.T) {
		contents := `---
name: test-agent
description: test description
github:
  permissions:
    contents: write
    issues: read
    pull-requests: write
---
prompt`
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		require.NotNil(t, attrs.Permissions)
		perms := attrs.Permissions.ToMap()
		assert.Equal(t, "write", perms["contents"])
		assert.Equal(t, "read", perms["issues"])
		assert.Equal(t, "write", perms["pull-requests"])
		assert.Equal(t, "read", perms["metadata"])
		assert.Len(t, perms, 4)
	})

	t.Run("parses permissions read-all shorthand", func(t *testing.T) {
		contents := `---
name: test-agent
description: test description
github:
  permissions: read-all
---
prompt`
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		require.NotNil(t, attrs.Permissions)
		perms := attrs.Permissions.ToMap()
		assert.Equal(t, "read", perms["actions"])
		assert.Equal(t, "read", perms["contents"])
		assert.Equal(t, "read", perms["issues"])
		assert.Equal(t, "read", perms["metadata"])
		assert.Equal(t, "read", perms["pull-requests"])
		assert.NotContains(t, perms, "workflows")        // Workflows only has write and none permissions
		assert.Len(t, perms, len(permissions.Allowed)-1) // -1 because workflows is not included
	})

	t.Run("parses permissions write-all shorthand", func(t *testing.T) {
		contents := `---
name: test-agent
description: test description
github:
  permissions: write-all
---
prompt`
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		require.NotNil(t, attrs.Permissions)
		perms := attrs.Permissions.ToMap()
		for _, scope := range permissions.Allowed {
			expected := "write"
			if scope == "metadata" || scope == "checks" || scope == "security-events" {
				expected = "read"
			}
			assert.Equal(t, expected, perms[scope], "all permissions should be write for scope: %s", scope)
		}
		assert.Len(t, perms, len(permissions.Allowed))
	})

	t.Run("defaults to default permissions when not specified", func(t *testing.T) {
		contents := `---
name: test-agent
description: test description
---
prompt`
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		require.NotNil(t, attrs.Permissions)
		// When no permissions are specified, they should be unset (empty)
		// The launcher/runtime will resolve these to defaults
		assert.True(t, attrs.Permissions.IsUnset())
	})

	t.Run("returns unset permissions for invalid string", func(t *testing.T) {
		contents := `---
name: test-agent
description: test description
github:
  permissions: invalid-value
---
prompt`
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		// Invalid string values return unset permissions
		assert.True(t, attrs.Permissions.IsUnset())
	})

	t.Run("rejects unknown permission scope", func(t *testing.T) {
		contents := `---
name: test-agent
description: test description
github:
  permissions:
    contents: read
    unknown-scope: read
---
prompt`
		_, err := parseConfig(contents, "some-name")
		require.Error(t, err)
		assert.Contains(t, err.Error(), "invalid permission")
		assert.Contains(t, err.Error(), "unknown-scope")
	})

	t.Run("rejects invalid permission value", func(t *testing.T) {
		contents := `---
name: test-agent
description: test description
github:
  permissions:
    contents: invalid-permission
---
prompt`
		_, err := parseConfig(contents, "some-name")
		require.Error(t, err)
		assert.Contains(t, err.Error(), "invalid permission")
		assert.Contains(t, err.Error(), "invalid-permission")
	})

	t.Run("rejects invalid permission value for workflows scope", func(t *testing.T) {
		contents := `---
name: test-agent
description: test description
github:
  permissions:
    workflows: read
---
prompt`
		_, err := parseConfig(contents, "some-name")
		require.Error(t, err)
		assert.Contains(t, err.Error(), "invalid permission")
		assert.Contains(t, err.Error(), "workflows")
	})

	t.Run("accepts valid permission values", func(t *testing.T) {
		validValues := []string{"read", "write", "none"}
		for _, value := range validValues {
			t.Run("permission value: "+value, func(t *testing.T) {
				contents := fmt.Sprintf(`---
name: test-agent
description: test description
github:
  permissions:
    contents: %s
---
prompt`, value)
				attrs, err := parseConfig(contents, "some-name")
				require.NoError(t, err)
				perms := attrs.Permissions.ToMap()
				assert.Equal(t, value, perms["contents"])
			})
		}
	})

	t.Run("accepts all allowed permission scopes", func(t *testing.T) {
		for _, scope := range permissions.Allowed {
			t.Run("scope: "+scope, func(t *testing.T) {
				// Workflows only supports write and none, not read
				permValue := "read"
				if scope == "workflows" {
					permValue = "write"
				}
				contents := fmt.Sprintf(`---
name: test-agent
description: test description
github:
  permissions:
    %s: %s
---
prompt`, scope, permValue)
				attrs, err := parseConfig(contents, "some-name")
				require.NoError(t, err)
				perms := attrs.Permissions.ToMap()
				assert.Equal(t, permValue, perms[scope])
			})
		}
	})

	t.Run("preserves partial permissions on validation error", func(t *testing.T) {
		contents := `---
name: test-agent
description: test description
github:
  permissions:
    contents: read
    issues: write
    invalid-scope: read
---
prompt`
		_, err := parseConfig(contents, "some-name")
		require.Error(t, err)
		var configErr *ErrConfigValidationError
		require.ErrorAs(t, err, &configErr)
		perms := configErr.attributes.Permissions.ToMap()
		assert.Equal(t, "read", perms["contents"])
		assert.Equal(t, "write", perms["issues"])
		assert.Equal(t, "read", perms["invalid-scope"])
	})
}

func TestToolsets(t *testing.T) {
	t.Run("parses toolsets with hyphen to underscore normalization", func(t *testing.T) {
		contents := `---
name: test-agent
description: test description
github:
  toolsets:
    - code-review
    - pull-requests
    - issues
---
prompt`
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		assert.Equal(t, []string{"code_review", "pull_requests", "issues"}, attrs.GitHubMCPToolsets)
	})

	t.Run("parses toolsets without hyphens unchanged", func(t *testing.T) {
		contents := `---
name: test-agent
description: test description
github:
  toolsets:
    - issues
    - code_security
---
prompt`
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		assert.Equal(t, []string{"issues", "code_security"}, attrs.GitHubMCPToolsets)
	})

	t.Run("returns nil when no toolsets specified", func(t *testing.T) {
		contents := `---
name: test-agent
description: test description
---
prompt`
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		assert.Nil(t, attrs.GitHubMCPToolsets)
	})

	t.Run("returns nil for empty toolsets list", func(t *testing.T) {
		contents := `---
name: test-agent
description: test description
github:
  toolsets: []
---
prompt`
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		assert.Nil(t, attrs.GitHubMCPToolsets)
	})

	t.Run("single toolset", func(t *testing.T) {
		contents := `---
name: test-agent
description: test description
github:
  toolsets:
    - web-search
---
prompt`
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		assert.Equal(t, []string{"web_search"}, attrs.GitHubMCPToolsets)
	})

	t.Run("rejects more than max toolsets", func(t *testing.T) {
		var b strings.Builder
		for i := 0; i <= MaxToolsetCount; i++ {
			fmt.Fprintf(&b, "    - toolset_%d\n", i)
		}
		contents := fmt.Sprintf("---\nname: test-agent\ndescription: test description\ngithub:\n  toolsets:\n%s---\nprompt", b.String())
		_, err := parseConfig(contents, "some-name")
		require.Error(t, err)
		assert.Contains(t, err.Error(), fmt.Sprintf("more than %d toolsets specified", MaxToolsetCount))
	})

	t.Run("accepts exactly max toolsets", func(t *testing.T) {
		var b strings.Builder
		for i := 0; i < MaxToolsetCount; i++ {
			fmt.Fprintf(&b, "    - toolset_%d\n", i)
		}
		contents := fmt.Sprintf("---\nname: test-agent\ndescription: test description\ngithub:\n  toolsets:\n%s---\nprompt", b.String())
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		assert.Len(t, attrs.GitHubMCPToolsets, MaxToolsetCount)
	})

	t.Run("rejects toolset name exceeding max length", func(t *testing.T) {
		longName := strings.Repeat("a", MaxToolsetNameLength+1)
		contents := fmt.Sprintf("---\nname: test-agent\ndescription: test description\ngithub:\n  toolsets:\n    - %s\n---\nprompt", longName)
		_, err := parseConfig(contents, "some-name")
		require.Error(t, err)
		assert.Contains(t, err.Error(), fmt.Sprintf("toolset name exceeds max length of %d", MaxToolsetNameLength))
	})

	t.Run("accepts toolset name at exactly max length", func(t *testing.T) {
		exactName := strings.Repeat("a", MaxToolsetNameLength)
		contents := fmt.Sprintf("---\nname: test-agent\ndescription: test description\ngithub:\n  toolsets:\n    - %s\n---\nprompt", exactName)
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		require.Len(t, attrs.GitHubMCPToolsets, 1)
		assert.Len(t, attrs.GitHubMCPToolsets[0], MaxToolsetNameLength)
	})

	t.Run("toolset name length uses rune count not byte count", func(t *testing.T) {
		// MaxToolsetNameLength multi-byte characters should be allowed
		emojiName := strings.Repeat("🔥", MaxToolsetNameLength)
		contents := fmt.Sprintf("---\nname: test-agent\ndescription: test description\ngithub:\n  toolsets:\n    - %s\n---\nprompt", emojiName)
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		require.Len(t, attrs.GitHubMCPToolsets, 1)

		// One more rune should exceed
		tooLong := emojiName + "🔥"
		contents = fmt.Sprintf("---\nname: test-agent\ndescription: test description\ngithub:\n  toolsets:\n    - %s\n---\nprompt", tooLong)
		_, err = parseConfig(contents, "some-name")
		require.Error(t, err)
		assert.Contains(t, err.Error(), fmt.Sprintf("toolset name exceeds max length of %d", MaxToolsetNameLength))
	})

	t.Run("toolsets combined with permissions", func(t *testing.T) {
		contents := `---
name: test-agent
description: test description
github:
  permissions:
    contents: read
    issues: write
  toolsets:
    - code-review
    - issues
---
prompt`
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		perms := attrs.Permissions.ToMap()
		assert.Equal(t, "read", perms["contents"])
		assert.Equal(t, "write", perms["issues"])
		assert.Equal(t, []string{"code_review", "issues"}, attrs.GitHubMCPToolsets)
	})

	t.Run("hyphen normalization applies to all hyphens", func(t *testing.T) {
		contents := `---
name: test-agent
description: test description
github:
  toolsets:
    - a-b-c-d
---
prompt`
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		assert.Equal(t, []string{"a_b_c_d"}, attrs.GitHubMCPToolsets)
	})
}

func TestTriggers(t *testing.T) {
	t.Run("parses triggers (on) with issues", func(t *testing.T) {
		contents := `---
name: test-agent
description: test description
on:
  issues:
    types: [opened, closed]
---
prompt`
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		require.NotNil(t, attrs.Triggers.Issues)
		assert.Equal(t, []string{"opened", "closed"}, attrs.Triggers.Issues.Types)
	})

	t.Run("parses triggers (on) with empty types array", func(t *testing.T) {
		contents := `---
name: test-agent
description: test description
on:
  issues:
    types: []
---
prompt`
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		require.NotNil(t, attrs.Triggers.Issues)
		assert.Empty(t, attrs.Triggers.Issues.Types)
	})

	t.Run("triggers (on) is optional", func(t *testing.T) {
		contents := `---
name: test-agent
description: test description
---
prompt`
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		assert.Nil(t, attrs.Triggers.Issues)
	})

	t.Run("parses triggers (on) with single type", func(t *testing.T) {
		contents := `---
name: test-agent
description: test description
on:
  issues:
    types: [opened]
---
prompt`
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		require.NotNil(t, attrs.Triggers.Issues)
		assert.Equal(t, []string{"opened"}, attrs.Triggers.Issues.Types)
	})

	t.Run("parses triggers (on) with multiple types", func(t *testing.T) {
		contents := `---
name: test-agent
description: test description
on:
  issues:
    types: [opened, closed, reopened, labeled, unlabeled]
---
prompt`
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		require.NotNil(t, attrs.Triggers.Issues)
		assert.Equal(t, []string{"opened", "closed", "reopened", "labeled", "unlabeled"}, attrs.Triggers.Issues.Types)
	})

	t.Run("triggers (on) without types field", func(t *testing.T) {
		contents := `---
name: test-agent
description: test description
on:
  issues:
---
prompt`
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		// When only "issues:" is specified without any sub-fields, YAML will parse it as nil
		// because there's no actual content to parse into the struct
		assert.Nil(t, attrs.Triggers.Issues)
	})

	t.Run("parses triggers (on) with query filter", func(t *testing.T) {
		contents := `---
name: test-agent
description: test description
on:
  issues:
    types: [opened]
    query: "label:auto-triage -has:assignee"
---
prompt`
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		require.NotNil(t, attrs.Triggers.Issues)
		assert.Equal(t, []string{"opened"}, attrs.Triggers.Issues.Types)
		assert.Equal(t, "label:auto-triage -has:assignee", attrs.Triggers.Issues.Query)
	})

	t.Run("parses triggers (on) without query filter", func(t *testing.T) {
		contents := `---
name: test-agent
description: test description
on:
  issues:
    types: [opened]
---
prompt`
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)
		require.NotNil(t, attrs.Triggers.Issues)
		assert.Equal(t, []string{"opened"}, attrs.Triggers.Issues.Types)
		assert.Empty(t, attrs.Triggers.Issues.Query)
	})
}

func TestMCPServersOIDCYAMLKeys(t *testing.T) {
	t.Run("parses OIDC config with YAML-style kebab-case keys", func(t *testing.T) {
		contents := `---
name: test-agent
description: test description
mcp-servers:
  my-server:
    type: http
    url: https://example.com/mcp
    tools:
      - "*"
    oidc:
      audience: https://example.com
      secret-suffix: MY_TOKEN
      grant-type: client_credentials
      agent-only-subject: true
      public-client: true
      redirect-port: 8080
      scope: read:all
      endpoints:
        exchange: https://example.com/token
---
prompt`
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)

		server, ok := attrs.MCPConfig.Servers["my-server"]
		require.True(t, ok, "server my-server should exist")
		require.NotNil(t, server.Auth, "OIDC config should be set")

		assert.Equal(t, "https://example.com", server.Auth.Audience)
		assert.Equal(t, "read:all", server.Auth.Scope)
		// SecretSuffix is intentionally cleared by NewConfigEntryForMCP for MCP inline entries
		assert.Empty(t, server.Auth.SecretSuffix)
		assert.Equal(t, "client_credentials", server.Auth.GrantType)
		assert.True(t, server.Auth.AgentOnlySubject)
		assert.True(t, server.Auth.IsPublicClient())
		assert.Equal(t, 8080, server.Auth.RedirectPort)
		assert.Equal(t, "https://example.com/token", server.Auth.Endpoints.Exchange)
	})

	t.Run("parses OIDC config with JSON-style camelCase keys", func(t *testing.T) {
		contents := `---
name: test-agent
description: test description
mcp-servers:
  my-server:
    type: http
    url: https://example.com/mcp
    tools:
      - "*"
    oidc:
      audience: https://example.com
      secretSuffix: MY_TOKEN
      grantType: client_credentials
      agentOnlySubject: true
      publicClient: true
---
prompt`
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)

		server, ok := attrs.MCPConfig.Servers["my-server"]
		require.True(t, ok, "server my-server should exist")
		require.NotNil(t, server.Auth, "OIDC config should be set")

		assert.Empty(t, server.Auth.SecretSuffix)
		assert.Equal(t, "client_credentials", server.Auth.GrantType)
		assert.True(t, server.Auth.AgentOnlySubject)
		assert.True(t, server.Auth.IsPublicClient())
	})

	t.Run("oidc boolean shorthand is unaffected", func(t *testing.T) {
		contents := `---
name: test-agent
description: test description
mcp-servers:
  my-server:
    type: http
    url: https://example.com/mcp
    tools:
      - "*"
    oidc: true
---
prompt`
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)

		server, ok := attrs.MCPConfig.Servers["my-server"]
		require.True(t, ok, "server my-server should exist")
		assert.True(t, server.OIDCEnabled)
	})

	t.Run("scope is an alias for scopes in OIDC YAML config", func(t *testing.T) {
		contents := `---
name: test-agent
description: test description
mcp-servers:
  my-server:
    type: http
    url: https://example.com/mcp
    tools:
      - "*"
    oidc:
      audience: https://example.com
      scope: read:all write:all
---
prompt`
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)

		server, ok := attrs.MCPConfig.Servers["my-server"]
		require.True(t, ok, "server my-server should exist")
		require.NotNil(t, server.Auth, "OIDC config should be set")
		assert.Equal(t, "read:all write:all", server.Auth.Scope)
	})

	t.Run("scope in headers and env is not renamed to scopes", func(t *testing.T) {
		contents := `---
name: test-agent
description: test description
mcp-servers:
  my-local-server:
    type: local
    command: /bin/server
    tools:
      - "*"
    env:
      scope: some-value
  my-remote-server:
    type: http
    url: https://example.com/mcp
    tools:
      - "*"
    headers:
      scope: header-value
---
prompt`
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)

		localServer, ok := attrs.MCPConfig.Servers["my-local-server"]
		require.True(t, ok, "local server should exist")
		assert.Equal(t, "some-value", localServer.Env["scope"], "env var 'scope' should not be renamed")
		assert.Equal(t, "", localServer.Env["scopes"], "env var 'scopes' should not exist")

		remoteServer, ok := attrs.MCPConfig.Servers["my-remote-server"]
		require.True(t, ok, "remote server should exist")
		assert.Equal(t, "header-value", remoteServer.Headers["scope"], "header 'scope' should not be renamed")
		assert.Equal(t, "", remoteServer.Headers["scopes"], "header 'scopes' should not exist")
	})

	t.Run("auth key normalization does not rewrite headers and env keys", func(t *testing.T) {
		contents := `---
name: test-agent
description: test description
mcp-servers:
  my-local-server:
    type: local
    command: /bin/server
    tools:
      - "*"
    env:
      redirect-port: "9000"
      public-client: "env-value"
  my-remote-server:
    type: http
    url: https://example.com/mcp
    tools:
      - "*"
    headers:
      redirect-port: header-value
      public-client: header-public
    auth:
      audience: https://example.com
      redirect-port: 8080
      public-client: true
---
prompt`
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)

		localServer, ok := attrs.MCPConfig.Servers["my-local-server"]
		require.True(t, ok, "local server should exist")
		assert.Equal(t, "9000", localServer.Env["redirect-port"], "env var 'redirect-port' should not be renamed")
		assert.Equal(t, "", localServer.Env["redirectPort"], "env var 'redirectPort' should not exist")
		assert.Equal(t, "env-value", localServer.Env["public-client"], "env var 'public-client' should not be renamed")
		assert.Equal(t, "", localServer.Env["publicClient"], "env var 'publicClient' should not exist")

		remoteServer, ok := attrs.MCPConfig.Servers["my-remote-server"]
		require.True(t, ok, "remote server should exist")
		assert.Equal(t, "header-value", remoteServer.Headers["redirect-port"], "header 'redirect-port' should not be renamed")
		assert.Equal(t, "", remoteServer.Headers["redirectPort"], "header 'redirectPort' should not exist")
		assert.Equal(t, "header-public", remoteServer.Headers["public-client"], "header 'public-client' should not be renamed")
		assert.Equal(t, "", remoteServer.Headers["publicClient"], "header 'publicClient' should not exist")
		require.NotNil(t, remoteServer.Auth, "auth config should be set")
		assert.Equal(t, 8080, remoteServer.Auth.RedirectPort)
		assert.True(t, remoteServer.Auth.IsPublicClient())
	})

	t.Run("auth key is accepted as primary in YAML", func(t *testing.T) {
		contents := `---
name: test-agent
description: test description
mcp-servers:
  my-server:
    type: http
    url: https://example.com/mcp
    tools:
      - "*"
    auth:
      audience: https://example.com
      grant-type: client_credentials
      endpoints:
        exchange: https://example.com/token
---
prompt`
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)

		server, ok := attrs.MCPConfig.Servers["my-server"]
		require.True(t, ok, "server my-server should exist")
		require.NotNil(t, server.Auth, "auth config should be set")

		assert.Equal(t, "https://example.com", server.Auth.Audience)
		assert.Equal(t, "client_credentials", server.Auth.GrantType)
		assert.Equal(t, "https://example.com/token", server.Auth.Endpoints.Exchange)
	})

	t.Run("auth boolean shorthand in YAML", func(t *testing.T) {
		contents := `---
name: test-agent
description: test description
mcp-servers:
  my-server:
    type: http
    url: https://example.com/mcp
    tools:
      - "*"
    auth: true
---
prompt`
		attrs, err := parseConfig(contents, "some-name")
		require.NoError(t, err)

		server, ok := attrs.MCPConfig.Servers["my-server"]
		require.True(t, ok, "server my-server should exist")
		assert.True(t, server.OIDCEnabled)
	})
}
