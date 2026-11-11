package github

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestUserIsAllowlistedBot(t *testing.T) {
	ghApp := &GitHubApp{
		ID:       123,
		AppLogin: "copilot-swe-agent",
		BotLogin: "copilot-swe-agent[bot]",
	}

	tests := []struct {
		name     string
		login    string
		expected bool
	}{
		{
			name:     "returns true for `copilot-pull-request-reviewer`",
			login:    "copilot-pull-request-reviewer",
			expected: true,
		},
		{
			name:     "returns true for `copilot-pull-request-reviewer[bot]`",
			login:    "copilot-pull-request-reviewer[bot]",
			expected: true,
		},
		{
			name:     "returns false for regular user",
			login:    "octocat",
			expected: false,
		},
		{
			name:     "returns false for different bot",
			login:    "github-actions[bot]",
			expected: false,
		},
		{
			name:     "returns false for copilot app login",
			login:    "copilot-swe-agent",
			expected: false,
		},
		{
			name:     "returns false for copilot bot login",
			login:    "copilot-swe-agent[bot]",
			expected: false,
		},
		{
			name:     "returns false for generic Copilot",
			login:    "Copilot",
			expected: false,
		},
		{
			name:     "returns false for empty string",
			login:    "",
			expected: false,
		},
		{
			name:     "returns false for similar but different login",
			login:    "copilot-pull-request-reviewer-v2",
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := UserIsAllowlistedBot(ghApp, tt.login)
			require.Equal(t, tt.expected, result)
		})
	}
}

func TestClientUserIsAllowlistedBot(t *testing.T) {
	ghApp := &GitHubApp{
		ID:       123,
		AppLogin: "copilot-swe-agent",
		BotLogin: "copilot-swe-agent[bot]",
	}

	client := &Client{
		githubApp: ghApp,
	}

	tests := []struct {
		name     string
		login    string
		expected bool
	}{
		{
			name:     "returns true for CCR",
			login:    "copilot-pull-request-reviewer",
			expected: true,
		},
		{
			name:     "returns true for CCR with [bot] suffix",
			login:    "copilot-pull-request-reviewer[bot]",
			expected: true,
		},
		{
			name:     "returns false for regular user",
			login:    "octocat",
			expected: false,
		},
		{
			name:     "returns false for copilot",
			login:    "Copilot",
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := client.UserIsAllowlistedBot(tt.login)
			require.Equal(t, tt.expected, result)
		})
	}
}

func TestGQLActorIsAllowlistedBot(t *testing.T) {
	ghApp := &GitHubApp{
		ID:       123,
		AppLogin: "copilot-swe-agent",
		BotLogin: "copilot-swe-agent[bot]",
	}

	client := &Client{
		githubApp: ghApp,
	}

	tests := []struct {
		name     string
		actor    GQLActor
		expected bool
	}{
		{
			name:     "returns true for CCR bot",
			actor:    NewGQLActor(1, "node1", CopilotCodeReviewAppSlug, GQLActorTypeBot, "CCR"),
			expected: true,
		},
		{
			name:     "returns true for CCR bot with [bot] suffix",
			actor:    NewGQLActor(2, "node2", CopilotCodeReviewAppSlug+"[bot]", GQLActorTypeBot, "CCR Bot"),
			expected: true,
		},
		{
			name:     "returns false for CCR as user type",
			actor:    NewGQLActor(3, "node3", CopilotCodeReviewAppSlug, GQLActorTypeUser, "CCR User"),
			expected: false,
		},
		{
			name:     "returns false for regular bot",
			actor:    NewGQLActor(4, "node4", "github-actions[bot]", GQLActorTypeBot, "GitHub Actions"),
			expected: false,
		},
		{
			name:     "returns false for copilot bot",
			actor:    NewGQLActor(5, "node5", "Copilot", GQLActorTypeBot, "Copilot"),
			expected: false,
		},
		{
			name:     "returns false for regular user",
			actor:    NewGQLActor(6, "node6", "octocat", GQLActorTypeUser, "Octocat"),
			expected: false,
		},
		{
			name:     "returns false for copilot app login as bot",
			actor:    NewGQLActor(7, "node7", "copilot-swe-agent[bot]", GQLActorTypeBot, "Copilot SWE Agent"),
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := tt.actor.IsAllowlistedBot(client)
			require.Equal(t, tt.expected, result)
		})
	}
}

func TestUserIsCopilot(t *testing.T) {
	ghApp := &GitHubApp{
		ID:       123,
		AppLogin: "copilot-swe-agent",
		BotLogin: "copilot-swe-agent[bot]",
	}

	tests := []struct {
		name     string
		login    string
		expected bool
	}{
		{
			name:     "returns false for regular user",
			login:    "not-copilot",
			expected: false,
		},
		{
			name:     "returns false for `copilot-pull-request-reviewer` (now allowlisted bot, not copilot)",
			login:    "copilot-pull-request-reviewer",
			expected: false,
		},
		{
			name:     "returns false for `copilot-pull-request-reviewer[bot]`",
			login:    "copilot-pull-request-reviewer[bot]",
			expected: false,
		},
		{
			name:     "returns true for app login",
			login:    "copilot-swe-agent",
			expected: true,
		},
		{
			name:     "returns true for app login with [bot]",
			login:    "copilot-swe-agent[bot]",
			expected: true,
		},
		{
			name:     "returns true for bot login",
			login:    "copilot-swe-agent[bot]",
			expected: true,
		},
		{
			name:     "returns true for generic Copilot",
			login:    "Copilot",
			expected: true,
		},
		{
			name:     "returns false for empty string",
			login:    "",
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := UserIsCopilot(ghApp, tt.login)
			require.Equal(t, tt.expected, result)
		})
	}
}

func TestDoesMentionCopilot(t *testing.T) {
	tests := []struct {
		name     string
		body     string
		expected bool
	}{
		// Valid mentions
		{
			name:     "@-mention at start",
			body:     "@Copilot comment-body",
			expected: true,
		},
		{
			name:     "@-mention with leading space",
			body:     " @Copilot comment-body",
			expected: true,
		},
		{
			name:     "@-mention with comma",
			body:     "@Copilot, comment-body",
			expected: true,
		},
		{
			name:     "@-mention with colon",
			body:     "@Copilot: comment-body",
			expected: true,
		},
		{
			name:     "@-mention with exclamation mark",
			body:     "@Copilot! comment-body",
			expected: true,
		},
		{
			name:     "@-mention with question mark",
			body:     "@Copilot? comment-body",
			expected: true,
		},
		{
			name:     "@-mention with period",
			body:     "@Copilot. comment-body",
			expected: true,
		},
		{
			name:     "@-mention with ellipsis",
			body:     "@Copilot... comment-body",
			expected: true,
		},
		{
			name:     "@-mention with newline",
			body:     "@Copilot\ncomment-body",
			expected: true,
		},
		{
			name:     "@-mention with random casing",
			body:     "@cOpIlOt comment-body",
			expected: true,
		},
		{
			name:     "@-mention lowercase",
			body:     "@copilot comment-body",
			expected: true,
		},
		{
			name:     "@-mention in middle of text",
			body:     "Hey @copilot can you help?",
			expected: true,
		},
		{
			name:     "@-mention at end",
			body:     "Please help @copilot",
			expected: true,
		},

		// Invalid mentions - wrapped in backticks
		{
			name:     "@-mention wrapped in single backticks",
			body:     "Use `@copilot` to mention",
			expected: false,
		},
		{
			name:     "@-mention wrapped in backticks with text before",
			body:     "The syntax `@copilot` is used",
			expected: false,
		},
		{
			name:     "@-mention wrapped in backticks with text after",
			body:     "Type `@copilot` in your comment",
			expected: false,
		},
		{
			name:     "@-mention in inline code",
			body:     "To mention copilot use `@copilot` in comments",
			expected: false,
		},
		{
			name:     "multiple backtick pairs with @copilot in first pair",
			body:     "Use `@copilot` or `@github-copilot` to mention",
			expected: false,
		},
		{
			name:     "@-mention in backticks among other text",
			body:     "Before `@copilot` after",
			expected: false,
		},
		{
			name:     "@-mention in code block with backticks",
			body:     "Here's how: `echo @copilot`",
			expected: false,
		},

		// Mixed cases - backticks present but @copilot outside
		{
			name:     "@-mention outside backticks with other code",
			body:     "@copilot can you check `this code`?",
			expected: true,
		},
		{
			name:     "@-mention before backticked code",
			body:     "@copilot `code here`",
			expected: true,
		},
		{
			name:     "@-mention after backticked code",
			body:     "`code here` @copilot",
			expected: true,
		},
		{
			name:     "backticked text with @copilot outside",
			body:     "The `function` needs @copilot review",
			expected: true,
		},
		{
			name:     "multiple @copilot mentions, one in backticks",
			body:     "@copilot please check the `@copilot` syntax",
			expected: true,
		},

		// Edge cases
		{
			name:     "no @-mention",
			body:     "comment-body",
			expected: false,
		},
		{
			name:     "email with @copilot",
			body:     "ee@copilot comment-body",
			expected: false,
		},
		{
			name:     "word containing copilot",
			body:     "acopilot comment-body",
			expected: false,
		},
		{
			name:     "copilot without @",
			body:     "copilot comment-body",
			expected: false,
		},
		{
			name:     "@ followed by copilot with underscore",
			body:     "@copilot_bot comment-body",
			expected: false,
		},
		{
			name:     "empty string",
			body:     "",
			expected: false,
		},
		{
			name:     "just @copilot",
			body:     "@copilot",
			expected: true,
		},
		{
			name:     "unmatched backtick before @copilot",
			body:     "` @copilot",
			expected: true, // Unmatched backtick doesn't form a code block, so @copilot is visible
		},
		{
			name:     "unmatched backtick after @copilot",
			body:     "@copilot `",
			expected: true,
		},
		{
			name:     "three backticks with @copilot in middle",
			body:     "` @copilot ` outside",
			expected: false, // First pair of backticks contains @copilot
		},
		{
			name:     "multiple pairs of backticks",
			body:     "`code1` @copilot `code2`",
			expected: true,
		},

		// Triple backtick code blocks
		{
			name:     "@-mention in triple backtick code block",
			body:     "```\n@copilot\n```",
			expected: false,
		},
		{
			name:     "@-mention in triple backtick code block with language",
			body:     "```go\n@copilot help\n```",
			expected: false,
		},
		{
			name:     "@-mention in triple backtick code block inline",
			body:     "```@copilot```",
			expected: false,
		},
		{
			name:     "@-mention outside triple backtick code block",
			body:     "@copilot check this:\n```\ncode here\n```",
			expected: true,
		},
		{
			name:     "@-mention after triple backtick code block",
			body:     "```\ncode here\n```\n@copilot",
			expected: true,
		},
		{
			name:     "triple backtick block with @copilot before",
			body:     "@copilot\n```\nsome code\n```",
			expected: true,
		},
		{
			name:     "multiple triple backtick blocks with @copilot inside one",
			body:     "```\ncode1\n```\n```\n@copilot\n```\ntext",
			expected: false,
		},
		{
			name:     "mixed single and triple backticks with @copilot in triple",
			body:     "`inline` text ```\n@copilot\n``` more",
			expected: false,
		},
		{
			name:     "mixed single and triple backticks with @copilot outside",
			body:     "`inline` @copilot ```\ncode\n```",
			expected: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := DoesMentionCopilot(tt.body)
			require.Equal(t, tt.expected, result, "Expected %v for body: %q", tt.expected, tt.body)
		})
	}
}
