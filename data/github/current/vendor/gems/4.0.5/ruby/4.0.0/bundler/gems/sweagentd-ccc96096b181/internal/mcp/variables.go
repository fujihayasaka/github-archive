package mcp

import "regexp"

var mcpVarRegex = regexp.MustCompile(`^COPILOT_MCP_([a-zA-Z0-9_]*)$`)

// IsVar returns true if the variable name follows the MCP naming pattern
func IsVar(name string) bool {
	return mcpVarRegex.MatchString(name)
}
