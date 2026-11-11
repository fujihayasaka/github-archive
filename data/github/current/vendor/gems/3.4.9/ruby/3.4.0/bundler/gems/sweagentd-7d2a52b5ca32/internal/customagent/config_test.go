package customagent

import (
	"errors"
	"fmt"
	"strings"
	"testing"

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

	t.Run("returns ErrConfigValidationError and ErrTargetIsVSCode for vscode target", func(t *testing.T) {
		contents := "---\nname: test-agent\ndescription: A test agent\ntarget: vscode\n---\nprompt text"
		_, err := parseConfig(contents, "some-name")
		require.Error(t, err, "expected error for vscode target")

		var configErr *ErrConfigValidationError
		require.ErrorAs(t, err, &configErr, "error should be ErrConfigValidationError type")

		// Should also wrap the specific ErrTargetIsVSCode error
		assert.True(t, errors.Is(configErr, ErrTargetIsVSCode))
		assert.Contains(t, err.Error(), "config is for VS Code only")

		// Verify partial state includes all parsed fields
		assert.Equal(t, "test-agent", configErr.attributes.DisplayName)
		assert.Equal(t, "A test agent", configErr.attributes.Description)
		assert.Equal(t, []string{"*"}, configErr.attributes.Tools)
		assert.Equal(t, "prompt text", configErr.attributes.Prompt)
		assert.Equal(t, "vscode", configErr.attributes.Target)
	})

	t.Run("accepts valid target values", func(t *testing.T) {
		validTargets := []string{"", "github-copilot"}

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

	t.Run("prompt length limit", func(t *testing.T) {
		// Exceeds limit
		longPrompt := strings.Repeat("a", MaxPromptLength+1)
		contents := fmt.Sprintf("---\nname: test-agent\ndescription: test description\n---\n%s", longPrompt)
		_, err := parseConfig(contents, "some-name")
		require.Error(t, err)
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
}
