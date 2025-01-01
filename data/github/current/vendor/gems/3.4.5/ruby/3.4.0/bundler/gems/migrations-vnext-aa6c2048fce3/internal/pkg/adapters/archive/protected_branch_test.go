package archive

import (
	"testing"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

func TestToV1ProtectedBranch(t *testing.T) {
	tests := []struct {
		name        string
		input       *ProtectedBranch
		expected    *v1.ProtectedBranch
		expectedID  string
		expectError bool
	}{
		{
			name: "Valid ProtectedBranch Conversion",
			input: &ProtectedBranch{
				Name:                             "main",
				RepositoryURL:                    "https://github.com/org/repo",
				RequiresApprovingReviews:         true,
				RequiredApprovingReviewCount:     2,
				RequiresCommitSignatures:         true,
				RequiresLinearHistory:            true,
				AllowsForcePushes:                false,
				AllowsDeletions:                  false,
				AdminEnforced:                    true,
				RequiresStatusChecks:             true,
				StrictRequiredStatusChecksPolicy: true,
				RequireCodeOwnerReview:           true,
				DismissStaleReviewsOnPush:        true,
				RestrictsReviewDismissals:        true,
				AuthorizedActorsOnly:             true,
				RequiredStatusChecks:             []string{"check1", "check2"},
				RequiresReviewThreadResolution:   true,
				RequireLastPushApproval:          true,
			},
			expected: &v1.ProtectedBranch{
				ResourceId:                     "protectedbranch-main-https://github.com/org/repo",
				RepositoryResourceId:           "https://github.com/org/repo",
				Name:                           "main",
				RequiresApprovingReviews:       &wrapperspb.BoolValue{Value: true},
				RequiredApprovingReviewCount:   &wrapperspb.Int32Value{Value: 2},
				RequiresCommitSignatures:       &wrapperspb.BoolValue{Value: true},
				RequiresLinearHistory:          &wrapperspb.BoolValue{Value: true},
				AllowsForcePushes:              &wrapperspb.BoolValue{Value: false},
				AllowsDeletions:                &wrapperspb.BoolValue{Value: false},
				IsAdminEnforced:                &wrapperspb.BoolValue{Value: true},
				RequiresStatusChecks:           &wrapperspb.BoolValue{Value: true},
				RequiresStrictStatusChecks:     &wrapperspb.BoolValue{Value: true},
				RequiresCodeOwnerReviews:       &wrapperspb.BoolValue{Value: true},
				DismissesStaleReviews:          &wrapperspb.BoolValue{Value: true},
				RestrictsReviewDismissals:      &wrapperspb.BoolValue{Value: true},
				RestrictsPushes:                &wrapperspb.BoolValue{Value: true},
				RequiredStatusCheckContexts:    []string{"check1", "check2"},
				RequiresReviewThreadResolution: &wrapperspb.BoolValue{Value: true},
				RequireLastPushApproval:        &wrapperspb.BoolValue{Value: true},
			},
			expectError: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, err := tt.input.ToV1ProtectedBranch()

			if tt.expectError {
				assert.Error(t, err)
			} else {
				require.NoError(t, err)
				assert.Equal(t, tt.expected, result)
			}
		})
	}
}
