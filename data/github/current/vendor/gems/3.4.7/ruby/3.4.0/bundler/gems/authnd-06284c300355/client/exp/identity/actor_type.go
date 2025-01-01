package identity

import "fmt"

type ActorType string

var (
	// Acting as a User
	// Authenticated through a session, ssh public key, PAT, or oauth access token
	ActorTypeUser ActorType = "User"

	// Acting as an installation of an integration
	// Authenticated through a server-to-server token
	ActorTypeBot ActorType = "Bot"

	// Acting directly as an integration
	// Authenticated via JWT
	ActorTypeIntegration ActorType = "Integration"

	// Acting directly as an oauth application
	// Authenticated by client_id and client_secret
	ActorTypeOauthApplication ActorType = "OauthApplication"

	// Acting as a repository
	// Authenticated via deploy key (ssh key scoped to a repository)
	ActorTypeRepository ActorType = "Repository"
)

func ParseActorType(actorType string) (ActorType, error) {
	switch actorType {
	case "User":
		return ActorTypeUser, nil
	case "Bot":
		return ActorTypeBot, nil
	case "Integration":
		return ActorTypeIntegration, nil
	case "OauthApplication":
		return ActorTypeOauthApplication, nil
	case "Repository":
		return ActorTypeRepository, nil
	default:
		return "", fmt.Errorf("unknown actor type: %s", actorType)
	}
}
