package attestation

import (
	_ "embed"
	"fmt"

	"github.com/sigstore/sigstore-go/pkg/tuf"
)

//go:embed embed/tuf-repo-cdn.sigstore.dev/root.json
var publicGoodTUFRoot []byte

//go:embed embed/tuf-repo.github.com/root.json
var githubTUFRoot []byte

//go:embed embed/github.github.com-staging-tuf-root/root.json
var githubStagingTUFRoot []byte

func tufClient(tufRootAnchor []byte, baseURL, tufDir string) (*tuf.Client, error) {
	opts := &tuf.Options{
		CachePath:         tufDir,
		RepositoryBaseURL: baseURL,
		Root:              tufRootAnchor,
	}

	client, err := tuf.New(opts)
	if err != nil {
		return nil, fmt.Errorf("failed to create TUF client for %s: %w", baseURL, err)
	}

	return client, nil
}

func publicGoodTUFClient(tufDir string) (*tuf.Client, error) {
	return tufClient(publicGoodTUFRoot, "https://tuf-repo-cdn.sigstore.dev", tufDir)
}

func githubTUFClient(tufDir, mirror string) (*tuf.Client, error) {
	var rb []byte

	switch mirror {
	case "https://tuf-repo.github.com":
		rb = githubTUFRoot
	case "https://github.github.com/staging-tuf-root":
		rb = githubStagingTUFRoot
	default:
		return nil, fmt.Errorf("unknown TUF mirror %s", mirror)
	}

	return tufClient(rb, mirror, tufDir)
}
