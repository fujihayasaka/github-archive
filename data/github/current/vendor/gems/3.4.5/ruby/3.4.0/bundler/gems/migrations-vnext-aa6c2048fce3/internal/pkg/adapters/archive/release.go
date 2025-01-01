package archive

import (
	"fmt"
	"time"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

// Release represents a release in a GitHub repository.
type Release struct {
	Type            string          `json:"type"`
	URL             string          `json:"url"`
	Repository      string          `json:"repository"`
	User            string          `json:"user"`
	Name            string          `json:"name"`
	TagName         string          `json:"tag_name"`
	Body            string          `json:"body"`
	State           string          `json:"state"`
	PendingTag      string          `json:"pending_tag"`
	PreRelease      bool            `json:"prerelease"`
	TargetCommitish string          `json:"target_commitish"`
	Reactions       Reactions       `json:"reactions"`
	PublishedAt     time.Time       `json:"published_at"`
	CreatedAt       time.Time       `json:"created_at"`
	ReleaseAssets   []*ReleaseAsset `json:"release_assets,omitempty"`
}

// ReleaseAsset represents a release asset in a GitHub release.
type ReleaseAsset struct {
	User        string `json:"user"`
	Name        string `json:"name"`
	ContentType string `json:"content_type"`
	Size        int    `json:"size"`
	GUID        string `json:"guid"`
	State       string `json:"state"`
	Label       string `json:"label"`
	AssetURL    string `json:"asset_url"`
}

// ToV1Release converts a release to a v1.Release.
func (r *Release) ToV1Release() (*v1.Release, error) {
	if r.State != "published" && r.State != "draft" {
		return nil, fmt.Errorf("invalid release state: %s", r.State)
	}

	return &v1.Release{
		ResourceId:           r.URL,
		RepositoryResourceId: r.Repository,
		UserResourceId:       r.User,
		Name:                 r.Name,
		TagName:              r.TagName,
		Body:                 r.Body,
		State:                r.State,
		PendingTag:           r.PendingTag,
		IsPreRelease:         r.PreRelease,
		TargetCommitish:      r.TargetCommitish,
		PublishedAt:          toTimestamp(r.PublishedAt),
		CreatedAt:            toTimestamp(r.CreatedAt),
	}, nil
}

// ToV1ReleaseAssets converts a release to a slice of v1.ReleaseAssets.
func (r *Release) extractReleaseAssets() []*v1.ReleaseAsset {
	assets := []*v1.ReleaseAsset{}
	for _, a := range r.ReleaseAssets {
		assets = append(assets, &v1.ReleaseAsset{
			ResourceId:           a.GUID,
			RepositoryResourceId: r.Repository,
			FileName:             a.Name,
			ReleaseResourceId:    r.URL,
			UserResourceId:       a.User,
			ContentType:          a.ContentType,
			Size:                 int64(a.Size),
		})
	}
	return assets
}
