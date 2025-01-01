package types

// ResolvedFile represents a file from a git repository.
type ResolvedFile struct {
	Path          string
	Text          string
	Ref           string
	SHA           string
	IsTruncated   bool
	RepositoryID  GlobalID
	RepositoryNwo string
}
