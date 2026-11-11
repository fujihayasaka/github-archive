package jobexecutor

import (
	"context"
	_ "embed"
	"fmt"

	"github.com/github/sweagentd/internal/githubtwirp"
)

func (e *AgentJobExecutor) insufficientQuotaMessage(totalPremiumQuota int32) string {
	message := "Your session could not start because you've used up the "
	if totalPremiumQuota > 0 {
		message += fmt.Sprintf("%d ", totalPremiumQuota)
	}
	message += "premium requests allowance included in your Copilot subscription this month, "
	message += "and your subscription does not allow additional paid usage. "
	message += "To retry, just leave a comment on this pull request asking me to try again. "
	message += "Learn more about managing premium request limits https://gh.io/manage-premrequests."
	return message
}

func (e *AgentJobExecutor) customerNotSelectedMessage() string {
	message := "Before you can use Copilot coding agent, you need to pick a \"Usage billed to\" "
	message += "option in your Copilot settings. Update your settings at "
	message += "https://github.com/settings/copilot/features, then try again."
	return message
}

func (e *AgentJobExecutor) GetPremiumQuotaStatus(ctx context.Context, ownerID, repoID, userID int64) (bool, int32, error) {
	return githubtwirp.CheckPremiumQuota(ctx, e.ghTwirp, e.ffClient, e.obsv, ownerID, repoID, userID)
}
