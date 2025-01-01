package types

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestCommitMessageType(t *testing.T) {
	t.Run("Test CommitMessage IsEqual method", func(t *testing.T) {
		testCases := []struct {
			name  string
			left  CommitMessage
			right CommitMessage
			want  bool
		}{
			{
				name:  "both empty",
				left:  CommitMessage(""),
				right: CommitMessage(""),
				want:  true,
			},
			{
				name:  "not empty and equal",
				left:  CommitMessage("some commit message"),
				right: CommitMessage("some commit message"),
				want:  true,
			},
			{
				name:  "not empty but different due to whitespace",
				left:  CommitMessage("some commit message"),
				right: CommitMessage("some commit message\n"),
				want:  false,
			},
		}
		for _, tt := range testCases {
			t.Run(tt.name, func(t *testing.T) {
				want := tt.want
				got := tt.left.IsEqual(tt.right)
				require.Equal(t, want, got)
			})
		}
	})
	t.Run("Test CommitMessage IsZeroValue method", func(t *testing.T) {
		testCases := []struct {
			name string
			msg  CommitMessage
			want bool
		}{
			{
				name: "blank string",
				msg:  CommitMessage(" "),
				want: false,
			},
			{
				name: "non-empty",
				msg:  CommitMessage("blabla"),
				want: false,
			},
			{
				name: "empty",
				msg:  CommitMessage(""),
				want: true,
			},
		}
		for _, tt := range testCases {
			t.Run(tt.name, func(t *testing.T) {
				want := tt.want
				got := tt.msg.IsZeroValue()
				require.Equal(t, want, got)
			})
		}
	})
}
