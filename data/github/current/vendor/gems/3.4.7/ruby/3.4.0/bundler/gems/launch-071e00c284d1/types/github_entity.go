package types

type GitHubEntity struct {
	// The type of the entity - this may not map directly to the GitHub model's type, see toModelClassName()
	// This will match the GraphQL type of an entity, see https://docs.github.com/en/graphql/reference/objects
	// In `github/github`, this is determined by `platform_type_name` and defaults to the model's class name
	// See `GitHub::Relay::TypeName` - https://github.com/github/github/blob/master/lib/github/relay.rb
	// Example: The `Business` model that represents an enterprise account will have a type of `Enterprise`
	Type string
	// The database ID of the entity
	ID int64
}

func NewGitHubEntity(globalID GlobalID) (GitHubEntity, error) {
	entityType, id, err := globalID.Decode()
	if err != nil {
		return GitHubEntity{}, err
	}

	return GitHubEntity{
		Type: entityType,
		ID:   id,
	}, nil
}
