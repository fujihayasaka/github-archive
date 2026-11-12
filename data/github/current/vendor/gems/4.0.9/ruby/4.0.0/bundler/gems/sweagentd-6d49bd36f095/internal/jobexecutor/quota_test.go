package jobexecutor

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestInsufficientQuotaMessage(t *testing.T) {
	tests := []struct {
		name              string
		totalQuota        int32
		tokenBasedBilling bool
		wantContains      []string
		wantNotContains   []string
	}{
		{
			name:              "premium requests message",
			totalQuota:        10,
			tokenBasedBilling: false,
			wantContains: []string{
				"used up the 10 premium requests allowance",
				"Learn more about managing premium request limits https://gh.io/manage-premrequests.",
			},
			wantNotContains: []string{
				"AI credits",
				"Manage your AI credit budget at https://github.com/settings/copilot/features.",
			},
		},
		{
			name:              "token-based billing message",
			totalQuota:        10,
			tokenBasedBilling: true,
			wantContains: []string{
				"used up the 10 AI credits allowance",
				"Manage your AI credit budget at https://github.com/settings/copilot/features.",
			},
			wantNotContains: []string{
				"premium requests allowance",
				"https://gh.io/manage-premrequests.",
			},
		},
		{
			name:              "omits quota amount when total is zero",
			totalQuota:        0,
			tokenBasedBilling: false,
			wantContains: []string{
				"used up the premium requests allowance",
			},
			wantNotContains: []string{
				"used up the 0 premium requests allowance",
			},
		},
	}

	executor := &AgentJobExecutor{}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			message := executor.insufficientQuotaMessage(tt.totalQuota, tt.tokenBasedBilling)

			for _, want := range tt.wantContains {
				assert.Contains(t, message, want)
			}

			for _, want := range tt.wantNotContains {
				assert.NotContains(t, message, want)
			}
		})
	}
}

func TestCustomerNotSelectedMessage(t *testing.T) {
	executor := &AgentJobExecutor{}

	assert.Equal(
		t,
		"Before you can use Copilot cloud agent, you need to pick a \"Usage billed to\" option in your Copilot settings. Update your settings at https://github.com/settings/copilot/features, then try again.",
		executor.customerNotSelectedMessage(),
	)
}

func TestInsufficientQuotaMessage_FullMessageWithoutTBB(t *testing.T) {
	executor := &AgentJobExecutor{}

	assert.Equal(
		t,
		"Your session could not start because you've used up the 10 premium requests allowance included in your Copilot subscription this month, and your subscription does not allow additional paid usage. To retry, just leave a comment on this pull request asking me to try again. Learn more about managing premium request limits https://gh.io/manage-premrequests.",
		executor.insufficientQuotaMessage(10, false),
	)
}

func TestInsufficientQuotaMessage_FullMessageWithTBB(t *testing.T) {
	executor := &AgentJobExecutor{}

	assert.Equal(
		t,
		"Your session could not start because you've used up the 10 AI credits allowance included in your Copilot subscription this month, and your subscription does not allow additional paid usage. To retry, just leave a comment on this pull request asking me to try again. Manage your AI credit budget at https://github.com/settings/copilot/features.",
		executor.insufficientQuotaMessage(10, true),
	)
}
