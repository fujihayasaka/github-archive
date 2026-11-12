package githubtwirp

import (
	"context"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
)

type NoopUserDetailAPI struct {
	copilotUsersTwirp.CopilotUserDetailAPI
	MockGetCopilotUser func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error)
}

// Ensure NoopClient implements ClientInterface
var _ copilotUsersTwirp.CopilotUserDetailAPI = &NoopUserDetailAPI{}

func (n *NoopUserDetailAPI) GetCopilotUser(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
	return n.MockGetCopilotUser(ctx, req)
}
