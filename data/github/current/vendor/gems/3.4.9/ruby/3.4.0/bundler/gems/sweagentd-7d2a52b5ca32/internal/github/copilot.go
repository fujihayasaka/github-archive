package github

import (
	"slices"

	"github.com/github/sweagentd/internal/agenticapp"
)

// CopilotCodeReviewAppSlug is the slug for the CCR GitHub App - some APIs return this string rather than `Copilot`
const CopilotCodeReviewAppSlug = "copilot-pull-request-reviewer"

type CopilotUserChecker interface {
	UserIsCopilot(login string) bool
	UserIsAllowlistedBot(login string) bool
	ContainsCopilotUser(logins []string) bool
}

func (ac *Client) UserIsCopilot(login string) bool {
	return UserIsCopilot(ac.githubApp, login)
}

func (ac *Client) UserIsAllowlistedBot(login string) bool {
	return UserIsAllowlistedBot(ac.githubApp, login)
}

func (ac *Client) ContainsCopilotUser(logins []string) bool {
	return ContainsCopilotUser(ac.githubApp, logins)
}

func (cf *ClientFactory) UserIsCopilot(login string) bool {
	return UserIsCopilot(cf.githubApp, login)
}

func (cf *ClientFactory) UserIsAllowlistedBot(login string) bool {
	return UserIsAllowlistedBot(cf.githubApp, login)
}

func (cf *ClientFactory) ContainsCopilotUser(logins []string) bool {
	return ContainsCopilotUser(cf.githubApp, logins)
}

func UserIsCopilot(githubApp *GitHubApp, login string) bool {
	// Our privileged app also reports the display login as "Copilot",
	// but not consistently. For now, just handle every case.
	copilotLogins := []string{
		githubApp.AppLogin,
		githubApp.AppLogin + "[bot]",
		githubApp.BotLogin,
		"Copilot",
	}

	// Ignore review comments on PRs not opened by the GitHub App
	// which looks like a login followed by [bot]
	return slices.Contains(copilotLogins, login)
}

// We want to allow certain bot logins to perform certain actions
func UserIsAllowlistedBot(githubApp *GitHubApp, login string) bool {
	allowlistedBotLogins := []string{
		CopilotCodeReviewAppSlug,
		CopilotCodeReviewAppSlug + "[bot]",
	}

	return slices.Contains(allowlistedBotLogins, login)
}

func ContainsCopilotUser(githubApp *GitHubApp, logins []string) bool {
	return slices.ContainsFunc(logins, func(login string) bool {
		return UserIsCopilot(githubApp, login)
	})
}

// DoesMentionCopilot checks if the body contains a mention of Copilot (includes `@copilot`).
// It excludes mentions wrapped in backticks (inline code) or triple backticks (code blocks).
func DoesMentionCopilot(body string) bool {
	// Step 1: Remove all backtick-enclosed content (both inline code and code blocks)
	bodyWithoutBackticks := agenticapp.BacktickContentPattern.ReplaceAllString(body, "")

	// Step 2: Check if @copilot mention exists in the remaining text
	return agenticapp.CopilotAtMentionRegexp.MatchString(bodyWithoutBackticks)
}
