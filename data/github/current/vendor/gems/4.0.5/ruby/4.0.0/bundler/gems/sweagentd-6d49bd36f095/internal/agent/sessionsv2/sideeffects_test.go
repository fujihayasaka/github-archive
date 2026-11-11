package sessionsv2

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestExtractSideEffects(t *testing.T) {
	t.Run("extracts report_progress", func(t *testing.T) {
		items := []ProgressItem{
			{Namespace: Namespace, Kind: KindReportProgress, Content: `{"pr_title":"Fix bug","pr_description":"Fixed it"}`},
		}
		effects, errs := ExtractSideEffects(items)
		require.Empty(t, errs)
		require.Len(t, effects, 1)
		assert.Equal(t, KindReportProgress, effects[0].Kind)
		assert.Equal(t, "Fix bug", effects[0].ReportProgress.PRTitle)
		assert.Equal(t, "Fixed it", effects[0].ReportProgress.PRDescription)
	})

	t.Run("extracts comment_reply", func(t *testing.T) {
		items := []ProgressItem{
			{Namespace: Namespace, Kind: KindCommentReply, Content: `{"comment_id":42,"message":"Done!"}`},
		}
		effects, errs := ExtractSideEffects(items)
		require.Empty(t, errs)
		require.Len(t, effects, 1)
		assert.Equal(t, KindCommentReply, effects[0].Kind)
		assert.Equal(t, int64(42), effects[0].CommentReply.CommentID)
		assert.Equal(t, "Done!", effects[0].CommentReply.Message)
	})

	t.Run("extracts pr_summary", func(t *testing.T) {
		items := []ProgressItem{
			{Namespace: Namespace, Kind: KindPRSummary, Content: `{"pr_title":"Add auth module","pr_description":"Implements JWT-based auth"}`},
		}
		effects, errs := ExtractSideEffects(items)
		require.Empty(t, errs)
		require.Len(t, effects, 1)
		assert.Equal(t, KindPRSummary, effects[0].Kind)
		assert.Equal(t, "Add auth module", effects[0].PRSummary.PRTitle)
		assert.Equal(t, "Implements JWT-based auth", effects[0].PRSummary.PRDescription)
	})

	t.Run("rejects pr_summary with empty title", func(t *testing.T) {
		items := []ProgressItem{
			{Namespace: Namespace, Kind: KindPRSummary, Content: `{"pr_title":"","pr_description":"Some desc"}`},
		}
		effects, errs := ExtractSideEffects(items)
		require.Len(t, errs, 1)
		assert.Contains(t, errs[0].Error(), "requires a non-empty pr_title")
		assert.Empty(t, effects)
	})

	t.Run("skips non-sessions-v2 namespace", func(t *testing.T) {
		items := []ProgressItem{
			{Namespace: "runtime", Kind: KindReportProgress, Content: `{"pr_title":"ignored"}`},
		}
		effects, errs := ExtractSideEffects(items)
		assert.Empty(t, errs)
		assert.Empty(t, effects)
	})

	t.Run("skips non-side-effect kinds", func(t *testing.T) {
		items := []ProgressItem{
			{Namespace: Namespace, Kind: KindMessage, Content: `{"kind":"message"}`},
			{Namespace: Namespace, Kind: KindToolExecution, Content: `{}`},
		}
		effects, errs := ExtractSideEffects(items)
		assert.Empty(t, errs)
		assert.Empty(t, effects)
	})

	t.Run("collects parse errors without aborting", func(t *testing.T) {
		items := []ProgressItem{
			{Namespace: Namespace, Kind: KindReportProgress, Content: `{invalid}`},
			{Namespace: Namespace, Kind: KindCommentReply, Content: `{"comment_id":99,"message":"OK"}`},
		}
		effects, errs := ExtractSideEffects(items)
		require.Len(t, errs, 1)
		assert.Contains(t, errs[0].Error(), "failed to parse report_progress content")
		require.Len(t, effects, 1)
		assert.Equal(t, KindCommentReply, effects[0].Kind)
	})

	t.Run("handles mixed batch", func(t *testing.T) {
		items := []ProgressItem{
			{Namespace: "runtime", Kind: "log", Content: `{}`},
			{Namespace: Namespace, Kind: KindMessage, Content: `{}`},
			{Namespace: Namespace, Kind: KindReportProgress, Content: `{"pr_title":"T1"}`},
			{Namespace: Namespace, Kind: KindCommentReply, Content: `{"comment_id":1,"message":"M1"}`},
			{Namespace: Namespace, Kind: KindReportProgress, Content: `{"pr_description":"D2"}`},
			{Namespace: Namespace, Kind: KindPRSummary, Content: `{"pr_title":"Final","pr_description":"Final desc"}`},
		}
		effects, errs := ExtractSideEffects(items)
		assert.Empty(t, errs)
		require.Len(t, effects, 4)
		assert.Equal(t, KindReportProgress, effects[0].Kind)
		assert.Equal(t, "T1", effects[0].ReportProgress.PRTitle)
		assert.Equal(t, KindCommentReply, effects[1].Kind)
		assert.Equal(t, KindReportProgress, effects[2].Kind)
		assert.Equal(t, "D2", effects[2].ReportProgress.PRDescription)
		assert.Equal(t, KindPRSummary, effects[3].Kind)
		assert.Equal(t, "Final", effects[3].PRSummary.PRTitle)
	})

	t.Run("empty items returns empty", func(t *testing.T) {
		effects, errs := ExtractSideEffects(nil)
		assert.Empty(t, errs)
		assert.Empty(t, effects)
	})
}
