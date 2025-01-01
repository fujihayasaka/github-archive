package wfparser

import (
	"context"
	"fmt"
	"strings"

	parser "github.com/github/actions-workflow-parser/go"
	"github.com/github/actions-workflow-parser/go/template"
	"github.com/github/go-kvp"

	"github.com/github/launch/observability"
)

var _ parser.FileProvider = &fileProvider{}

type fileProvider struct {
	ctx   context.Context
	obs   *observability.Observability
	files []WorkflowReferencedFile
}

type WorkflowReferencedFile struct {
	Path          string
	Text          string
	Ref           string
	SHA           string
	RepositoryNwo string
	IsTrusted     bool
	IsRequired    bool
}

func NewFileProvider(ctx context.Context, obs *observability.Observability, files []WorkflowReferencedFile) parser.FileProvider {
	return &fileProvider{
		ctx:   ctx,
		obs:   obs,
		files: files,
	}
}

// GetFileContents returns the contents of the file at the given path.
func (f *fileProvider) GetFileContents(path string) (string, error) {
	file, err := f.findFile(path)
	if err != nil {
		return "", err
	}

	return file.Text, nil
}

// GetFileInfo returns the metadata of the file at the given path.
func (f *fileProvider) GetFileInfo(path string) (*parser.FileInfo, error) {
	file, err := f.findFile(path)
	if err != nil {
		return nil, err
	}

	return &parser.FileInfo{
		Path:        file.Path,
		NWO:         file.RepositoryNwo,
		ResolvedSHA: file.SHA,
		ResolvedRef: file.Ref,
		IsTrusted:   file.IsTrusted,
		IsRequired:  file.IsRequired,
	}, nil
}

func (f *fileProvider) findFile(path string) (WorkflowReferencedFile, error) {
	for _, file := range f.files {
		ok, err := pathMatchesFile(path, file)
		if err != nil {
			f.obs.Error(f.ctx, "error matching file", kvp.Err(err))
			continue
		}
		if ok {
			return file, nil
		}
	}

	var paths strings.Builder
	for _, f := range f.files {
		paths.WriteString(fmt.Sprintf("%s#(%s)%s:%s|", f.RepositoryNwo, f.Path, f.Ref, f.SHA))
	}

	f.obs.Error(f.ctx, "file provider did not match file", kvp.String("gh.launch.file_path", path), kvp.String("gh.launch.file_properties", paths.String()))

	return WorkflowReferencedFile{}, template.NewNotImplementedError("file provider did not match file")
}

func pathMatchesFile(path string, file WorkflowReferencedFile) (bool, error) {
	// If it starts with ./, it's a local file, just do a straight match
	if strings.HasPrefix(path, "./") {
		return file.Path == path, nil
	}

	// If the file.Path and path match already, we're done. This covers the majority of cases, including required workflows
	if file.Path == path {
		return true, nil
	}

	// Extract the NWO from the front, so we can compare it ignoring case
	splitPath := strings.SplitN(path, "/", 3)
	splitFilePath := strings.SplitN(file.Path, "/", 3)
	if len(splitPath) != 3 || len(splitFilePath) != 3 {
		return false, fmt.Errorf("path or match didn't contain 3 parts: %s, %s", path, file.Path)
	}

	// For the 0 (owner) and 1 (repo) parts, we want to compare ignoring case, otherwise we want to compare exactly
	return strings.EqualFold(splitPath[0], splitFilePath[0]) &&
			strings.EqualFold(splitPath[1], splitFilePath[1]) &&
			splitPath[2] == splitFilePath[2],
		nil

}
