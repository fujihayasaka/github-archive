package model

import (
	"errors"
	"fmt"
	"regexp"
	"strings"

	"github.com/github/launch/types"
)

const LocalWorkflowPathPrefix = "./.github/workflows"

type WorkflowRef struct {
	Owner   string
	Repo    string
	Path    string
	Version VersionRef
}

func ParseWorkflowRef(input string) (*WorkflowRef, error) {
	parts := strings.Split(input, "@")
	var (
		version *VersionRef
		err     error
	)
	switch len(parts) {
	case 0:
		return nil, errors.New("empty input")
	case 1:
		// if the path starts with a dot, refers to local workflow and the version can be omitted
		// note that we should check for workflows and workflows-lab both
		if !strings.HasPrefix(parts[0], LocalWorkflowPathPrefix) {
			return nil, errors.New("no version specified")
		}
	case 2:
		// if the version is specified, it should not have nwo
		// note that this behavior is consistent with GitHub action
		if strings.HasPrefix(parts[0], LocalWorkflowPathPrefix) {
			return nil, fmt.Errorf("cannot specify version when calling local workflows")
		}
		version, err = parseVersionRef(parts[1])
	default:
		return nil, errors.New("too many '@' in workflow reference")
	}
	if err != nil {
		return nil, err
	}

	pathIdx := strings.Index(parts[0], ".github/workflows")
	if pathIdx < 0 {
		return nil, errors.New("references to workflows must be rooted in '.github/workflows'")
	}
	nwoPart := parts[0][:pathIdx]
	path := parts[0][pathIdx:]

	// expect ".github", "workflows", "foo.yml", disallow any subdirectories.
	if err := ValidateWorkflowPath(path); err != nil {
		return nil, err
	}

	// includes the last "" from the 2nd `/` in `owner/repo/`
	// note: dot nwo means the local repo
	if nwoPart != "./" && len(strings.Split(nwoPart, "/")) != 3 {
		return nil, errors.New("references to workflows must be prefixed with format 'owner/repository/' or './' for local workflows")
	}
	// removes the last "/" from `owner/repo/`
	nwoPart = strings.TrimSuffix(nwoPart, "/")
	nwo, err := types.ParseNWO(nwoPart)
	if err != nil {
		return nil, err
	}
	if err := ValidateNWO(nwo); err != nil {
		return nil, err
	}

	if version == nil {
		version = &VersionRef{}
	}

	return &WorkflowRef{
		Owner:   nwo.Owner,
		Repo:    nwo.Name,
		Path:    path,
		Version: *version,
	}, nil
}

func (ref WorkflowRef) GetNWO() types.RepositoryFullName {
	return types.RepositoryFullName{
		Owner: ref.Owner,
		Name:  ref.Repo,
	}
}

func (ref WorkflowRef) IsDotNWO() bool {
	return ref.GetNWO().IsDotRepo()
}

func (ref WorkflowRef) IsFullyQualified() bool {
	return ref.Owner != "" && ref.Repo != ""
}

func (ref WorkflowRef) String() string {
	repoFullName := ref.GetNWO()
	pathWithRef := ref.Path

	if ref.Version.String() != "" {
		pathWithRef = pathWithRef + "@" + ref.Version.String()
	}

	if !repoFullName.IsBlank() {
		// Note: avoid using path.Join() because it will remove ./ in case of DotRepository(local repo)
		return repoFullName.String() + "/" + pathWithRef
	}

	return pathWithRef
}

type VersionRef struct {
	// oneof:
	GitRef *string
}

func (vr VersionRef) String() string {
	if vr.GitRef != nil {
		return *vr.GitRef
	}
	return ""
}

func parseVersionRef(refname string) (*VersionRef, error) {
	err := ValidateRefName(refname)
	if err != nil {
		return nil, err
	}

	return &VersionRef{GitRef: &refname}, nil
}

// validateRefName returns true if the refname is a valid ref
// note that refname is the text after the 'refs/(heads|tags)/' prefix
// See https://git-scm.com/docs/git-check-ref-format for ref validation rule
func ValidateRefName(refname string) error {
	if len(refname) == 0 {
		return errors.New("no version specified")
	}

	// cannot be the single character '@'
	if refname == "@" {
		return errors.New("version cannot be the single character '@'")
	}

	// cannot have '?', '*', '[', ']', '\',  '~', '^', or ':' in the refname
	invalidSequence := []string{
		"?", "*", "[", "]", "\\", "~", "^", ":", "@{", "..", "//",
	}
	for _, s := range invalidSequence {
		if strings.Contains(refname, s) {
			return fmt.Errorf("invalid character '%s' in version :%s", s, refname)
		}
	}

	// cannot begin or end with a slash '/' or a dot '.'
	if strings.HasPrefix(refname, "/") || strings.HasSuffix(refname, "/") || strings.HasPrefix(refname, ".") || strings.HasSuffix(refname, ".") {
		return fmt.Errorf("version cannot begin or end with a slash '/' or a dot '.'")
	}

	// no slash-separated component can begin with a dot '.' or end with the sequence '.lock'
	components := strings.Split(refname, "/")
	for _, component := range components {
		if strings.HasPrefix(component, ".") || strings.HasSuffix(component, ".lock") {
			return fmt.Errorf("invalid version: %s", refname)
		}
	}

	// no ascii control characters (bytes whose values are lower than \040, or \177 DEL) or whitespace
	asciiRegex := regexp.MustCompile(`[[:cntrl:]]`)
	if asciiRegex.MatchString(refname) {
		return fmt.Errorf("version cannot have ASCII control characters: %s", refname)
	}

	spaceRegex := regexp.MustCompile(`[[:space:]]`)
	if spaceRegex.MatchString(refname) {
		return fmt.Errorf("version cannot have whitespace: %s", refname)
	}

	return nil
}

func ValidateWorkflowPath(path string) error {
	if len(path) == 0 {
		return fmt.Errorf("no workflow path specified")
	}

	pathParts := strings.Split(path, "/")
	workflowsRegex := regexp.MustCompile(`\Aworkflows(-lab)?\z`)
	if len(pathParts) != 3 || pathParts[0] != ".github" || !workflowsRegex.MatchString(pathParts[1]) {
		return errors.New("workflows must be defined at the top level of the .github/workflows/ directory")
	}

	filePart := pathParts[2]
	if !strings.HasSuffix(filePart, ".yml") && !strings.HasSuffix(filePart, ".yaml") {
		return errors.New("workflow file should have either a '.yml' or '.yaml' file extension")
	}

	if filePart == ".yml" || filePart == ".yaml" {
		return errors.New("invalid workflow file name")
	}

	return nil
}

func ValidateNWO(nwo types.RepositoryFullName) error {
	// user login regex can be more restrictive, but this is a reasonable
	// see https://github.com/github/github/blob/3e9210bfab31156a85ff68d871ecdedea7f88342/app/models/user.rb#L40-L59
	ownerRegex := regexp.MustCompile(`\A[\w\.\-]+\z`)
	if !ownerRegex.MatchString(nwo.Owner) {
		return errors.New("owner name must be a valid repository owner name")
	}

	// repository name can have \w, \- and \.
	// see https://github.com/github/github/blob/05052fa7736b57f8a9d8b11eb4c047b5f3d46bc2/app/models/entity_name.rb
	repoRegex := regexp.MustCompile(`\A[\w\.\-]+\z`)
	if !repoRegex.MatchString(nwo.Name) {
		return errors.New("repository name is invalid")
	}

	return nil
}
