// Package diff provides utility functions and types for working with diffs.
package diff

import (
	"errors"
	"path/filepath"
	"strconv"
	"strings"
)

// ChangedCodeRegion represents a region of code that has changed between two versions of a file.
type ChangedCodeRegion struct {
	OldFile      string
	NewFile      string
	OldLineRange CodeRange
	NewLineRange CodeRange
}

// CodeRange represents a range of line numbers in a source code file.
type CodeRange struct {
	Start int
	End   int
}

// ExtractChangedCodeRegions parses a unified diff string and extracts the changed code regions.
func ExtractChangedCodeRegions(diff string) ([]ChangedCodeRegion, error) {
	lines := strings.Split(diff, "\n")
	if len(lines) > 0 && strings.HasPrefix(lines[0], "=") {
		lines = lines[1:]
	}

	var oldFile, newFile string
	var changedRegions []ChangedCodeRegion

	for _, line := range lines {
		switch {
		case strings.HasPrefix(line, "--- "):
			oldFile = filepath.Clean(strings.TrimPrefix(strings.TrimSpace(line[4:]), "a/"))
		case strings.HasPrefix(line, "+++ "):
			newFile = filepath.Clean(strings.TrimPrefix(strings.TrimSpace(line[4:]), "b/"))
		case strings.HasPrefix(line, "@@ "):
			if oldFile == "" || newFile == "" {
				return nil, errors.New("hunk header found before file headers")
			}
			hunkHeader := line
			endOfHunkHeader := strings.LastIndex(hunkHeader, "@@")
			if endOfHunkHeader == -1 {
				return nil, errors.New("invalid hunk header: " + hunkHeader)
			}
			header := hunkHeader[4 : endOfHunkHeader-1]
			parts := strings.Split(header, " ")
			if len(parts) != 2 {
				return nil, errors.New("invalid line numbers in hunk header: " + hunkHeader)
			}
			oldLineRange, err := parseLineRange(parts[0])
			if err != nil {
				return nil, err
			}
			newLineRange, err := parseLineRange(parts[1])
			if err != nil {
				return nil, err
			}
			changedRegions = append(changedRegions, ChangedCodeRegion{
				OldFile:      oldFile,
				NewFile:      newFile,
				OldLineRange: oldLineRange,
				NewLineRange: newLineRange,
			})
		}
	}
	return changedRegions, nil
}

func parseLineRange(s string) (CodeRange, error) {
	s = strings.TrimPrefix(s, "-")
	s = strings.TrimPrefix(s, "+")
	nums := strings.Split(s, ",")
	start, err := strconv.Atoi(nums[0])
	if err != nil {
		return CodeRange{}, err
	}
	length := 1
	if len(nums) == 2 {
		length, err = strconv.Atoi(nums[1])
		if err != nil {
			return CodeRange{}, err
		}
	}
	return CodeRange{Start: start, End: start + length - 1}, nil
}
