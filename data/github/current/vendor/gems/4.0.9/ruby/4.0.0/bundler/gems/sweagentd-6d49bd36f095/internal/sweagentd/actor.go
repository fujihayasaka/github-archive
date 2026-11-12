package sweagentd

// Actor represents a GitHub actor (typically a user or bot) with a method to access the actor ID.
type Actor interface {
	GetActorID() int64
}

// ActorWithRepository extends Actor to include a method for accessing the repository ID.
type ActorWithRepository interface {
	Actor
	GetRepositoryID() int64
}

// ActorLogin provides a method to access the actor's login name.
type ActorLogin interface {
	GetLogin() string
}

// ActorWithLogin combines the Actor and ActorLogin interfaces.
type ActorWithLogin interface {
	Actor
	ActorLogin
}
