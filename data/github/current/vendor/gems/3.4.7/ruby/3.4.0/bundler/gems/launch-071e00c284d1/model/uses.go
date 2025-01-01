package model

import (
	"errors"
	"fmt"
	"strings"
)

func ParseActionRef(strVal string) (Uses, error) {
	if strVal == "" {
		return &UsesInvalid{}, errors.New("`uses' value in action cannot be blank")
	}
	if strings.HasPrefix(strVal, "./") {
		return &UsesPath{Path: strings.TrimPrefix(strVal, "./")}, nil
	}

	if strings.HasPrefix(strVal, "docker://") {
		return &UsesDockerImage{Image: strings.TrimPrefix(strVal, "docker://")}, nil
	}

	tok := strings.Split(strVal, "@")
	if len(tok) != 2 {
		return &UsesInvalid{Raw: strVal}, errors.New("the `uses' attribute must be a path, a Docker image, or owner/repo@ref")
	}
	ref := tok[1]
	tok = strings.SplitN(tok[0], "/", 3)
	if len(tok) < 2 {
		return &UsesInvalid{Raw: strVal}, errors.New("the `uses' attribute must be a path, a Docker image, or owner/repo@ref")
	}
	usesRepo := UsesRepository{Repository: tok[0] + "/" + tok[1], Ref: ref}
	if len(tok) == 3 {
		usesRepo.Path = tok[2]
	}

	if strings.HasPrefix(usesRepo.Path, ".github/workflows/") {
		return &UsesInvalid{Raw: strVal}, errors.New("reusable workflows should be referenced at the top-level `jobs.*.uses' key, not within steps")
	}

	return &usesRepo, nil
}

type Uses interface {
	fmt.Stringer
	isUses()
}

// UsesDockerImage represents `uses = "docker://<image>"`
type UsesDockerImage struct {
	Image string
}

// UsesRepository represents `uses = "<owner>/<repo>[/<path>]@<ref>"`
type UsesRepository struct {
	Repository string
	Path       string
	Ref        string
}

// UsesPath represents `uses = "./<path>"`
type UsesPath struct {
	Path string
}

// UsesInvalid represents any invalid `uses = "<raw>"` value
type UsesInvalid struct {
	Raw string
}

func (u *UsesDockerImage) isUses() {}
func (u *UsesRepository) isUses()  {}
func (u *UsesPath) isUses()        {}
func (u *UsesInvalid) isUses()     {}

func (u *UsesDockerImage) String() string {
	return fmt.Sprintf("docker://%s", u.Image)
}

func (u *UsesRepository) String() string {
	if u.Path == "" {
		return fmt.Sprintf("%s@%s", u.Repository, u.Ref)
	}

	return fmt.Sprintf("%s/%s@%s", u.Repository, u.Path, u.Ref)
}

func (u *UsesPath) String() string {
	return fmt.Sprintf("./%s", u.Path)
}

func (u *UsesInvalid) String() string {
	return u.Raw
}
