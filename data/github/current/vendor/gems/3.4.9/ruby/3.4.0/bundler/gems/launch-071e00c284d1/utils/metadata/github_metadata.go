package metadata

import (
	"encoding/json"
	"errors"
	"os"

	"github.com/github/go-kvp"

	"github.com/github/launch/observability/kvperrors"
)

var md githubMetadata

// Init reads /etc/github/metadata.json and reports an error if it can't, or if any of the data is missing.
func Init() error {
	if site, ok := os.LookupEnv("GITHUB_SITE"); ok {
		md.Site = site
		return nil
	}

	err := readMetadataFromFile(&md, "/etc/github/metadata.json")
	if err != nil {
		return err
	}

	if len(md.Site) < 1 {
		return errors.New("missing 'site' from /etc/github/metadata.json")
	}

	return nil
}

// GetSite returns the site initialized by Init().
func GetSite() string {
	return md.Site
}

// githubMetadata is a Go version of the fields that we need from /etc/github/metadata.json.
type githubMetadata struct {
	Site string
}

// #nosec - metadatapath seems injectable, but in practice is only called with a constant
func readMetadataFromFile(md *githubMetadata, metadatapath string) error {
	f, err := os.Open(metadatapath)
	if err != nil {
		return kvperrors.WrapWith(err, kvp.String("metadatapath", metadatapath))
	}
	defer f.Close() // nolint: errcheck

	err = json.NewDecoder(f).Decode(md)
	if err != nil {
		return kvperrors.WrapWith(err, kvp.String("metadatapath", metadatapath))
	}

	return nil
}
