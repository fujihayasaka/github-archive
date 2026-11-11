package manifests

// RelatedManifests groups the manifests within a git changeset.
type RelatedManifests struct {
	// each sub-array of ManifestChange entries is a single batch
	// of related manifests that should be ingested together
	ToUpdate [][]ManifestChange

	// ungrouped ManifestChange entries to be
	// fanned out as individual deletion jobs
	ToDelete []ManifestChange
}

// metadata about one manifest file change identified and extracted
// from a Git changeset or full repo/ecosystem file enumeration
type ManifestChange struct {
	FileInfo Info
	BlobOID  string
	Type     ChangeType
}

type ChangeType uint8

const (
	ChangeUnknown ChangeType = iota
	ChangeAdded
	ChangeModified
	ChangeDeleted
)

func (ct ChangeType) String() string {
	switch ct {
	case ChangeAdded:
		return "added"
	case ChangeModified:
		return "modified"
	case ChangeDeleted:
		return "deleted"
	default:
		return "unknown"
	}
}
