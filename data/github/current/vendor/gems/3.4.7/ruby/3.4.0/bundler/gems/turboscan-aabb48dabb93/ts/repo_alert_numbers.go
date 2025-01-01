package ts

// RepoAlertNumbers is a struct that allows grouping of alerts for a repository
// and ref.
type RepoAlertNumbers struct {
	RepositoryID  RepositoryEID
	AlertNumbers  []uint32
	RefNamesBytes [][]byte
}
