// Package guidelines provides types and utilities for managing coding guidelines.
package guidelines

import (
	"fmt"

	"github.com/bmatcuk/doublestar/v4"
)

// CodingGuideline is a reference to a repository coding guideline.
// This struct is copied from the copilot-api code.
type CodingGuideline struct {
	ID           uint64   `json:"id"`
	Name         string   `json:"name"`
	Description  string   `json:"description"`
	FilePatterns []string `json:"file_patterns,omitempty"`
}

// IsAppliedToPath returns true if the coding guideline is applied to the given file path.
func (cg *CodingGuideline) IsAppliedToPath(filePath string) (bool, error) {
	// This is copied directly from copilot-api code (but removed a few fields we don't care about)
	// TODO: consider if we should rely on the copilot-api code instead (by importing it, and using their type instead)
	if len(cg.FilePatterns) == 0 {
		return true, nil
	}

	for _, pattern := range cg.FilePatterns {
		// To follow VSCode behavior, these wildcard patterns
		// should always result in using the instruction.
		// See https://github.com/microsoft/vscode/blob/main/src/vs/workbench/contrib/chat/common/promptSyntax/computeAutomaticInstructions.ts#L200
		if pattern == "**" || pattern == "**/*" || pattern == "*" {
			return true, nil
		}
		match, err := doublestar.PathMatch(pattern, filePath)
		if err != nil {
			return false, fmt.Errorf("error matching %s and %s: %w", pattern, filePath, err)
		}
		if match {
			return true, nil
		}
	}
	return false, nil
}

// FilterApplicable filters coding guidelines to only those that apply to at least one of the given file paths.
// It deduplicates guidelines by ID, Name, and Description, returning only unique guidelines.
// Guidelines with no file patterns are always included (they apply to all files).
// Returns nil if no guidelines are provided or none match.
func FilterApplicable(guidelines []CodingGuideline, filePaths []string) []CodingGuideline {
	if len(guidelines) == 0 {
		return nil
	}

	type guidelineKey struct {
		ID          uint64
		Name        string
		Description string
	}
	seen := make(map[guidelineKey]struct{})
	matched := make([]CodingGuideline, 0, len(guidelines))

	for _, guideline := range guidelines {
		// Deduplicate by ID, Name, and Description
		key := guidelineKey{
			ID:          guideline.ID,
			Name:        guideline.Name,
			Description: guideline.Description,
		}
		if _, ok := seen[key]; ok {
			continue
		}

		// Guidelines with no file patterns apply to all files
		if len(guideline.FilePatterns) == 0 {
			matched = append(matched, guideline)
			seen[key] = struct{}{}
			continue
		}

		// Check if guideline applies to any of the given file paths
		for _, filePath := range filePaths {
			applied, err := guideline.IsAppliedToPath(filePath)
			if err != nil {
				// Skip on error (pattern matching failed)
				continue
			}
			if applied {
				matched = append(matched, guideline)
				seen[key] = struct{}{}
				break
			}
		}
	}

	if len(matched) == 0 {
		return nil
	}

	return matched
}
