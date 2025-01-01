package workflowinvoker

import (
	"regexp"
	"strings"

	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/types"

	githubgo "github.com/google/go-github/v25/github"
)

func isSkippablePushOrPullRequest(inv Invocation) bool {
	event := inv.Event.Ghe
	switch evt := event.(type) {
	case *githubgo.PullRequestEvent:
		switch inv.Event.Name {
		case flowevents.PullRequestTarget:
			return false
		case flowevents.PullRequest:
			return true
		}
		return false
	case *githubgo.PushEvent:
		if types.CommitSha(evt.GetAfter()).IsNullSha() {
			return false // it's a push request, but to delete
		}
		return true
	default:
		return false
	}
}

func hasSkipRunAnnotation(msg types.CommitMessage) bool {
	if types.CommitMessageZeroValue.IsEqual(msg) {
		return false
	}
	msgS := string(msg)
	if hasBracketSkipKeywordAnywhere(msgS) {
		return true
	}
	cleaned := strings.TrimSpace(msgS)
	return skipAnnotationRegexp.MatchString(cleaned)
}

// skipAnnotationRegexp matches this syntax (EBNF):
//
//	should_skip ::= 3 * leading, skip_word, trailing
//	leading     ::= "\n" | "\r\n"
//	skip_word   ::= "skip-checks: true" | "skip-checks:true"
//	trailing    ::= "" | "\n" | "\r\n"
var skipAnnotationRegexp = regexp.MustCompile(`(\n|(\r\n)){3}skip-checks:\s?true(\n|(\r\n))?\z`)

var skipKeywords = [...]string{"[skip ci]", "[ci skip]", "[no ci]", "[skip actions]", "[actions skip]"}

func hasBracketSkipKeywordAnywhere(commitMessage string) bool {
	for _, keyword := range skipKeywords {
		if strings.Contains(commitMessage, keyword) {
			return true
		}
	}
	return false
}
