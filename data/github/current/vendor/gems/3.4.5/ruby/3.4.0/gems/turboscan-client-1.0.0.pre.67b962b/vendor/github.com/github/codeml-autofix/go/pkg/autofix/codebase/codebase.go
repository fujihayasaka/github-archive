package codebase

import (
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"reflect"
	"strings"

	"github.com/github/codeml-autofix/go/pkg/autofix"
	"github.com/github/codeml-autofix/go/pkg/autofix/sarif/v210autofix"
)

/*
VirtualCodebase is an abstract representation of a codebase, either checked out locally or
accessed remotely via the GitHub API.
*/
type VirtualCodebase interface {
	// A short but human-readable description of the root of this codebase.
	GetRoot() string

	// Read the contents of a file in this codebase.
	ReadContents(path string) (string, error)

	// Write the contents of a file in this codebase.
	WriteContents(path string, contents string) error

	// Find all files in this codebase that match all the given globs.
	FindFiles(globs []string) ([]string, error)

	// Check whether this codebase is equal to another codebase.
	Equals(that VirtualCodebase) bool

	// Gets a file in this codebase given its URI (either a file:// URL or a path).
	// Throws an exception if the file is outside the codebase. For some codebases,
	// it may also throw an exception if the file does not exist.
	GetFile(uri string) (File, error)

	// Reads a region of characters from a file in this codebase.
	// The region can either be a LineRegion or a Region.
	// If the region is nil, the entire file is read.
	Read(path string, region RegionReader) (string, error)

	// Gets a hash key for this codebase.
	Hash() string
}

// LocalCodebase represents a codebase that is checked out locally and
// implements the VirtualCodebase interface.
type LocalCodebase struct {
	Root string
}

// NewLocalCheckout creates a new LocalCheckout instance.
func NewLocalCodebase(root string) (LocalCodebase, autofix.AutofixError) {
	cleanRoot := filepath.Clean(root)
	realRoot, err := filepath.EvalSymlinks(cleanRoot)
	if err != nil {
		return LocalCodebase{}, autofix.LogicError{Err: fmt.Errorf("failed to evaluate symlinks for root: %w", err)}
	}
	realRoot, err = filepath.Abs(realRoot)
	if err != nil {
		return LocalCodebase{}, autofix.LogicError{Err: fmt.Errorf("failed to get absolute path for root: %w", err)}
	}
	return LocalCodebase{Root: realRoot}, nil
}

// GetRoot returns the root of the codebase.
func (lc LocalCodebase) GetRoot() string {
	return lc.Root
}

// ReadContents reads the overall contents of a file in the codebase
func (lc LocalCodebase) ReadContents(pth string) (string, error) {
	fullPath := filepath.Join(lc.Root, pth)
	data, err := os.ReadFile(fullPath)
	if err != nil {
		return "", err
	}
	return string(data), nil
}

const (
	dirPermissions  = 0o700
	filePermissions = 0o600
)

// WriteContents writes the contents of a file in the codebase
func (lc LocalCodebase) WriteContents(pth, contents string) error {
	fullPath := filepath.Join(lc.Root, pth)
	err := os.MkdirAll(filepath.Dir(fullPath), dirPermissions) // Use 0700 permissions for directories
	if err != nil {
		return err
	}
	return os.WriteFile(fullPath, []byte(contents), filePermissions) // Use 0600 permissions for files
}

// FindFiles finds all files in the codebase that match the given globs.
func (lc LocalCodebase) FindFiles(globs []string) ([]string, error) {
	var results []string

	for _, glob := range globs {
		matches, err := filepath.Glob(filepath.Join(lc.Root, glob))
		if err != nil {
			// The only possible error for Glob is ErrBadPattern, which we should surface
			// up to the caller.
			return nil, err
		}

		results = append(results, matches...)
	}

	return results, nil
}

func (lc LocalCodebase) ReadLines(path string, startLine LineNumber, endLine LineNumber) ([]string, error) {
	content, err := lc.ReadContents(path)
	if err != nil {
		return nil, err
	}
	return readLines(content, startLine, endLine), nil
}

// Equals finds all files in the codebase that match the given globs.
func (lc LocalCodebase) Equals(that VirtualCodebase) bool {
	if other, ok := that.(LocalCodebase); ok {
		return lc.Root == other.Root
	}
	return false
}

/*
GetFile gets a file in this codebase given its URI (either a file:// URL or a path).
Throws an exception if the file is outside the codebase. For some codebases,
it may also throw an exception if the file does not exist.
*/
func (lc LocalCodebase) GetFile(uri string) (File, error) {

	// Try to parse the URI as a URL
	parsedURL, err := url.Parse(uri)
	if err == nil && parsedURL.Scheme == "file" {
		uri = parsedURL.Path
	} else {
		// If the URI is not a valid URL, assume it is a file path
		uri = strings.TrimPrefix(uri, "file://")
		uri = strings.TrimPrefix(uri, "file:")
	}

	var fullPath string
	if filepath.IsAbs(uri) {
		fullPath = filepath.Clean(uri)
	} else {
		fullPath = filepath.Join(lc.Root, uri)
		fullPath = filepath.Clean(fullPath)
	}

	// Verify that the path is within the root of the codebase
	realPath, err := filepath.EvalSymlinks(fullPath)
	if err != nil {
		return File{}, err
	}
	if !strings.HasPrefix(realPath, lc.Root) {
		return File{}, fmt.Errorf("file %s is not inside %s", realPath, lc.Root)
	}

	// Compute relative path
	relativePath, err := filepath.Rel(lc.Root, realPath)
	if err != nil {
		return File{}, fmt.Errorf("failed to get relative path: %v", err)
	}

	return File{Codebase: lc, Path: relativePath}, nil
}

// Read reads a region of characters from a file in this codebase.
func (lc LocalCodebase) Read(path string, region RegionReader) (string, error) {
	content, err := lc.ReadContents(path)
	if err != nil {
		return "", err
	}
	if region == nil {
		return content, nil
	}

	return region.read(content), nil
}

func (lc LocalCodebase) Hash() string {
	return reflect.TypeOf(lc).String() + ":" + lc.Root
}

// SarifArtifactsAsCodebase represents a codebase backed by the artifact contents in a SARIF file and
// implements the Codebase interface.
type SarifArtifactsAsCodebase struct {
	SarifFileName    string
	SarifLog         v210autofix.SarifLog
	artifactContents map[string]v210autofix.ArtifactContent
}

func NewSarifArtifactsAsCodebase(sarifFileName string, sarifLog v210autofix.SarifLog) *SarifArtifactsAsCodebase {
	artifactContents := make(map[string]v210autofix.ArtifactContent)

	for _, run := range sarifLog.Runs {
		for _, artifact := range run.Artifacts {
			if artifact.Location != nil && artifact.Location.Uri != "" && artifact.Contents != nil && artifact.Contents.Text != "" {
				artifactContents[artifact.Location.Uri] = *artifact.Contents
			}
		}
	}

	return &SarifArtifactsAsCodebase{SarifFileName: sarifFileName, SarifLog: sarifLog, artifactContents: artifactContents}
}

func (sa SarifArtifactsAsCodebase) GetRoot() string {
	return sa.SarifFileName
}

func (sa SarifArtifactsAsCodebase) ReadContents(path string) (string, error) {
	artifact, ok := sa.artifactContents[path]
	if !ok {
		return "", fmt.Errorf("unable to read %s from %s", path, sa.SarifFileName)
	}
	return artifact.Text, nil
}

func (sa SarifArtifactsAsCodebase) WriteContents(path string, contents string) error {
	return fmt.Errorf("writing to SARIF files is not supported")
}

func (sa SarifArtifactsAsCodebase) FindFiles(globs []string) ([]string, error) {
	return nil, errors.New("FindFiles is not implemented for SarifArtifactsAsCodebase")
}

func (sa SarifArtifactsAsCodebase) Equals(that VirtualCodebase) bool {
	if other, ok := that.(SarifArtifactsAsCodebase); ok {
		return sa.SarifFileName == other.SarifFileName && sa.SarifLog.Equals(other.SarifLog)
	}
	return false
}

func (sa SarifArtifactsAsCodebase) ReadLines(path string, startLine LineNumber, endLine LineNumber) ([]string, error) {
	content, err := sa.ReadContents(path)
	if err != nil {
		return nil, err
	}
	return readLines(content, startLine, endLine), nil
}

func (sa SarifArtifactsAsCodebase) GetFile(uriOrPath string) (File, error) {
	return File{Codebase: sa, Path: uriOrPath}, nil

}

func (sa SarifArtifactsAsCodebase) Read(path string, region RegionReader) (string, error) {
	content, err := sa.ReadContents(path)
	if err != nil {
		return "", err
	}
	if region == nil {
		return content, nil
	}

	return region.read(content), nil
}

func (sa SarifArtifactsAsCodebase) Hash() string {
	return reflect.TypeOf(sa).String() + ":" + sa.SarifFileName
}
