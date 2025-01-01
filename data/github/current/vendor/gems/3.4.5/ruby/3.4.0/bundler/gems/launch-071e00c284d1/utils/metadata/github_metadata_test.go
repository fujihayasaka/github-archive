package metadata

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestGitHubMetadata(t *testing.T) {
	var md githubMetadata

	err := readMetadataFromFile(&md, "testdata/good.json")
	require.NoError(t, err, "read good.json")
	if assert.NotNil(t, md, "good.json's data") {
		assert.Equal(t, "the-site", md.Site)
	}

	err = readMetadataFromFile(&md, "testdata/nosuchfile")
	assert.Error(t, err, "no metadata")
}
