package jobexecutor

import (
	"context"
	_ "embed"
	"fmt"

	"github.com/github/sweagentd/internal/githubtwirp"
)

func (e *AgentJobExecutor) insufficientQuotaMessage(totalQuota int32, tokenBasedBilling bool) string {
	quotaUnit := "premium requests "
	manageQuotaMessage := "Learn more about managing premium request limits https://gh.io/manage-premrequests."

	if tokenBasedBilling {
		quotaUnit = "AI credits "
		manageQuotaMessage = "Manage your AI credit budget at https://github.com/settings/copilot/features."
	}

	message := "Your session could not start because you've used up the "
	if totalQuota > 0 {
		message += fmt.Sprintf("%d ", totalQuota)
	}
	message += quotaUnit
	message += "allowance included in your Copilot subscription this month, "
	message += "and your subscription does not allow additional paid usage. "
	message += "To retry, just leave a comment on this pull request asking me to try again. "
	message += manageQuotaMessage
	return message
}

func (e *AgentJobExecutor) customerNotSelectedMessage() string {
	message := "Before you can use Copilot cloud agent, you need to pick a \"Usage billed to\" "
	message += "option in your Copilot settings. Update your settings at "
	message += "https://github.com/settings/copilot/features, then try again."
	return message
}

// GetQuotaStatus checks if the user has sufficient quota for launching agents.
func (e *AgentJobExecutor) GetQuotaStatus(ctx context.Context, ownerID, repoID, userID int64) (bool, int32, bool, error) {
	return githubtwirp.CheckPremiumQuota(ctx, e.ghTwirp, e.ffClient, e.obsv, ownerID, repoID, userID, false)
}
