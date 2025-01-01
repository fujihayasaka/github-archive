package dependencies

import (
	"context"

	"github.com/github/codeml-autofix/go/v2/pkg/autofix/fixdata"
)

// MockAdvisoryMetadataFetcher is a test implementation of IMetadataFetcher
// that allows tests to register advisory metadata for specific dependencies.
// It can mark dependencies as malicious by attaching advisories.
type MockAdvisoryMetadataFetcher struct {
	ecoSystem  string
	advisories map[string]fixdata.Advisory
}

var _ IMetadataFetcher = &MockAdvisoryMetadataFetcher{}

// NewMockAdvisoryMetadataFetcher creates a new mock metadata fetcher for the
// given ecosystem.
func NewMockAdvisoryMetadataFetcher(ecoSystem string) MockAdvisoryMetadataFetcher {
	return MockAdvisoryMetadataFetcher{
		ecoSystem:  ecoSystem,
		advisories: make(map[string]fixdata.Advisory),
	}
}

// AddAdvisory registers a fake advisory for a dependency with the provided
// severity (also marking the dependency as malicious in metadata results).
func (m *MockAdvisoryMetadataFetcher) AddAdvisory(depName string, severity string) {
	m.advisories[depName] = fixdata.Advisory{
		Id:          "CVE-2023-1234",
		HtmlUrl:     "https://example.com/advisory",
		Summary:     "Dependency vulnerability summary",
		Description: "Dependency vulnerability description",
		Severity:    severity,
	}
}

// GetMetadata returns mock dependency metadata enriched with any registered
// advisory for that dependency. Implements IMetadataFetcher.
func (m MockAdvisoryMetadataFetcher) GetMetadata(
	ctx context.Context, dependency string, latest bool) (fixdata.DependencyMetadata, error) {
	var version string
	if m.ecoSystem == "go" {
		version = "v1.2.3"
	} else {
		version = "1.2.3"
	}

	ret := fixdata.DependencyMetadata{
		Ecosystem:   m.ecoSystem,
		Version:     version,
		Advisories:  []fixdata.Advisory{},
		Url:         "some-url/" + dependency,
		Description: "Dependency description",
		Name:        dependency,
		IsMalicious: false,
	}
	if advisory, ok := m.advisories[dependency]; ok {
		ret.Advisories = append(ret.Advisories, advisory)
		ret.IsMalicious = true
	}
	return ret, nil
}
