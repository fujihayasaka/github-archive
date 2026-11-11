package launcher

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestValidateWorkflowYAML_ValidWorkflow(t *testing.T) {
	validYAML := `
name: Test Workflow
on: push
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run tests
        run: echo "Hello World"
`
	result := validateWorkflowYAML(validYAML)
	assert.True(t, result.Valid, "Expected valid workflow")
	assert.Empty(t, result.Errors, "Expected no errors")
}

func TestValidateWorkflowYAML_InvalidWorkflow(t *testing.T) {
	// Missing required 'jobs' key
	invalidYAML := `
name: Test Workflow
on: push
`
	result := validateWorkflowYAML(invalidYAML)
	assert.False(t, result.Valid, "Expected invalid workflow")
	assert.NotEmpty(t, result.Errors, "Expected errors")
}

func TestValidateWorkflowYAML_DynamicTrigger(t *testing.T) {
	// Workflow with 'on: dynamic' which is a GitHub-internal trigger type
	dynamicYAML := `
name: Dynamic Workflow
on: dynamic
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Test
        run: echo "test"
`
	result := validateWorkflowYAML(dynamicYAML)
	assert.True(t, result.Valid, "Expected valid workflow with dynamic trigger")
	assert.Empty(t, result.Errors, "Expected no errors for dynamic trigger")
}

func TestValidateWorkflowYAML_MalformedYAML(t *testing.T) {
	malformedYAML := `
name: Test
on: push
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Test
        run: |
          echo "hello
          # Missing closing quote/block
      invalid yaml here: [
`
	result := validateWorkflowYAML(malformedYAML)
	assert.False(t, result.Valid, "Expected invalid workflow for malformed YAML")
	assert.NotEmpty(t, result.Errors, "Expected errors for malformed YAML")
}

func TestValidateWorkflowYAML_ComplexWorkflow(t *testing.T) {
	complexYAML := `
name: Complex Workflow
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
jobs:
  build:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        node: [16, 18, 20]
    steps:
      - uses: actions/checkout@v4
      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node }}
      - name: Build
        run: npm ci && npm run build
  test:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Test
        run: npm test
`
	result := validateWorkflowYAML(complexYAML)
	assert.True(t, result.Valid, "Expected valid complex workflow")
	assert.Empty(t, result.Errors, "Expected no errors for complex workflow")
}

func TestWorkflowValidationResult_FullError(t *testing.T) {
	result := &WorkflowValidationResult{
		Valid: false,
		Errors: []WorkflowValidationError{
			{Message: "missing required field 'jobs'", Line: 3},
			{Message: "invalid trigger type"},
		},
	}

	fullError := result.FullError()
	require.NotEmpty(t, fullError)
	assert.Contains(t, fullError, "workflow validation failed")
	assert.Contains(t, fullError, "missing required field 'jobs'")
	assert.Contains(t, fullError, "invalid trigger type")
	assert.Contains(t, fullError, "line 3")
}

func TestWorkflowValidationResult_FullError_Empty(t *testing.T) {
	result := &WorkflowValidationResult{
		Valid:  true,
		Errors: []WorkflowValidationError{},
	}

	fullError := result.FullError()
	assert.Empty(t, fullError, "Expected empty error for valid result")
}

func TestSimpleFileProvider(t *testing.T) {
	content := "test content"
	provider := NewSimpleFileProvider(content)

	t.Run("GetFileContents returns content", func(t *testing.T) {
		got, err := provider.GetFileContents(".github/workflows/workflow.yml")
		require.NoError(t, err)
		assert.Equal(t, content, got)
	})

	t.Run("GetFileContents returns content for any path", func(t *testing.T) {
		got, err := provider.GetFileContents("any/path.yml")
		require.NoError(t, err)
		assert.Equal(t, content, got)
	})

	t.Run("GetFileInfo returns info with provided path", func(t *testing.T) {
		info, err := provider.GetFileInfo(".github/workflows/workflow.yml")
		require.NoError(t, err)
		assert.Equal(t, ".github/workflows/workflow.yml", info.Path)
	})

	t.Run("GetFileInfo returns info for any path", func(t *testing.T) {
		info, err := provider.GetFileInfo("custom/path.yml")
		require.NoError(t, err)
		assert.Equal(t, "custom/path.yml", info.Path)
	})
}
