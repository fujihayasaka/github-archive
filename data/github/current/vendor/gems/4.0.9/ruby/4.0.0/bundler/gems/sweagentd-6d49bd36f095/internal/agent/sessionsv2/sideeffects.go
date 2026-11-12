package sessionsv2

import (
	"encoding/json"

	"github.com/github/sweagentd/internal/goerrors"
)

// ProgressItem is the minimal shape needed to identify side-effect events.
type ProgressItem struct {
	Namespace string
	Kind      string
	Content   string
}

// ReportProgressContent is the parsed content of a report_progress event.
type ReportProgressContent struct {
	PRTitle       string `json:"pr_title"`
	PRDescription string `json:"pr_description"`
}

// CommentReplyContent is the parsed content of a comment_reply event.
type CommentReplyContent struct {
	CommentID int64  `json:"comment_id"`
	Message   string `json:"message"`
}

// SideEffect represents a parsed side-effect action from a progress event.
type SideEffect struct {
	Kind           string
	ReportProgress *ReportProgressContent
	CommentReply   *CommentReplyContent
	PRSummary      *ReportProgressContent // same shape as report_progress
}

// ExtractSideEffects filters and parses side-effect events from a list of
// progress items. Only sessions-v2 items with recognized side-effect kinds
// are returned. Parse errors are collected in the second return value so
// callers can log them without aborting the entire batch.
func ExtractSideEffects(items []ProgressItem) ([]SideEffect, []error) {
	var effects []SideEffect
	var errs []error

	for _, item := range items {
		if item.Namespace != Namespace {
			continue
		}

		switch item.Kind {
		case KindReportProgress:
			var rp ReportProgressContent
			err := json.Unmarshal([]byte(item.Content), &rp)
			if err != nil {
				errs = append(errs, goerrors.Errorf("failed to parse %s content: %w", KindReportProgress, err))
				continue
			}
			effects = append(effects, SideEffect{Kind: KindReportProgress, ReportProgress: &rp})

		case KindCommentReply:
			var cr CommentReplyContent
			err := json.Unmarshal([]byte(item.Content), &cr)
			if err != nil {
				errs = append(errs, goerrors.Errorf("failed to parse %s content: %w", KindCommentReply, err))
				continue
			}
			effects = append(effects, SideEffect{Kind: KindCommentReply, CommentReply: &cr})

		case KindPRSummary:
			var ps ReportProgressContent
			err := json.Unmarshal([]byte(item.Content), &ps)
			if err != nil {
				errs = append(errs, goerrors.Errorf("failed to parse %s content: %w", KindPRSummary, err))
				continue
			}
			if ps.PRTitle == "" {
				errs = append(errs, goerrors.Errorf("%s requires a non-empty pr_title", KindPRSummary))
				continue
			}
			effects = append(effects, SideEffect{Kind: KindPRSummary, PRSummary: &ps})

		default:
		}
	}

	return effects, errs
}
