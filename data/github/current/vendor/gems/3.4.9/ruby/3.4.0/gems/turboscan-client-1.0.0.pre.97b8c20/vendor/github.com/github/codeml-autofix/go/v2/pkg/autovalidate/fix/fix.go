// Package fix defines structures and helpers for representing a single
// fix, in the autovalidation system.
package fix

import (
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"

	"sort"
	"strings"

	"github.com/hexops/gotextdiff"
	"github.com/pkg/errors"

	_codebase "github.com/github/codeml-autofix/go/v2/pkg/autofix/codebase"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/editcommands"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/fixdata"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/replacement"
	autofix_utils "github.com/github/codeml-autofix/go/v2/pkg/autofix/utils"
)

// Fix represents a single fix candidate produced by autofix used in
// autovalidation.
type Fix struct {
	Diffs []fixdata.Diff    `json:"diffs"`
	Alert fixdata.RespAlert `json:"alert"`
}

// Represent a result of applying a patch.
type patchResult interface {
	isPatchResult()
}

type newFile struct {
	Content string
}

func (*newFile) isPatchResult() {}

type deleteFile struct {
}

func (*deleteFile) isPatchResult() {}

type updateFile struct {
	Content string
}

func (*updateFile) isPatchResult() {}

// NewFromFile loads a Fix from the given file path, interpreting the file
// according to the specified format.
func NewFromFile(path string, format Format) (*Fix, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	switch format {
	case FormatFix:
		var fix Fix
		if err := json.NewDecoder(file).Decode(&fix); err != nil {
			return nil, err
		}
		return &fix, nil
	case FormatAutoFixResponse:
		var autofixResponse fixdata.AutofixResponse
		if err := json.NewDecoder(file).Decode(&autofixResponse); err != nil {
			return nil, err
		}
		return FromAutofixResponse(&autofixResponse)
	default:
		return nil, errors.Errorf("unsupported fix format: %s", format)
	}
}

// FromAutofixResponse converts a single-output AutofixResponse into a Fix.
// Returns an error if the response is nil or doesn't contain exactly one output.
func FromAutofixResponse(response *fixdata.AutofixResponse) (*Fix, error) {
	if response == nil {
		return nil, errors.New("response is nil")
	}

	outputs := []fixdata.Output(*response)

	if len(outputs) != 1 {
		return nil, errors.New("response should contain exactly one output")
	}

	outcome := outputs[0].Outcome
	alert := outputs[0].Alert

	return &Fix{
		Diffs: outcome.Diffs,
		Alert: alert,
	}, nil
}

// Apply applies the fix to the given codebase.
// In case of an error, the codebase may be in an inconsistent state as there is no attempt to rollback
// possible patches.
func (f *Fix) Apply(codebase _codebase.VirtualCodebase) error {
	// Use a map so we can keep track of which files we've already processed.
	// We currently do not support multiple unified diffs per file, because it is unknown if edit commands compose.
	patchResults := make(map[string]patchResult, len(f.Diffs))
	for _, diff := range f.Diffs {
		// Normalize the path for the current OS - on Windows, convert Unix-style paths
		pathForCodebaseAccess := diff.Path
		if runtime.GOOS == "windows" {
			pathForCodebaseAccess = filepath.FromSlash(pathForCodebaseAccess)
		}

		unifiedDiff, unifiedDiffParseErr := replacement.ParseUnifiedString(diff.Diff)
		if unifiedDiffParseErr != nil {
			return errors.Wrapf(unifiedDiffParseErr, "failed to parse unified diff for file %s", diff.Path)
		}
		editCommands := editcommands.NewEditCommands(replacement.ParseEditCommandsFromDiff(unifiedDiff.Hunks))

		if _, ok := patchResults[pathForCodebaseAccess]; ok {
			return errors.Errorf("multiple diffs for the same file are not supported: %s", pathForCodebaseAccess)
		}

		switch {
		case unifiedDiff.From == "/dev/null":
			// New file - extract content directly from the diff hunks, because `editCommands.Apply`
			// fails on an empty content.
			// For new files, all lines in hunks should be additions
			// Note: Line.Content from the parser already includes the trailing \n
			var lines []string
			for _, hunk := range unifiedDiff.Hunks {
				for _, line := range hunk.Lines {
					if line.Kind != gotextdiff.Insert {
						return errors.Errorf("unexpected line kind in new file diff for file %s: %v", diff.Path, line.Kind)
					}
					// Content includes '\n', so strip it to store as lines
					content := strings.TrimSuffix(line.Content, "\n")
					lines = append(lines, content)
				}
			}
			// Join with newlines and add trailing newline (standard file format)
			content := strings.Join(lines, "\n")
			if content != "" {
				content += "\n"
			}
			patchResults[pathForCodebaseAccess] = &newFile{Content: content}
		case unifiedDiff.To == "/dev/null":
			// File deletion
			patchResults[pathForCodebaseAccess] = &deleteFile{}
		default:
			// File update - read existing content and apply edit commands
			content, codebaseReadErr := codebase.Read(pathForCodebaseAccess, nil)
			if codebaseReadErr != nil {
				return errors.Wrapf(codebaseReadErr, "failed to read contents of file %s", pathForCodebaseAccess)
			}
			patchResults[pathForCodebaseAccess] = &updateFile{Content: editCommands.Apply(content)}
		}
	}

	// Now write all patched contents back to the codebase.
	// If any write fails, we return an error and do not write any further files.
	// Note that this means some files may have been written already.
	// For now this is acceptable, because failing to apply a patch, should fail the validation attempt.
	for path, pathResult := range patchResults {
		switch r := pathResult.(type) {
		case *newFile:
			if writeErr := codebase.WriteContents(path, r.Content); writeErr != nil {
				return errors.Wrapf(writeErr, "failed to write new file %s", path)
			}
		case *deleteFile:
			// Handle deletion based on codebase type, because the `VirtualCodebase` doesn't support deletion.
			switch cb := codebase.(type) {
			case *_codebase.MemoryCodebase:
				// For memory codebases, verify file exists before deleting
				if _, exists := cb.Files[path]; !exists {
					return errors.Errorf("cannot delete non-existent file %s", path)
				}
				// Delete from the in-memory map
				delete(cb.Files, path)
			case *_codebase.LocalCodebase:
				// For local codebases, delete the file from disk
				fullPath := filepath.Join(cb.GetRoot(), path)
				if removeErr := os.Remove(fullPath); removeErr != nil {
					return errors.Wrapf(removeErr, "failed to delete file %s", path)
				}
			default:
				return errors.Errorf("deleting files is not supported for codebase type %T", codebase)
			}
		case *updateFile:
			if writeErr := codebase.WriteContents(path, r.Content); writeErr != nil {
				return errors.Wrapf(writeErr, "failed to write updated contents to file %s", path)
			}
		default:
			return errors.Errorf("unknown patch result type for file %s", path)
		}
	}

	return nil
}

// LanguageMap maps programming languages to their associated file paths.
type LanguageMap = map[autofix_utils.Language][]string

// SortLanguagesByFileCount sorts languages by number of files associated
func SortLanguagesByFileCount(languages LanguageMap) []autofix_utils.Language {
	var sortedLangs []autofix_utils.Language
	for lang := range languages {
		sortedLangs = append(sortedLangs, lang)
	}
	sort.Slice(sortedLangs, func(i, j int) bool {
		return len(languages[sortedLangs[i]]) > len(languages[sortedLangs[j]])
	})
	return sortedLangs
}

// GetLanguages returns a map of programming languages to their associated file paths in the fix.
func (f *Fix) GetLanguages() LanguageMap {
	languages := make(map[autofix_utils.Language][]string)
	for _, d := range f.Diffs {
		language := findLanguageFromPath(d.Path)
		languages[language] = append(languages[language], d.Path)
	}
	return languages
}

func findLanguageFromPath(path string) autofix_utils.Language {
	// Remove any leading directory components
	if i := strings.LastIndex(path, "/"); i != -1 {
		path = path[i+1:]
	}
	// Extract file extension
	ext := filepath.Ext(path)
	if ext == "" {
		return autofix_utils.LanguageUnknown
	}
	return autofix_utils.LanguageFromExtension(ext)
}
