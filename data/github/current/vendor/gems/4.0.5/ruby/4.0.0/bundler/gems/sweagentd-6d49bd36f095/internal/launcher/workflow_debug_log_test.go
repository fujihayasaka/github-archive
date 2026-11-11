package launcher

import (
	"encoding/hex"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestPrepareWorkflowContentForDebugLog_ValidUTF8(t *testing.T) {
	encoded, valid, truncated := prepareWorkflowContentForDebugLog("name: ok\n")
	assert.True(t, valid)
	assert.False(t, truncated)
	assert.Equal(t, "name: ok\n", encoded)
}

func TestPrepareWorkflowContentForDebugLog_InvalidUTF8HexEncoded(t *testing.T) {
	content := "abc\xE2xyz"
	encoded, valid, truncated := prepareWorkflowContentForDebugLog(content)
	assert.False(t, valid)
	assert.False(t, truncated)
	assert.Equal(t, hex.EncodeToString([]byte(content)), encoded)
}

func TestPrepareWorkflowContentForDebugLog_Truncated(t *testing.T) {
	content := strings.Repeat("a", workflowContentDebugLogMaxBytes+1000)
	encoded, valid, truncated := prepareWorkflowContentForDebugLog(content)
	assert.True(t, valid)
	assert.True(t, truncated)
	assert.Len(t, encoded, workflowContentDebugLogMaxBytes)
}

func TestPrepareWorkflowContentForDebugLog_TruncatedAndInvalid(t *testing.T) {
	content := strings.Repeat("a", workflowContentDebugLogMaxBytes) + "\xE2"
	encoded, valid, truncated := prepareWorkflowContentForDebugLog(content)
	assert.True(t, truncated)
	// Truncation cuts off the invalid tail byte; the retained prefix is pure ASCII.
	assert.True(t, valid)
	assert.Len(t, encoded, workflowContentDebugLogMaxBytes)
}

func TestPrepareWorkflowContentForDebugLog_Empty(t *testing.T) {
	encoded, valid, truncated := prepareWorkflowContentForDebugLog("")
	assert.True(t, valid)
	assert.False(t, truncated)
	assert.Equal(t, "", encoded)
}
