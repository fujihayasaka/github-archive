package models

// The owner of a repository (a user or organization) which we can derive from
// data in the blackbird_repositories table or fetch via a snapshot search.
type Owner struct {
	OwnerID     uint32 `db:"owner_id"`
	OwnerLogin  string `db:"owner_login"`
	IsProtected bool   `db:"is_protected"`
}
