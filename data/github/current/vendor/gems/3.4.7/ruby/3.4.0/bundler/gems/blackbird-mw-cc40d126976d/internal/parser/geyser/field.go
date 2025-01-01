package geyser

// Field is used in queries to indicate the field to search on. In general, fields correspond closely to the representation
// of fields in Elasticsearch as opposed to the qualifiers in the GitHub syntax.
type Field string

// This is the list of expected fields
const (
	Unspecified        = ""
	Content      Field = "content"
	Path         Field = "path"
	PathSplit    Field = "path.split" // tokenized by splitting the path on slashes
	RepositoryID Field = "repository_id"
	Repository   Field = "repository"
	LanguageID   Field = "language_id"
	Language     Field = "language"

	SizeField  Field = "size"
	OwnerID    Field = "owner_id"
	Owner      Field = "owner"
	Fork       Field = "fork"
	Filename   Field = "filename"
	Extension  Field = "extension"
	Visibility Field = "visibility"

	// IsRootFile doesn't correspond to a field in Elasticsearch. Eventually it would be nice to actually implement
	// this field and to index the `path` field with the full path including the filename so that people could search.
	IsRootFile Field = "is_root_file"
)
