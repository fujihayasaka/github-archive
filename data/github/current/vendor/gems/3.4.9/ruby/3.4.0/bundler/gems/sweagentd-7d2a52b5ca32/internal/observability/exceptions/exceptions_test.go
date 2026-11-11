package exceptions

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"path/filepath"
	"testing"

	mockexporter "github.com/github/go-exceptions/exporters/mock"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

func TestRedactSensitiveInfo(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		// Test owner and name endpoint format
		{
			name:     "Redact URL with owner and repo",
			input:    "I'm an error: https://api.github.com/repos/owner/repo and more text",
			expected: "I'm an error: https://api.github.com/repos/:owner/:repo and more text",
		},
		{
			name:     "Redact URL with owner and repo and sub-paths",
			input:    "I'm an error: https://api.github.com/repos/example-owner/example-repo/git/refs and more text",
			expected: "I'm an error: https://api.github.com/repos/:owner/:repo/git/refs and more text",
		},
		{
			name:     "Redact URL with owner, repo, and pull number",
			input:    "I'm an error: https://api.github.com/repos/owner/repo/pulls/123 and more text",
			expected: "I'm an error: https://api.github.com/repos/:owner/:repo/pulls/:number and more text",
		},
		{
			name:     "Redact URL with owner, repo, and issue number",
			input:    "I'm an error: https://api.github.com/repos/owner/repo/issues/456 and more text",
			expected: "I'm an error: https://api.github.com/repos/:owner/:repo/issues/:number and more text",
		},
		{
			name:     "Redact URL path with a branch name",
			input:    "I'm an error: https://api.github.com/repos/example-owner/example-repo/git/refs/heads/copilot/fix-31-2 and more text",
			expected: "I'm an error: https://api.github.com/repos/:owner/:repo/git/refs/heads/copilot/<branch> and more text",
		},
		{
			name:     "Redact URL with repo name containing periods",
			input:    "I'm an error: https://api.github.com/repos/foobar/foobar.AssetService.AssetService and more text",
			expected: "I'm an error: https://api.github.com/repos/:owner/:repo and more text",
		},
		{
			name:     "Redact URL with repo name containing periods and pulls endpoint",
			input:    "I'm an error: https://api.github.com/repos/owner/my.service.api/pulls/123 and more text",
			expected: "I'm an error: https://api.github.com/repos/:owner/:repo/pulls/:number and more text",
		},
		{
			name:     "Redact URL with repo name containing periods and issues endpoint",
			input:    "I'm an error: https://api.github.com/repos/owner/service.core.api/issues/456 and more text",
			expected: "I'm an error: https://api.github.com/repos/:owner/:repo/issues/:number and more text",
		},
		{
			name:     "Redact URL with owner and repo both containing periods",
			input:    "I'm an error: https://api.github.com/repos/org.team/project.service.api/git/refs and more text",
			expected: "I'm an error: https://api.github.com/repos/:owner/:repo/git/refs and more text",
		},
		{
			name:     "Redact collaborator permission URL",
			input:    "Permission check: https://api.github.com/repos/MyOwner/MyRepo/collaborators/MyUsername/permission",
			expected: "Permission check: https://api.github.com/repos/:owner/:repo/collaborators/:user/permission",
		},
		{
			name:     "Redact issue reactions URL with ID",
			input:    "Reaction error: https://api.github.com/repos/MyOwner/MyRepo/issues/123/reactions/204289461",
			expected: "Reaction error: https://api.github.com/repos/:owner/:repo/issues/:number/reactions/:id",
		},
		{
			name:     "Redact actions jobs URL with ID",
			input:    "Job failed: https://api.github.com/repos/MyOwner/MyRepo/actions/jobs/42885175958",
			expected: "Job failed: https://api.github.com/repos/:owner/:repo/actions/jobs/:id",
		},
		{
			name:     "Redact internal API URL",
			input:    "Failed to access: https://internal-api.service.iad.github.net/internal/repos/MyOwner/MyRepo/actions/dynamic",
			expected: "Failed to access: https://internal-api.service.iad.github.net/internal/repos/:owner/:repo/actions/dynamic",
		},
		{
			name:     "Redact GitHub git URL",
			input:    "Clone failed: https://github.com/MyOwner/MyRepo.git",
			expected: "Clone failed: https://github.com/:owner/:repo.git",
		},
		{
			name:     "Redact GitHub git URL",
			input:    "Clone failed: https://github.com/MyOwner/MyRepo",
			expected: "Clone failed: https://github.com/:owner/:repo",
		},
		// Test validation failed messages with branch names
		{
			name:     "Redact validation failed message with Japanese characters in branch name",
			input:    "Failed to handle result: failed to update pull request: failed to update pull request: PATCH https://api.github.com/repositories/1044636597/pulls/30: 422 Validation Failed [{Resource:PullRequest Field:base Code:invalid Message:A pull request already exists for base branch 'formリファクタリング_git_入力マージ' and head branch 'copilot/create-overall-design-document'}]",
			expected: "Failed to handle result: failed to update pull request: failed to update pull request: PATCH https://api.github.com/repositories/:repo/pulls/:number: 422 Validation Failed [{Resource:PullRequest Field:base Code:invalid Message:A pull request already exists for base branch '<branch>' and head branch 'copilot/<branch>'}]",
		},
		{
			name:     "Redact validation failed message with Spanish characters in branch name",
			input:    "Failed to handle result: failed to update pull request: failed to update pull request: PATCH https://api.github.com/repositories/1016973226/pulls/79: 422 Validation Failed [{Resource:PullRequest Field:base Code:invalid Message:A pull request already exists for base branch '76-sistema-de-alertas-y-mensajería-con-notificaciones-multicanal' and head branch 'copilot/implement-multichannel-notification-system'}]",
			expected: "Failed to handle result: failed to update pull request: failed to update pull request: PATCH https://api.github.com/repositories/:repo/pulls/:number: 422 Validation Failed [{Resource:PullRequest Field:base Code:invalid Message:A pull request already exists for base branch '<branch>' and head branch 'copilot/<branch>'}]",
		},
		{
			name:     "Redact validation failed message with Polish characters in branch name",
			input:    "Failed to handle result: failed to update pull request: failed to update pull request: PATCH https://api.github.com/repositories/838803490/pulls/5: 422 Validation Failed [{Resource:PullRequest Field:base Code:invalid Message:A pull request already exists for base branch '4-z-powodu-wejścia-w-życie-ksef' and head branch 'copilot/add-endpoint-for-fv-import'}]",
			expected: "Failed to handle result: failed to update pull request: failed to update pull request: PATCH https://api.github.com/repositories/:repo/pulls/:number: 422 Validation Failed [{Resource:PullRequest Field:base Code:invalid Message:A pull request already exists for base branch '<branch>' and head branch 'copilot/<branch>'}]",
		},
		{
			name:     "Redact validation failed message with Chinese characters in branch name",
			input:    "Failed to handle result: failed to update pull request: failed to update pull request: PATCH https://api.github.com/repositories/1041371689/pulls/12: 422 Validation Failed [{Resource:PullRequest Field:base Code:invalid Message:A pull request already exists for base branch 'master-選單改為上方' and head branch 'copilot/remove-dynamic-linking-from-forms'}]",
			expected: "Failed to handle result: failed to update pull request: failed to update pull request: PATCH https://api.github.com/repositories/:repo/pulls/:number: 422 Validation Failed [{Resource:PullRequest Field:base Code:invalid Message:A pull request already exists for base branch '<branch>' and head branch 'copilot/<branch>'}]",
		},
		{
			name:     "Redact validation failed message with Japanese date in branch name",
			input:    "Failed to handle result: failed to update pull request: failed to update pull request: PATCH https://api.github.com/repositories/1057711795/pulls/2: 422 Validation Failed [{Resource:PullRequest Field:base Code:invalid Message:A pull request already exists for base branch '作成-25-0101' and head branch 'copilot/investigate-post-office-number-use'}]",
			expected: "Failed to handle result: failed to update pull request: failed to update pull request: PATCH https://api.github.com/repositories/:repo/pulls/:number: 422 Validation Failed [{Resource:PullRequest Field:base Code:invalid Message:A pull request already exists for base branch '<branch>' and head branch 'copilot/<branch>'}]",
		},
		{
			name:     "Redact validation failed message with traditional Chinese in branch name",
			input:    "Failed to handle result: failed to update pull request: failed to update pull request: PATCH https://api.github.com/repositories/956278429/pulls/11: 422 Validation Failed [{Resource:PullRequest Field:base Code:invalid Message:A pull request already exists for base branch 'feature/VSTS528357_新增支援markdown語法' and head branch 'copilot/add-unit-tests-for-query'}]",
			expected: "Failed to handle result: failed to update pull request: failed to update pull request: PATCH https://api.github.com/repositories/:repo/pulls/:number: 422 Validation Failed [{Resource:PullRequest Field:base Code:invalid Message:A pull request already exists for base branch '<branch>' and head branch 'copilot/<branch>'}]",
		},
		{
			name:     "Redact simple validation failed message with base and head branches",
			input:    "422 Validation Failed [{Message:A pull request already exists for base branch 'main' and head branch 'feature-branch'}]",
			expected: "422 Validation Failed [{Message:A pull request already exists for base branch '<branch>' and head branch '<branch>'}]",
		},
		// Test alternate repository ID endpoint format
		{
			name:     "Redact repository ID URL",
			input:    "I'm an error: https://api.github.com/repositories/938254149 and more text",
			expected: "I'm an error: https://api.github.com/repositories/:repo and more text",
		},
		{
			name:     "Redact repository ID URL with issues endpoint",
			input:    "I'm an error: https://api.github.com/repositories/938254149/issues/32 and more text",
			expected: "I'm an error: https://api.github.com/repositories/:repo/issues/:number and more text",
		},
		{
			name:     "Redact repository ID URL with pulls endpoint",
			input:    "I'm an error: https://api.github.com/repositories/123456789/pulls/456 and more text",
			expected: "I'm an error: https://api.github.com/repositories/:repo/pulls/:number and more text",
		},
		{
			name:     "Redact repository ID URL with collaborator permission",
			input:    "Permission check: https://api.github.com/repositories/938254149/collaborators/MyUsername/permission",
			expected: "Permission check: https://api.github.com/repositories/:repo/collaborators/:user/permission",
		},
		{
			name:     "Redact repository ID URL with issue reactions",
			input:    "Reaction error: https://api.github.com/repositories/938254149/issues/123/reactions/204289461",
			expected: "Reaction error: https://api.github.com/repositories/:repo/issues/:number/reactions/:id",
		},
		{
			name:     "Redact repository ID URL with actions jobs",
			input:    "Job failed: https://api.github.com/repositories/938254149/actions/jobs/42885175958",
			expected: "Job failed: https://api.github.com/repositories/:repo/actions/jobs/:id",
		},
		{
			name:     "Redact actions runs URL with owner and repo",
			input:    "Run failed: https://api.github.com/repos/somerepoowner/somreponame/actions/runs/18377584251",
			expected: "Run failed: https://api.github.com/repos/:owner/:repo/actions/runs/:id",
		},
		{
			name:     "Redact actions runs cancel URL with owner and repo",
			input:    "Cancel failed: https://api.github.com/repos/somerepoowner/somreponame/actions/runs/18379447541/cancel",
			expected: "Cancel failed: https://api.github.com/repos/:owner/:repo/actions/runs/:id/cancel",
		},
		{
			name:     "Redact repository ID URL with actions runs",
			input:    "Run failed: https://api.github.com/repositories/123456789/actions/runs/18377584251",
			expected: "Run failed: https://api.github.com/repositories/:repo/actions/runs/:id",
		},
		{
			name:     "Redact repository ID URL with actions runs cancel",
			input:    "Cancel failed: https://api.github.com/repositories/123456789/actions/runs/18379447541/cancel",
			expected: "Cancel failed: https://api.github.com/repositories/:repo/actions/runs/:id/cancel",
		},
		{
			name:     "Redact issue comments list URL with owner and repo",
			input:    "GET https://api.github.com/repos/myowner/myrepo/issues/42/comments failed",
			expected: "GET https://api.github.com/repos/:owner/:repo/issues/:number/comments failed",
		},
		{
			name:     "Redact repository ID URL with issue comments list",
			input:    "GET https://api.github.com/repositories/123456789/issues/4/comments failed",
			expected: "GET https://api.github.com/repositories/:repo/issues/:number/comments failed",
		},
		{
			name:     "Redact repository ID URL with issue comments list (different number)",
			input:    "GET https://api.github.com/repositories/987654321/issues/88/comments failed",
			expected: "GET https://api.github.com/repositories/:repo/issues/:number/comments failed",
		},
		{
			name:     "Redact issue comment URL",
			input:    "PATCH https://api.github.com/repos/MyOwner/MyOwner/issues/comments/2981588060: 503 No server is currently available.",
			expected: "PATCH https://api.github.com/repos/:owner/:repo/issues/comments/:id: 503 No server is currently available.",
		},
		{
			name:     "Redact pull request comment URL",
			input:    "POST https://api.github.com/repos/MyOwner/MyOwner/pulls/123/comments/2153016368/replies: 500 []",
			expected: "POST https://api.github.com/repos/:owner/:repo/pulls/:number/comments/:id/replies: 500 []",
		},
		{
			name:     "Redact git commit URL",
			input:    "GET https://api.github.com/repos/MyOwner/MyOwner/git/commits/982a826921dc3745b3463e950a1e2b08c7f64b17: 503 No server is currently available.",
			expected: "GET https://api.github.com/repos/:owner/:repo/git/commits/:hash: 503 No server is currently available.",
		},
		{
			name:     "Redact repository issue comment URL",
			input:    "PATCH https://api.github.com/repositories/938254149/issues/comments/2981588060: 503 No server is currently available.",
			expected: "PATCH https://api.github.com/repositories/:repo/issues/comments/:id: 503 No server is currently available.",
		},
		{
			name:     "Redact repository pull request comment URL",
			input:    "POST https://api.github.com/repositories/938254149/pulls/123/comments/2153016368/replies: 500 []",
			expected: "POST https://api.github.com/repositories/:repo/pulls/:number/comments/:id/replies: 500 []",
		},
		{
			name:     "Redact repository git commit URL",
			input:    "GET https://api.github.com/repositories/938254149/git/commits/982a826921dc3745b3463e950a1e2b08c7f64b17: 503 No server is currently available.",
			expected: "GET https://api.github.com/repositories/:repo/git/commits/:hash: 503 No server is currently available.",
		},
		// Test Proxima tenant URLs
		{
			name:     "Redact Proxima tenant URL with owner and repo",
			input:    "I'm an error: https://internal-api.service.test-ae-01.github.net/test-tenant/repos/owner/repo and more text",
			expected: "I'm an error: https://internal-api.service.test-ae-01.github.net/<tenant>/repos/:owner/:repo and more text",
		},
		{
			name:     "Redact Proxima tenant URL with owner and repo and sub-paths",
			input:    "I'm an error: https://internal-api.service.test-ae-01.github.net/test-tenant/repos/example-owner/example-repo/git/refs and more text",
			expected: "I'm an error: https://internal-api.service.test-ae-01.github.net/<tenant>/repos/:owner/:repo/git/refs and more text",
		},
		{
			name:     "Redact Proxima tenant URL with owner, repo, and pull number",
			input:    "Pull request error: https://internal-api.service.test-ae-01.github.net/test-tenant/repos/myowner/myrepo/pulls/123",
			expected: "Pull request error: https://internal-api.service.test-ae-01.github.net/<tenant>/repos/:owner/:repo/pulls/:number",
		},
		{
			name:     "Redact Proxima tenant URL with owner, repo, and issue number",
			input:    "Issue error: https://internal-api.service.test-ae-01.github.net/test-tenant/repos/owner/repo/issues/456",
			expected: "Issue error: https://internal-api.service.test-ae-01.github.net/<tenant>/repos/:owner/:repo/issues/:number",
		},
		{
			name:     "Redact Proxima tenant collaborator permission URL",
			input:    "Permission check: https://internal-api.service.test-ae-01.github.net/test-tenant/repos/owner/repo/collaborators/username/permission",
			expected: "Permission check: https://internal-api.service.test-ae-01.github.net/<tenant>/repos/:owner/:repo/collaborators/:user/permission",
		},
		{
			name:     "Redact Proxima tenant URL path with a branch name",
			input:    "I'm an error: https://internal-api.service.test-ae-01.github.net/test-tenant/repos/example-owner/example-repo/git/refs/heads/copilot/fix-31-2 and more text",
			expected: "I'm an error: https://internal-api.service.test-ae-01.github.net/<tenant>/repos/:owner/:repo/git/refs/heads/copilot/<branch> and more text",
		},
		{
			name:     "Redact Proxima tenant URL with repo name containing periods",
			input:    "I'm an error: https://internal-api.service.test-ae-01.github.net/test-tenant/repos/foobar/foobar.AssetService.AssetService and more text",
			expected: "I'm an error: https://internal-api.service.test-ae-01.github.net/<tenant>/repos/:owner/:repo and more text",
		},
		{
			name:     "Redact Proxima tenant URL with repo name containing periods and pulls endpoint",
			input:    "Pull request error: https://internal-api.service.test-ae-01.github.net/test-tenant/repos/owner/my.service.api/pulls/123 and more text",
			expected: "Pull request error: https://internal-api.service.test-ae-01.github.net/<tenant>/repos/:owner/:repo/pulls/:number and more text",
		},
		{
			name:     "Redact Proxima tenant URL with repo name containing periods and issues endpoint",
			input:    "Issue error: https://internal-api.service.test-ae-01.github.net/test-tenant/repos/owner/service.core.api/issues/456 and more text",
			expected: "Issue error: https://internal-api.service.test-ae-01.github.net/<tenant>/repos/:owner/:repo/issues/:number and more text",
		},
		{
			name:     "Redact Proxima tenant URL with owner and repo both containing periods",
			input:    "I'm an error: https://internal-api.service.test-ae-01.github.net/test-tenant/repos/org.team/project.service.api/git/refs and more text",
			expected: "I'm an error: https://internal-api.service.test-ae-01.github.net/<tenant>/repos/:owner/:repo/git/refs and more text",
		},
		{
			name:     "Redact Proxima tenant collaborator permission URL",
			input:    "Permission check: https://internal-api.service.test-ae-01.github.net/my-tenant/repos/MyOwner/MyRepo/collaborators/MyUsername/permission",
			expected: "Permission check: https://internal-api.service.test-ae-01.github.net/<tenant>/repos/:owner/:repo/collaborators/:user/permission",
		},
		{
			name:     "Redact Proxima tenant issue reactions URL with ID",
			input:    "Reaction error: https://internal-api.service.test-ae-01.github.net/my-tenant/repos/MyOwner/MyRepo/issues/123/reactions/204289461",
			expected: "Reaction error: https://internal-api.service.test-ae-01.github.net/<tenant>/repos/:owner/:repo/issues/:number/reactions/:id",
		},
		{
			name:     "Redact Proxima tenant actions jobs URL with ID",
			input:    "Job failed: https://internal-api.service.test-ae-01.github.net/my-tenant/repos/MyOwner/MyRepo/actions/jobs/42885175958",
			expected: "Job failed: https://internal-api.service.test-ae-01.github.net/<tenant>/repos/:owner/:repo/actions/jobs/:id",
		},
		{
			name:     "Redact Proxima tenant Copilot URL",
			input:    "I'm an error: https://copilot-api.test-tenant.ghe.com/agents/sessions/ad26548d-8631-4d0a-8651-b0773da80160",
			expected: "I'm an error: https://copilot-api.<tenant>.ghe.com/agents/sessions/:session",
		},
		// Test Proxima tenant repository ID URLs
		{
			name:     "Redact Proxima tenant repository ID URL",
			input:    "Error: https://internal-api.service.test-ae-01.github.net/test-tenant/repositories/123456 and more text",
			expected: "Error: https://internal-api.service.test-ae-01.github.net/<tenant>/repositories/:repo and more text",
		},
		{
			name:     "Redact Proxima tenant repository ID URL with issues endpoint",
			input:    "Error: https://internal-api.service.test-ae-01.github.net/test-tenant/repositories/123456/issues/42 and more text",
			expected: "Error: https://internal-api.service.test-ae-01.github.net/<tenant>/repositories/:repo/issues/:number and more text",
		},
		{
			name:     "Redact Proxima tenant repository ID URL with pulls endpoint",
			input:    "Pull error: https://internal-api.service.test-ae-01.github.net/test-tenant/repositories/789012/pulls/456 and more text",
			expected: "Pull error: https://internal-api.service.test-ae-01.github.net/<tenant>/repositories/:repo/pulls/:number and more text",
		},
		{
			name:     "Redact Proxima tenant repository ID URL with collaborator permission",
			input:    "Permission check: https://internal-api.service.test-ae-01.github.net/test-tenant/repositories/345678/collaborators/username/permission",
			expected: "Permission check: https://internal-api.service.test-ae-01.github.net/<tenant>/repositories/:repo/collaborators/:user/permission",
		},
		{
			name:     "Redact Proxima tenant repository ID URL with issue reactions",
			input:    "Reaction error: https://internal-api.service.test-ae-01.github.net/test-tenant/repositories/901234/issues/123/reactions/204289461",
			expected: "Reaction error: https://internal-api.service.test-ae-01.github.net/<tenant>/repositories/:repo/issues/:number/reactions/:id",
		},
		{
			name:     "Redact Proxima tenant repository ID URL with actions jobs",
			input:    "Job failed: https://internal-api.service.test-ae-01.github.net/test-tenant/repositories/567890/actions/jobs/42885175958",
			expected: "Job failed: https://internal-api.service.test-ae-01.github.net/<tenant>/repositories/:repo/actions/jobs/:id",
		},
		{
			name:     "Redact Proxima tenant repository ID issue comment URL",
			input:    "PATCH https://internal-api.service.test-ae-01.github.net/test-tenant/repositories/123456/issues/comments/2981588060: 503 No server is currently available.",
			expected: "PATCH https://internal-api.service.test-ae-01.github.net/<tenant>/repositories/:repo/issues/comments/:id: 503 No server is currently available.",
		},
		{
			name:     "Redact Proxima tenant repository ID pull request comment URL",
			input:    "POST https://internal-api.service.test-ae-01.github.net/test-tenant/repositories/789012/pulls/123/comments/2153016368/replies: 500 []",
			expected: "POST https://internal-api.service.test-ae-01.github.net/<tenant>/repositories/:repo/pulls/:number/comments/:id/replies: 500 []",
		},
		{
			name:     "Redact Proxima tenant repository ID git commit URL",
			input:    "GET https://internal-api.service.test-ae-01.github.net/my-tenant/repositories/345678/git/commits/982a826921dc3745b3463e950a1e2b08c7f64b17: 503 No server is currently available.",
			expected: "GET https://internal-api.service.test-ae-01.github.net/<tenant>/repositories/:repo/git/commits/:hash: 503 No server is currently available.",
		},
		{
			name:     "Redact Proxima tenant repository ID repository comment URL",
			input:    "PATCH https://internal-api.service.test-ae-01.github.net/test-tenant/repositories/123456/issues/comments/2981588060: 503 No server is currently available.",
			expected: "PATCH https://internal-api.service.test-ae-01.github.net/<tenant>/repositories/:repo/issues/comments/:id: 503 No server is currently available.",
		},
		{
			name:     "Redact Proxima tenant repository ID pull request comment URL",
			input:    "POST https://internal-api.service.test-ae-01.github.net/test-tenant/repositories/938254149/pulls/123/comments/2153016368/replies: 500 []",
			expected: "POST https://internal-api.service.test-ae-01.github.net/<tenant>/repositories/:repo/pulls/:number/comments/:id/replies: 500 []",
		},
		{
			name:     "Redact Proxima tenant repository ID git commit URL",
			input:    "GET https://internal-api.service.test-ae-01.github.net/test-tenant/repositories/938254149/git/commits/982a826921dc3745b3463e950a1e2b08c7f64b17: 503 No server is currently available.",
			expected: "GET https://internal-api.service.test-ae-01.github.net/<tenant>/repositories/:repo/git/commits/:hash: 503 No server is currently available.",
		},
		// Other GitHub endpoints
		{
			name:     "Redact applications token URL",
			input:    "DELETE https://api.github.com/applications/Iv23ctzlsVrAf9UtZ48B/token: 503 No server is currently available.",
			expected: "DELETE https://api.github.com/applications/:id/token: 503 No server is currently available.",
		},
		{
			name:     "Redact Copilot session URL",
			input:    "Error in session: https://api.githubcopilot.com/agents/sessions/ad26548d-8631-4d0a-8651-b0773da80160",
			expected: "Error in session: https://api.githubcopilot.com/agents/sessions/:session",
		},
		{
			name:     "Redact Copilot branch name",
			input:    "I'm an error: copilot/fix-123 and more text",
			expected: "I'm an error: copilot/<branch> and more text",
		},
		{
			name:     "Redact Copilot branch name with multiple numbers",
			input:    "I'm an error: copilot/fix-123-123 and more text",
			expected: "I'm an error: copilot/<branch> and more text",
		},
		{
			name:     "Redact Copilot branch name with a UUID",
			input:    fmt.Sprintf("copilot/%s-%s", uuid.New(), uuid.New()),
			expected: "copilot/<branch>",
		},
		{
			name:     "Redact IP addresses in error message",
			input:    "failed to create global app token: read tcp 10.125.85.161:60100->140.82.113.5:443: read: connection timed out",
			expected: "failed to create global app token: read tcp <ip-address>-><ip-address>: read: connection timed out",
		},
		{
			name:     "Redact multiple IP addresses in error message",
			input:    "failed to create global app token: read tcp 10.125.84.193:38386->140.82.113.6:443: read: connection timed out",
			expected: "failed to create global app token: read tcp <ip-address>-><ip-address>: read: connection timed out",
		},
		{
			name:     "Redact queue job ID pattern - event-job-queue",
			input:    "Error in sweagentd/event-job-queue/61-0199badd-8ee8-7248-83f3-7e5ec3f45683:roanoke:",
			expected: "Error in <app>/<queue>/<job-id>:<cluster>:",
		},
		{
			name:     "Redact queue job ID pattern - agent-job-queue",
			input:    "Failed: sweagentd/agent-job-queue/62-0199bacf-ae7a-752c-933d-d043f0949877:hudson:",
			expected: "Failed: <app>/<queue>/<job-id>:<cluster>:",
		},
		{
			name:     "Redact queue job ID pattern - staging with api-job-background-queue",
			input:    "Error in sweagentd-staging-jedi-knight/api-job-background-queue/61-0199badd-8ee8-7248-83f3-7e5ec3f45683:otherthing:",
			expected: "Error in <app>/<queue>/<job-id>:<cluster>:",
		},
		{
			name:     "Redact queue job ID pattern - multiple in same string",
			input:    "First: sweagentd/event-job-queue/61-0199badd-8ee8-7248-83f3-7e5ec3f45683:roanoke: and second: sweagentd/agent-job-queue/62-0199bacf-ae7a-752c-933d-d043f0949877:hudson:",
			expected: "First: <app>/<queue>/<job-id>:<cluster>: and second: <app>/<queue>/<job-id>:<cluster>:",
		},
		{
			name:     "Redact queue job ID pattern - different cluster names",
			input:    "Jobs: sweagentd/my-queue/61-0199badd-8ee8-7248-83f3-7e5ec3f45683:clusterone: and sweagentd/another-queue/62-0199bacf-ae7a-752c-933d-d043f0949877:clustertwo:",
			expected: "Jobs: <app>/<queue>/<job-id>:<cluster>: and <app>/<queue>/<job-id>:<cluster>:",
		},
		{
			name:     "Redact queue job ID pattern - at beginning of string",
			input:    "sweagentd/event-job-queue/61-0199badd-8ee8-7248-83f3-7e5ec3f45683:roanoke: caused an error",
			expected: "<app>/<queue>/<job-id>:<cluster>: caused an error",
		},
		{
			name:     "Redact queue job ID pattern - at end of string",
			input:    "Error occurred in sweagentd/event-job-queue/61-0199badd-8ee8-7248-83f3-7e5ec3f45683:roanoke:",
			expected: "Error occurred in <app>/<queue>/<job-id>:<cluster>:",
		},
		{
			name:     "Redact queue job ID pattern - with uppercase letters in queue name",
			input:    "Error in sweagentd/MyQueue/61-0199badd-8ee8-7248-83f3-7e5ec3f45683:roanoke:",
			expected: "Error in <app>/<queue>/<job-id>:<cluster>:",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var payload map[string]any
			exporter := mockexporter.NewExporter(func(ctx context.Context, data []byte) error {
				if err := json.NewDecoder(bytes.NewReader(data)).Decode(&payload); err != nil {
					return fmt.Errorf("failed to decode JSON: %w", err)
				}
				return nil
			})

			reporter, err := newReporter(exporter, "test", "test", "testsha", "testref", nil)
			require.NoError(t, err)

			err = reporter.Report(context.Background(), errors.New(tt.input), map[string]string{})
			require.NoError(t, err)

			require.True(t, exporter.IsInvoked(), "Exporter should be invoked")
			require.NotNil(t, payload, "Message should not be nil")

			message, ok := payload["message"].(string)
			require.True(t, ok, "Message should be a string")
			require.Equal(t, tt.expected, message, "Message should match expected value")
		})
	}
}

func TestRedactRollupInfo(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{
			name:     "Redact request ID with 8 chars each segment",
			input:    "Error occurred with request: 12345678:abcdef01:87654321:fedcba09:11223344",
			expected: "Error occurred with request: <request-id>",
		},
		{
			name:     "Redact request ID with mixed case",
			input:    "Request failed: 1a2b3c4d:5E6F7A8B:9C0D1E2F:3A4B5C6D:7E8F9A0B",
			expected: "Request failed: <request-id>",
		},
		{
			name:     "Redact request ID with shorter segments",
			input:    "Error: 123:abc:456:def:789",
			expected: "Error: <request-id>",
		},
		{
			name:     "Redact request ID with single char segments",
			input:    "Failed with ID: 1:a:2:b:3",
			expected: "Failed with ID: <request-id>",
		},
		{
			name:     "Redact multiple request IDs in same string",
			input:    "First: 12345678:abcdef01:87654321:fedcba09:11223344 and second: 1a2b3c4d:5E6F7A8B:9C0D1E2F:3A4B5C6D:7E8F9A0B",
			expected: "First: <request-id> and second: <request-id>",
		},
		{
			name:     "No request ID to redact",
			input:    "This is just a regular error message without any request IDs",
			expected: "This is just a regular error message without any request IDs",
		},
		{
			name:     "Invalid request ID format (too few segments)",
			input:    "Error with incomplete ID: 12345678:abcdef01:87654321:fedcba09",
			expected: "Error with incomplete ID: 12345678:abcdef01:87654321:fedcba09",
		},
		{
			name:     "Invalid request ID format (too many segments)",
			input:    "Error with extra segment: 12345678:abcdef01:87654321:fedcba09:11223344:extra",
			expected: "Error with extra segment: <request-id>:extra",
		},
		{
			name:     "Invalid request ID format (segments too long)",
			input:    "Error with long segment: 123456789:abcdef01:87654321:fedcba09:11223344",
			expected: "Error with long segment: 1<request-id>",
		},
		{
			name:     "Invalid request ID format (non-hex characters)",
			input:    "Error with invalid chars: 1234567g:abcdef01:87654321:fedcba09:11223344",
			expected: "Error with invalid chars: 1234567g:abcdef01:87654321:fedcba09:11223344",
		},
		{
			name:     "Request ID at beginning of string",
			input:    "12345678:abcdef01:87654321:fedcba09:11223344 caused an error",
			expected: "<request-id> caused an error",
		},
		{
			name:     "Request ID at end of string",
			input:    "Error occurred with request ID 12345678:abcdef01:87654321:fedcba09:11223344",
			expected: "Error occurred with request ID <request-id>",
		},
		{
			name:     "Empty string",
			input:    "",
			expected: "",
		},
		{
			name:     "Redact retry info with single digit counts",
			input:    "Operation failed: retried 5 times (total retry wait time: 99 seconds)",
			expected: "Operation failed: <retry-info>",
		},
		{
			name:     "Redact retry info with multi-digit counts",
			input:    "Request timeout: retried 15 times (total retry wait time: 300 seconds)",
			expected: "Request timeout: <retry-info>",
		},
		{
			name:     "Redact retry info at beginning of string",
			input:    "retried 3 times (total retry wait time: 45 seconds) and then gave up",
			expected: "<retry-info> and then gave up",
		},
		{
			name:     "Redact retry info at end of string",
			input:    "Connection failed after retried 10 times (total retry wait time: 180 seconds)",
			expected: "Connection failed after <retry-info>",
		},
		{
			name:     "Redact multiple retry info in same string",
			input:    "First attempt: retried 2 times (total retry wait time: 30 seconds), second attempt: retried 7 times (total retry wait time: 120 seconds)",
			expected: "First attempt: <retry-info>, second attempt: <retry-info>",
		},
		{
			name:     "Redact retry info with zero values",
			input:    "Error: retried 0 times (total retry wait time: 0 seconds)",
			expected: "Error: <retry-info>",
		},
		{
			name:     "No retry info to redact",
			input:    "This is just a regular error message without retry information",
			expected: "This is just a regular error message without retry information",
		},
		{
			name:     "Partial retry pattern (missing seconds)",
			input:    "Error: retried 5 times (total retry wait time: 99)",
			expected: "Error: retried 5 times (total retry wait time: 99)",
		},
		{
			name:     "Partial retry pattern (missing parentheses)",
			input:    "Error: retried 5 times total retry wait time: 99 seconds",
			expected: "Error: retried 5 times total retry wait time: 99 seconds",
		},
		{
			name:     "Retry info with extra text in parentheses",
			input:    "Error: retried 5 times (total retry wait time: 99 seconds and more info)",
			expected: "Error: retried 5 times (total retry wait time: 99 seconds and more info)",
		},
		{
			name:     "Redact 'after N attempts' with multiple attempts",
			input:    "session API request failed after 5 attempts: unauthorized",
			expected: "session API request failed after <attempts>: unauthorized",
		},
		{
			name:     "Redact 'after N attempt' with single attempt",
			input:    "giving up after 1 attempt",
			expected: "giving up after <attempts>",
		},
		{
			name:     "Redact 'after N attempts' with large number",
			input:    "POST https://internal-api.service.iad.github.net/internal/twirp/sweagentd.sweagentd_api.v1.SweagentdAPI/MintUserToServerTokenForRepo giving up after 4 attempts",
			expected: "POST https://internal-api.service.iad.github.net/internal/twirp/sweagentd.sweagentd_api.v1.SweagentdAPI/MintUserToServerTokenForRepo giving up after <attempts>",
		},
		{
			name:     "Redact 'after N attempts' in middle of string",
			input:    "failed to do request: Post \"https://example.com/api\" after 10 attempts and then gave up",
			expected: "failed to do request: Post \"https://example.com/api\" after <attempts> and then gave up",
		},
		{
			name:     "Redact 'after N attempts' at beginning of string",
			input:    "after 3 attempts the connection timed out",
			expected: "after <attempts> the connection timed out",
		},
		{
			name:     "Redact 'after N attempts' at end of string",
			input:    "Connection to database failed after 7 attempts",
			expected: "Connection to database failed after <attempts>",
		},
		{
			name:     "Redact multiple 'after N attempts' in same string",
			input:    "First service failed after 5 attempts, then second service failed after 3 attempts",
			expected: "First service failed after <attempts>, then second service failed after <attempts>",
		},
		{
			name:     "Redact 'after N attempts' with zero attempts",
			input:    "Immediately failed after 0 attempts",
			expected: "Immediately failed after <attempts>",
		},
		{
			name:     "No 'after N attempts' to redact",
			input:    "This is just a regular error message without attempt information",
			expected: "This is just a regular error message without attempt information",
		},
		{
			name:     "Partial attempt pattern (missing 'after')",
			input:    "Error: 5 attempts were made",
			expected: "Error: 5 attempts were made",
		},
		{
			name:     "Real world example 1 - session API request",
			input:    "handler error for job sweagentd/event-job-queue/25-0199c991-aafa-7f35-b041-0c2702c4b428:roanoke: failed to handle assignment: failed to build job: failed to create session: failed to create session: Post \"https://api.githubcopilot.com/agents/sessions\": unexpected status code 401: session API request failed after 5 attempts: unauthorized: unauthorized: AuthenticateToken authentication failed",
			expected: "handler error for job <app>/<queue>/<job-id>:<cluster>: failed to handle assignment: failed to build job: failed to create session: failed to create session: Post \"https://api.githubcopilot.com/agents/sessions\": unexpected status code 401: session API request failed after <attempts>: unauthorized: unauthorized: AuthenticateToken authentication failed",
		},
		{
			name:     "Real world example 2 - giving up after attempts",
			input:    "Unwrapped error: failed to mint user to server token for repo: twirp error internal: failed to do request: Post \"https://internal-api.service.iad.github.net/internal/twirp/sweagentd.sweagentd_api.v1.SweagentdAPI/MintUserToServerTokenForRepo\": POST https://internal-api.service.iad.github.net/internal/twirp/sweagentd.sweagentd_api.v1.SweagentdAPI/MintUserToServerTokenForRepo giving up after 4 attempts",
			expected: "Unwrapped error: failed to mint user to server token for repo: twirp error internal: failed to do request: Post \"https://internal-api.service.iad.github.net/internal/twirp/sweagentd.sweagentd_api.v1.SweagentdAPI/MintUserToServerTokenForRepo\": POST https://internal-api.service.iad.github.net/internal/twirp/sweagentd.sweagentd_api.v1.SweagentdAPI/MintUserToServerTokenForRepo giving up after <attempts>",
		},
		{
			name:     "Redact UUID request ID",
			input:    "Error occurred with request: 7c7e05d9-85af-46b6-b94b-9c2b7e544dd5",
			expected: "Error occurred with request: <request-id>",
		},
		{
			name:     "Redact UUID with uppercase letters",
			input:    "Error occurred with request: 7C7E05D9-85AF-46B6-B94B-9C2B7E544DD5",
			expected: "Error occurred with request: <request-id>",
		},
		{
			name:     "Redact UUID in middle of string",
			input:    "Request failed with ID: f47ac10b-58cc-4372-a567-0e02b2c3d479 and more text",
			expected: "Request failed with ID: <request-id> and more text",
		},
		{
			name:     "Redact multiple UUIDs in same string",
			input:    "First: 550e8400-e29b-41d4-a716-446655440000 and second: 6ba7b810-9dad-11d1-80b4-00c04fd430c8",
			expected: "First: <request-id> and second: <request-id>",
		},
		{
			name:     "Redact UUID at beginning of string",
			input:    "123e4567-e89b-12d3-a456-426614174000 caused an error",
			expected: "<request-id> caused an error",
		},
		{
			name:     "Redact UUID at end of string",
			input:    "Error occurred with UUID 00000000-0000-0000-0000-000000000000",
			expected: "Error occurred with UUID <request-id>",
		},
		{
			name:     "No UUID to redact",
			input:    "This is just a regular error message without any UUIDs",
			expected: "This is just a regular error message without any UUIDs",
		},
		{
			name:     "Invalid UUID format (too short)",
			input:    "Error with short ID: 123e4567-e89b-12d3-a456-42661417400",
			expected: "Error with short ID: 123e4567-e89b-12d3-a456-42661417400",
		},
		{
			name:     "Invalid UUID format (too long)",
			input:    "Error with long ID: 123e4567-e89b-12d3-a456-4266141740000",
			expected: "Error with long ID: 123e4567-e89b-12d3-a456-4266141740000",
		},
		{
			name:     "Invalid UUID format (wrong separators)",
			input:    "Error with wrong format: 123e4567_e89b_12d3_a456_426614174000",
			expected: "Error with wrong format: 123e4567_e89b_12d3_a456_426614174000",
		},
		{
			name:     "Invalid UUID format (non-hex characters)",
			input:    "Error with invalid chars: 123g4567-e89b-12d3-a456-426614174000",
			expected: "Error with invalid chars: 123g4567-e89b-12d3-a456-426614174000",
		},
		{
			name:     "Redact timeout with decimal seconds",
			input:    "timeout after 10.000679034s",
			expected: "timeout after <timeout>",
		},
		{
			name:     "Redact timeout with integer seconds",
			input:    "Operation failed: timeout after 30s",
			expected: "Operation failed: timeout after <timeout>",
		},
		{
			name:     "Redact date and time with timezone",
			input:    "Error occurred at 2023-10-01T12:34:56Z with timeout after 15.5s",
			expected: "Error occurred at <datetime> with timeout after <timeout>",
		},
		{
			name:     "Redact date and time with timezone",
			input:    "Something went wrong while executing your query on 2025-06-17T19:56:46Z.",
			expected: "Something went wrong while executing your query on <datetime>.",
		},
		{
			name:     "Redact date and time with request ID",
			input:    "Something went wrong while executing your query on 2025-06-17T19:56:46Z. Please include `B2D2:128377:E520A2:1C6DBB3:6851C87C` when reporting this issue.",
			expected: "Something went wrong while executing your query on <datetime>. Please include `<request-id>` when reporting this issue.",
		},
		{
			name:     "Redact timeout at beginning of string",
			input:    "timeout after 5.123s occurred during request",
			expected: "timeout after <timeout> occurred during request",
		},
		{
			name:     "Redact timeout at end of string",
			input:    "Request failed due to timeout after 45.567s",
			expected: "Request failed due to timeout after <timeout>",
		},
		{
			name:     "Redact multiple timeouts in same string",
			input:    "First timeout after 10.5s, then another timeout after 20s",
			expected: "First timeout after <timeout>, then another timeout after <timeout>",
		},
		{
			name:     "Redact timeout with very precise decimal",
			input:    "timeout after 123.456789012s",
			expected: "timeout after <timeout>",
		},
		{
			name:     "Redact timeout with zero value",
			input:    "timeout after 0s",
			expected: "timeout after <timeout>",
		},
		{
			name:     "Redact timeout with zero decimal",
			input:    "timeout after 0.0s",
			expected: "timeout after <timeout>",
		},
		{
			name:     "No timeout to redact",
			input:    "This is just a regular error message without timeout information",
			expected: "This is just a regular error message without timeout information",
		},
		{
			name:     "Partial timeout pattern (missing 's')",
			input:    "Error: timeout after 10.5",
			expected: "Error: timeout after 10.5",
		},
		{
			name:     "Timeout with different unit (not seconds)",
			input:    "Error: timeout after 10.5ms",
			expected: "Error: timeout after 10.5ms",
		},
		{
			name:     "Redact database ID in error message",
			input:    "Database error with ID: 80350150-986570413-77c09ee2-caa5-4c5c-8f9b-9cd9f37ce0cc",
			expected: "Database error with ID: <database-id>",
		},
		{
			name:     "Redact database ID in different context",
			input:    "Failed to connect to database 106155996-998460395-5b73369f-e288-4eed-aa9c-0f42aec3cf9c and retry",
			expected: "Failed to connect to database <database-id> and retry",
		},
		{
			name:     "Redact database ID at beginning of string",
			input:    "80350150-986570413-77c09ee2-caa5-4c5c-8f9b-9cd9f37ce0cc caused connection failure",
			expected: "<database-id> caused connection failure",
		},
		{
			name:     "Redact database ID at end of string",
			input:    "Connection timeout for database 106155996-998460395-5b73369f-e288-4eed-aa9c-0f42aec3cf9c",
			expected: "Connection timeout for database <database-id>",
		},
		{
			name:     "Redact multiple database IDs in same string",
			input:    "Primary DB: 80350150-986570413-77c09ee2-caa5-4c5c-8f9b-9cd9f37ce0cc, Secondary DB: 106155996-998460395-5b73369f-e288-4eed-aa9c-0f42aec3cf9c",
			expected: "Primary DB: <database-id>, Secondary DB: <database-id>",
		},
		{
			name:     "Redact database ID with uppercase UUID",
			input:    "Database error: 80350150-986570413-77C09EE2-CAA5-4C5C-8F9B-9CD9F37CE0CC",
			expected: "Database error: <database-id>",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var payload map[string]any
			exporter := mockexporter.NewExporter(func(ctx context.Context, data []byte) error {
				if err := json.NewDecoder(bytes.NewReader(data)).Decode(&payload); err != nil {
					return fmt.Errorf("failed to decode JSON: %w", err)
				}
				return nil
			})

			reporter, err := newReporter(exporter, "test", "test", "testsha", "testref", nil)
			require.NoError(t, err)

			err = reporter.Report(context.Background(), errors.New(tt.input), map[string]string{})
			require.NoError(t, err)

			require.True(t, exporter.IsInvoked(), "Exporter should be invoked")
			require.NotNil(t, payload, "Message should not be nil")

			ru, ok := payload["rollup"].(string)
			require.True(t, ok, "Rollup should be a string")
			expectedRollup := rollup(tt.expected)
			require.Equal(t, expectedRollup, ru, "Rollup should match expected value")
		})
	}
}

// rollup generates a SHA-256 hash of the input string and returns it as a hexadecimal string.
func rollup(info string) string {
	hash := sha256.New()
	_, _ = io.WriteString(hash, info)
	return fmt.Sprintf("%x", hash.Sum(nil))
}

func genStackTrace(err error) error {
	return goerrors.WithStack(err)
}

func TestNewStackTracer(t *testing.T) {
	// Create first error with stack trace
	err := errors.New("first error")
	errWithStack1 := genStackTrace(err)

	// Create second error with stack trace, wrapping the first
	errWithStack2 := goerrors.WithStack(errWithStack1)

	// Get the stack tracer
	stackTracer := NewStackTracer()

	// Call the stack tracer with the wrapped error
	stacks, rawStackTrace := stackTracer(errWithStack2)

	// Verify we got two stack traces
	require.Len(t, stacks, 2)
	require.NotEmpty(t, rawStackTrace)

	require.Greater(t, len(stacks[0].Frames), 1)
	curframe := stacks[0].Frames[len(stacks[0].Frames)-1]
	require.Equal(t, "github.com/github/sweagentd/internal/observability/exceptions.TestNewStackTracer", curframe.Function)
	require.Equal(t, "exceptions_test.go", filepath.Base(curframe.AbsPath))
	require.Equal(t, "first error", stacks[0].Value)
	require.Equal(t, fmt.Sprintf("%T", errWithStack1), stacks[0].Type)

	require.Greater(t, len(stacks[1].Frames), 2)
	curframe = stacks[1].Frames[len(stacks[1].Frames)-1]
	require.Equal(t, "github.com/github/sweagentd/internal/observability/exceptions.genStackTrace", curframe.Function)
	require.Equal(t, "exceptions_test.go", filepath.Base(curframe.AbsPath))
	curframe = stacks[1].Frames[len(stacks[1].Frames)-2]
	require.Equal(t, "github.com/github/sweagentd/internal/observability/exceptions.TestNewStackTracer", curframe.Function)
	require.Equal(t, "exceptions_test.go", filepath.Base(curframe.AbsPath))
	require.Equal(t, "first error", stacks[1].Value)
	require.Equal(t, fmt.Sprintf("%T", err), stacks[1].Type)
}
