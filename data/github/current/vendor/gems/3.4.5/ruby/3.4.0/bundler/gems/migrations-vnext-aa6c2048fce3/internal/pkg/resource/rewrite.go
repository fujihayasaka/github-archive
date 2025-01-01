package resource

import (
	"regexp"
	"strings"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

func rewriteIssueBodyAttachmentURLs(issue *v1.Issue, attachmentURLMapping map[string]string) {
	for _, sourceURL := range issue.AttachmentResourceIds {
		if targetURL, exists := attachmentURLMapping[sourceURL]; exists {
			issue.Body = strings.ReplaceAll(issue.Body, sourceURL, targetURL)
		}
	}
}

func rewriteIssueCommentBodyAttachmentURLs(issueComment *v1.IssueComment, attachmentURLMapping map[string]string) {
	for _, sourceURL := range issueComment.AttachmentResourceIds {
		if targetURL, exists := attachmentURLMapping[sourceURL]; exists {
			issueComment.Body = strings.ReplaceAll(issueComment.Body, sourceURL, targetURL)
		}
	}
}

func rewritePullRequestBodyAttachmentURLs(pr *v1.PullRequest, attachmentURLMapping map[string]string) {
	for _, sourceURL := range pr.AttachmentResourceIds {
		if targetURL, exists := attachmentURLMapping[sourceURL]; exists {
			pr.Body = strings.ReplaceAll(pr.Body, sourceURL, targetURL)
		}
	}
}

func rewritePullRequestReviewBodyAttachmentURLs(pr *v1.PullRequestReview, attachmentURLMapping map[string]string) {
	for _, sourceURL := range pr.AttachmentResourceIds {
		if targetURL, exists := attachmentURLMapping[sourceURL]; exists {
			pr.Body = strings.ReplaceAll(pr.Body, sourceURL, targetURL)
		}
	}
}

func rewritePullRequestReviewCommentBodyAttachmentURLs(pr *v1.PullRequestReviewComment, attachmentURLMapping map[string]string) {
	for _, sourceURL := range pr.AttachmentResourceIds {
		if targetURL, exists := attachmentURLMapping[sourceURL]; exists {
			pr.Body = strings.ReplaceAll(pr.Body, sourceURL, targetURL)
		}
	}
}

// rewriteBaseURL rewrites the base URL of a resource. This is an initial and very naive implementation that
// only rewrites the base URL of any URL that is found in the input string. This may change URLs that are not
// intended to be changed. Issue comments URL won't work either because the URL contains the comment ID and
// that changes across systems.
func rewriteBaseURL(in, oldURL, newURL string) string {
	return strings.ReplaceAll(in, oldURL, newURL)
}

func parameterize(s string, separator ...string) string {
	sep := "-"
	if len(separator) > 0 {
		sep = separator[0]
	}

	re := regexp.MustCompile(`[^a-zA-Z0-9\-_]+`)
	parameterizedString := re.ReplaceAllString(s, sep)

	// handle duplicate separators
	reDuplicate := regexp.MustCompile(regexp.QuoteMeta(sep) + `{2,}`)
	parameterizedString = reDuplicate.ReplaceAllString(parameterizedString, sep)

	// remove leading/trailing separators
	reLeadingTrailing := regexp.MustCompile(`^` + regexp.QuoteMeta(sep) + `|` + regexp.QuoteMeta(sep) + `$`)
	parameterizedString = reLeadingTrailing.ReplaceAllString(parameterizedString, "")

	return parameterizedString
}
