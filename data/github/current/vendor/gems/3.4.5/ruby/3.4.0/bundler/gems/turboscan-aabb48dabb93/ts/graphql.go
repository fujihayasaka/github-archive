package ts

// GlobalRelayID is the generic type for GraphQL global ID's
// See https://thehub.github.com/epd/engineering/dev-practicals/secure-coding/secure-coding-dotcom/graphql/#global-relay-ids
// Some external systems require those ids (rather than DB IDs) to identify components.
type GlobalRelayID string

type RepositoryGRID GlobalRelayID

type ActorGRID GlobalRelayID
