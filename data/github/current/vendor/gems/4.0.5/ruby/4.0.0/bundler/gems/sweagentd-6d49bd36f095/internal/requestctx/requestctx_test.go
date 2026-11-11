package requestctx

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/github/go-http/v2/middleware/tenant"
	"github.com/stretchr/testify/require"
)

func TestBucketFunctions(t *testing.T) {
	tests := []struct {
		name                string
		bucketFunc          func(any) uint64
		rangeTestCases      []any
		consistencyTestCase any
		distributionRange   []any
	}{
		{
			name: "BucketUInt64",
			bucketFunc: func(input any) uint64 {
				return bucketUInt64(input.(uint64))
			},
			rangeTestCases:      []any{uint64(0), uint64(1), uint64(100), uint64(1000), uint64(10000), uint64(18446744073709551615)}, // max uint64
			consistencyTestCase: uint64(12345),
			distributionRange: func() []any {
				var inputs []any
				for i := range uint64(1000) {
					inputs = append(inputs, i)
				}
				return inputs
			}(),
		},
		{
			name: "BucketInt64",
			bucketFunc: func(input any) uint64 {
				return bucketInt64(input.(int64))
			},
			rangeTestCases:      []any{int64(-9223372036854775808), int64(-1000), int64(-1), int64(0), int64(1), int64(1000), int64(9223372036854775807)}, // min and max int64
			consistencyTestCase: int64(-12345),
			distributionRange: func() []any {
				var inputs []any
				for i := int64(-500); i < 500; i++ {
					inputs = append(inputs, i)
				}
				return inputs
			}(),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Run("bucket values are within expected range", func(t *testing.T) {
				for _, input := range tt.rangeTestCases {
					bucket := tt.bucketFunc(input)
					require.Less(t, bucket, numberOfStatsBucketsToCoarsenTo,
						"Bucket value %d should be less than %d for input %v",
						bucket, numberOfStatsBucketsToCoarsenTo, input)
				}
			})

			t.Run("same input produces same bucket", func(t *testing.T) {
				bucket1 := tt.bucketFunc(tt.consistencyTestCase)
				bucket2 := tt.bucketFunc(tt.consistencyTestCase)
				require.Equal(t, bucket1, bucket2, "Same input should produce same bucket")
			})

			t.Run("different inputs can produce different buckets", func(t *testing.T) {
				// Test a range of inputs to ensure they don't all map to the same bucket
				buckets := make(map[uint64]bool)
				for _, input := range tt.distributionRange {
					bucket := tt.bucketFunc(input)
					buckets[bucket] = true
				}

				// We should see multiple different bucket values
				require.Greater(t, len(buckets), 1, "Should produce multiple different bucket values")
				require.LessOrEqual(t, len(buckets), int(numberOfStatsBucketsToCoarsenTo),
					"Should not produce more buckets than the coarsening limit")
			})
		})
	}
}

func TestStatsTags_BucketCoarsening(t *testing.T) {
	ctx := context.Background()
	ctx = AddData(ctx, &CtxData{})

	// Set up test data with specific IDs
	userID := uint64(123456789)
	repoID := int64(987654321)
	issueID := int64(555666777)
	prID := int64(111222333)

	// Add all context data
	err := AddUser(ctx, &UserInfo{ID: userID, Login: "testuser", TrackingID: "tracking-id"})
	require.NoError(t, err)
	err = AddRepo(ctx, CtxRepo{ID: repoID})
	require.NoError(t, err)
	err = AddIssue(ctx, CtxIssue{ID: issueID})
	require.NoError(t, err)
	err = AddPullRequest(ctx, CtxPullRequest{ID: &prID, Number: 42})
	require.NoError(t, err)

	// Add HTTP request info
	req, _ := http.NewRequest(http.MethodPost, "/test", http.NoBody)

	tags := statsTags(ctx, req)

	// Verify user_bucket is properly coarsened
	userBucket, exists := tags["user_bucket"]
	require.True(t, exists, "user_bucket should exist in stats tags")
	expectedUserBucket := bucketUInt64(userID)
	require.Equal(t, userBucket, fmt.Sprintf("%d", expectedUserBucket), "user_bucket should match bucketUInt64 output")
	require.Less(t, expectedUserBucket, numberOfStatsBucketsToCoarsenTo, "User bucket should be coarsened")

	// Verify repo_bucket is properly coarsened
	repoBucket, exists := tags["repo_bucket"]
	require.True(t, exists, "repo_bucket should exist in stats tags")
	expectedRepoBucket := bucketInt64(repoID)
	require.Equal(t, repoBucket, fmt.Sprintf("%d", expectedRepoBucket), "repo_bucket should match bucketInt64 output")
	require.Less(t, expectedRepoBucket, numberOfStatsBucketsToCoarsenTo, "Repo bucket should be coarsened")

	// Verify issue_bucket is properly coarsened
	issueBucket, exists := tags["issue_bucket"]
	require.True(t, exists, "issue_bucket should exist in stats tags")
	expectedIssueBucket := bucketInt64(issueID)
	require.Equal(t, issueBucket, fmt.Sprintf("%d", expectedIssueBucket), "issue_bucket should match bucketInt64 output")
	require.Less(t, expectedIssueBucket, numberOfStatsBucketsToCoarsenTo, "Issue bucket should be coarsened")

	// Verify pr_bucket is properly coarsened
	prBucket, exists := tags["pr_bucket"]
	require.True(t, exists, "pr_bucket should exist in stats tags")
	expectedPRBucket := bucketInt64(prID)
	require.Equal(t, prBucket, fmt.Sprintf("%d", expectedPRBucket), "pr_bucket should match bucketInt64 output")
	require.Less(t, expectedPRBucket, numberOfStatsBucketsToCoarsenTo, "PR bucket should be coarsened")

	// Verify HTTP tags are also present
	require.Equal(t, "POST", tags["http.request.method"])
	require.NotEmpty(t, tags["url.route"])

	// Test case where PR ID is nil
	t.Run("pr_bucket is not present when PR ID is nil", func(t *testing.T) {
		ctxNilPR := context.Background()
		ctxNilPR = AddData(ctxNilPR, &CtxData{})
		err := AddPullRequest(ctxNilPR, CtxPullRequest{ID: nil, Number: 42})
		require.NoError(t, err)

		tagsNilPR := statsTags(ctxNilPR, nil)
		_, exists := tagsNilPR["pr_bucket"]
		require.False(t, exists, "pr_bucket should not exist when PR ID is nil")
	})
}

func TestTelemetryIncludesLauncherTypeAndComputeIDInLogsAndExceptions(t *testing.T) {
	ctx := NewContext(context.Background())
	err := AddJob(ctx, &CtxJob{
		ID: "job-123",
	})
	require.NoError(t, err)
	require.NoError(t, SetJobComputeID(ctx, "sandbox-456"))
	require.NoError(t, SetJobLauncherType(ctx, "sandbox"))

	tags := statsTags(ctx, nil)
	require.NotContains(t, tags, "launcher_type")

	_, exceptionTags, fields := ToTelemetry(ctx, nil)
	require.Equal(t, "sandbox-456", exceptionTags["#job.compute_id"])
	require.Equal(t, "sandbox", exceptionTags["#job.launcher_type"])
	require.Equal(t, "false", exceptionTags["is_automation"])

	fieldValues := map[string]any{}
	for _, field := range fields {
		fieldValues[field.Key] = field.String
	}
	require.Equal(t, "sandbox-456", fieldValues["job.compute_id"])
	require.Equal(t, "sandbox", fieldValues["job.launcher_type"])
}

func TestExceptionTagsIncludeJobAutomationStatus(t *testing.T) {
	t.Run("automation job", func(t *testing.T) {
		ctx := NewContext(context.Background())
		err := AddJob(ctx, &CtxJob{
			ID:           "job-123",
			IsAutomation: true,
		})
		require.NoError(t, err)

		_, exceptionTags, _ := ToTelemetry(ctx, nil)
		require.Equal(t, "true", exceptionTags["is_automation"])
	})

	t.Run("non-automation job", func(t *testing.T) {
		ctx := NewContext(context.Background())
		err := AddJob(ctx, &CtxJob{
			ID:           "job-123",
			IsAutomation: false,
		})
		require.NoError(t, err)

		_, exceptionTags, _ := ToTelemetry(ctx, nil)
		require.Equal(t, "false", exceptionTags["is_automation"])
	})
}

func TestBucketDistribution(t *testing.T) {
	t.Run("bucket distribution is reasonable", func(t *testing.T) {
		// Test that buckets are reasonably distributed across the range
		bucketCounts := make(map[uint64]int)

		// Generate buckets for a range of inputs
		for i := range uint64(10000) {
			bucket := bucketUInt64(i)
			bucketCounts[bucket]++
		}

		// We should see a reasonable distribution
		require.Greater(t, len(bucketCounts), 50, "Should use a reasonable number of different buckets")

		// No single bucket should be overwhelmingly dominant
		maxCount := 0
		for _, count := range bucketCounts {
			if count > maxCount {
				maxCount = count
			}
		}

		// With 10000 inputs and 100 buckets, we'd expect roughly 100 per bucket on average
		// Allow for some variation but not extreme skew
		require.Less(t, maxCount, 500, "No single bucket should be overly dominant")
	})
}

func TestTenantFunctions(t *testing.T) {
	t.Run("AddTenantID and TenantID", func(t *testing.T) {
		ctx := context.Background()
		ctx = AddData(ctx, &CtxData{})

		// Test adding and retrieving tenant ID
		testTenantID := "test-tenant-123"
		err := AddTenantID(ctx, testTenantID)
		require.NoError(t, err)

		retrievedTenantID := TenantID(ctx)
		require.Equal(t, testTenantID, retrievedTenantID)

		// Test with invalid context
		err = AddTenantID(context.Background(), "test")
		require.Error(t, err)
		require.Contains(t, err.Error(), "context does not contain requestContext")

		// Test TenantID with invalid context returns empty string
		require.Equal(t, "", TenantID(context.Background()))
	})

	t.Run("AddTenantSlug and TenantSlug", func(t *testing.T) {
		ctx := context.Background()
		ctx = AddData(ctx, &CtxData{})

		// Test adding and retrieving tenant slug
		testTenantSlug := "test-org"
		err := AddTenantSlug(ctx, testTenantSlug)
		require.NoError(t, err)

		retrievedTenantSlug := TenantSlug(ctx)
		require.Equal(t, testTenantSlug, retrievedTenantSlug)

		// Test with invalid context
		err = AddTenantSlug(context.Background(), "test")
		require.Error(t, err)
		require.Contains(t, err.Error(), "context does not contain requestContext")

		// Test TenantSlug with invalid context returns empty string
		require.Equal(t, "", TenantSlug(context.Background()))
	})

	t.Run("TenantID fallback behavior", func(t *testing.T) {
		// Test fallback to tenant package when CtxData exists but TenantID is empty
		ctx := context.Background()
		ctx = AddData(ctx, &CtxData{})

		// First set up tenant package context
		ctx = tenant.TenantIDContext(ctx, "fallback-tenant-id")

		// TenantID should fall back to tenant package function
		retrievedTenantID := TenantID(ctx)
		require.Equal(t, "fallback-tenant-id", retrievedTenantID)

		// Now add a non-empty TenantID to CtxData - it should override the fallback
		err := AddTenantID(ctx, "override-tenant-id")
		require.NoError(t, err)

		retrievedTenantID = TenantID(ctx)
		require.Equal(t, "override-tenant-id", retrievedTenantID)

		// Test with empty TenantID in CtxData - should fallback again
		err = AddTenantID(ctx, "")
		require.NoError(t, err)

		retrievedTenantID = TenantID(ctx)
		require.Equal(t, "fallback-tenant-id", retrievedTenantID)
	})

	t.Run("TenantSlug fallback behavior", func(t *testing.T) {
		// Test fallback to tenant package when CtxData exists but TenantSlug is empty
		ctx := context.Background()
		ctx = AddData(ctx, &CtxData{})

		// First set up tenant package context
		ctx = tenant.TenantContext(ctx, "fallback-tenant-slug")

		// TenantSlug should fall back to tenant package function
		retrievedTenantSlug := TenantSlug(ctx)
		require.Equal(t, "fallback-tenant-slug", retrievedTenantSlug)

		// Now add a non-empty TenantSlug to CtxData - it should override the fallback
		err := AddTenantSlug(ctx, "override-tenant-slug")
		require.NoError(t, err)

		retrievedTenantSlug = TenantSlug(ctx)
		require.Equal(t, "override-tenant-slug", retrievedTenantSlug)

		// Test with empty TenantSlug in CtxData - should fallback again
		err = AddTenantSlug(ctx, "")
		require.NoError(t, err)

		retrievedTenantSlug = TenantSlug(ctx)
		require.Equal(t, "fallback-tenant-slug", retrievedTenantSlug)
	})
}

func TestStatsTags_Complete(t *testing.T) {
	t.Run("all stats tags are properly included when all data is present", func(t *testing.T) {
		ctx := context.Background()
		ctx = AddData(ctx, &CtxData{})

		// Set up all test data
		userID := uint64(123456789)
		repoID := int64(987654321)
		issueID := int64(555666777)
		prID := int64(111222333)

		hydroEvent := HydroEvent{
			Topic:      "test.topic.name",
			Offset:     12345,
			Partition:  7,
			EnvelopeID: "envelope-123",
		}

		aqueductJob := &CtxAqueductJob{
			Queue:           "test-queue",
			ID:              "job-123",
			DeliveryAttempt: 2,
		}

		// Add all context data
		err := AddUser(ctx, &UserInfo{ID: userID, Login: "testuser", TrackingID: "tracking-id"})
		require.NoError(t, err)
		err = AddRepo(ctx, CtxRepo{ID: repoID})
		require.NoError(t, err)
		err = AddIssue(ctx, CtxIssue{ID: issueID})
		require.NoError(t, err)
		err = AddPullRequest(ctx, CtxPullRequest{ID: &prID, Number: 42})
		require.NoError(t, err)
		err = AddHydroMessage(ctx, hydroEvent)
		require.NoError(t, err)
		err = AddAqueductJob(ctx, aqueductJob)
		require.NoError(t, err)

		// Create HTTP request for stats tags
		req, _ := http.NewRequest(http.MethodPost, "/test/endpoint", http.NoBody)

		// Get stats tags
		tags := statsTags(ctx, req)

		// Verify HydroMessage tags
		require.Equal(t, "test.topic.name", tags["topic"], "topic tag should match HydroEvent topic")
		require.Equal(t, "7", tags["partition"], "partition tag should match HydroEvent partition as string")

		// Verify AqueductJob tags
		require.Equal(t, "test-queue", tags["aqueduct.queue"], "aqueduct.queue tag should match AqueductJob queue")
		require.Equal(t, "2", tags["aqueduct.delivery_attempt"], "aqueduct.delivery_attempt tag should match AqueductJob delivery attempt as string")

		// Verify bucketed ID tags
		expectedUserBucket := bucketUInt64(userID)
		require.Equal(t, fmt.Sprintf("%d", expectedUserBucket), tags["user_bucket"], "user_bucket should match bucketUInt64 output")

		expectedRepoBucket := bucketInt64(repoID)
		require.Equal(t, fmt.Sprintf("%d", expectedRepoBucket), tags["repo_bucket"], "repo_bucket should match bucketInt64 output")

		expectedIssueBucket := bucketInt64(issueID)
		require.Equal(t, fmt.Sprintf("%d", expectedIssueBucket), tags["issue_bucket"], "issue_bucket should match bucketInt64 output")

		expectedPRBucket := bucketInt64(prID)
		require.Equal(t, fmt.Sprintf("%d", expectedPRBucket), tags["pr_bucket"], "pr_bucket should match bucketInt64 output")

		// Verify HTTP request tags
		require.Equal(t, "POST", tags["http.request.method"], "http.request.method should match request method")
		require.NotEmpty(t, tags["url.route"], "url.route should be present and non-empty")

		// Verify all buckets are within expected range
		require.Less(t, expectedUserBucket, numberOfStatsBucketsToCoarsenTo, "User bucket should be coarsened")
		require.Less(t, expectedRepoBucket, numberOfStatsBucketsToCoarsenTo, "Repo bucket should be coarsened")
		require.Less(t, expectedIssueBucket, numberOfStatsBucketsToCoarsenTo, "Issue bucket should be coarsened")
		require.Less(t, expectedPRBucket, numberOfStatsBucketsToCoarsenTo, "PR bucket should be coarsened")
	})

	t.Run("stats tags work correctly when some data is missing", func(t *testing.T) {
		ctx := context.Background()
		ctx = AddData(ctx, &CtxData{})

		// Only add a subset of data - user and repo, no hydro message, no aqueduct job, no issue, PR with nil ID
		userID := uint64(456789123)
		repoID := int64(789123456)

		err := AddUser(ctx, &UserInfo{ID: userID, Login: "testuser2", TrackingID: "tracking-id-2"})
		require.NoError(t, err)
		err = AddRepo(ctx, CtxRepo{ID: repoID})
		require.NoError(t, err)
		err = AddPullRequest(ctx, CtxPullRequest{ID: nil, Number: 99}) // PR with nil ID
		require.NoError(t, err)

		// Get stats tags without HTTP request
		tags := statsTags(ctx, nil)

		// Verify present tags
		expectedUserBucket := bucketUInt64(userID)
		require.Equal(t, fmt.Sprintf("%d", expectedUserBucket), tags["user_bucket"], "user_bucket should be present")

		expectedRepoBucket := bucketInt64(repoID)
		require.Equal(t, fmt.Sprintf("%d", expectedRepoBucket), tags["repo_bucket"], "repo_bucket should be present")

		// Verify missing tags are not present
		_, exists := tags["topic"]
		require.False(t, exists, "topic tag should not exist when no HydroMessage")

		_, exists = tags["partition"]
		require.False(t, exists, "partition tag should not exist when no HydroMessage")

		_, exists = tags["aqueduct.queue"]
		require.False(t, exists, "aqueduct.queue tag should not exist when no AqueductJob")

		_, exists = tags["issue_bucket"]
		require.False(t, exists, "issue_bucket tag should not exist when no Issue")

		_, exists = tags["pr_bucket"]
		require.False(t, exists, "pr_bucket tag should not exist when PR ID is nil")

		_, exists = tags["http.request.method"]
		require.False(t, exists, "http.request.method tag should not exist when no HTTP request")

		_, exists = tags["url.route"]
		require.False(t, exists, "url.route tag should not exist when no HTTP request")

		// Verify buckets are still within expected range
		require.Less(t, expectedUserBucket, numberOfStatsBucketsToCoarsenTo, "User bucket should be coarsened")
		require.Less(t, expectedRepoBucket, numberOfStatsBucketsToCoarsenTo, "Repo bucket should be coarsened")
	})
}

func TestStatsTags_AgentSlug(t *testing.T) {
	t.Run("agent_slug included when EmitAgentSlugStats is true and slug is set", func(t *testing.T) {
		ctx := context.Background()
		ctx = AddData(ctx, &CtxData{})

		err := AddJob(ctx, &CtxJob{
			ID:                 "job-1",
			Agent:              CtxAgent{ID: 1, Slug: "copilot"},
			EmitAgentSlugStats: true,
		})
		require.NoError(t, err)

		tags := statsTags(ctx, nil)
		require.Equal(t, "copilot", tags["agent_slug"])
	})

	t.Run("agent_slug absent when EmitAgentSlugStats is false", func(t *testing.T) {
		ctx := context.Background()
		ctx = AddData(ctx, &CtxData{})

		err := AddJob(ctx, &CtxJob{
			ID:                 "job-2",
			Agent:              CtxAgent{ID: 1, Slug: "copilot"},
			EmitAgentSlugStats: false,
		})
		require.NoError(t, err)

		tags := statsTags(ctx, nil)
		_, exists := tags["agent_slug"]
		require.False(t, exists, "agent_slug should not be present when EmitAgentSlugStats is false")
	})

	t.Run("agent_slug absent when slug is empty", func(t *testing.T) {
		ctx := context.Background()
		ctx = AddData(ctx, &CtxData{})

		err := AddJob(ctx, &CtxJob{
			ID:                 "job-3",
			Agent:              CtxAgent{ID: 1},
			EmitAgentSlugStats: true,
		})
		require.NoError(t, err)

		tags := statsTags(ctx, nil)
		_, exists := tags["agent_slug"]
		require.False(t, exists, "agent_slug should not be present when slug is empty")
	})

	t.Run("agent_slug included from top-level CtxAgent when set", func(t *testing.T) {
		ctx := context.Background()
		ctx = AddData(ctx, &CtxData{})

		err := AddAgent(ctx, &CtxAgent{ID: 1, Slug: "copilot"})
		require.NoError(t, err)

		tags := statsTags(ctx, nil)
		require.Equal(t, "copilot", tags["agent_slug"])
	})

	t.Run("agent_slug from top-level CtxAgent does not require job context", func(t *testing.T) {
		ctx := context.Background()
		ctx = AddData(ctx, &CtxData{})

		err := AddAgent(ctx, &CtxAgent{Slug: "copilot-pull-request-reviewer"})
		require.NoError(t, err)

		tags := statsTags(ctx, nil)
		require.Equal(t, "copilot-pull-request-reviewer", tags["agent_slug"])
	})

	t.Run("agent_slug from CtxJob.Agent takes precedence over top-level CtxAgent", func(t *testing.T) {
		ctx := context.Background()
		ctx = AddData(ctx, &CtxData{})

		err := AddAgent(ctx, &CtxAgent{Slug: "copilot"})
		require.NoError(t, err)
		err = AddJob(ctx, &CtxJob{
			ID:                 "job-4",
			Agent:              CtxAgent{Slug: "stale-slug"},
			EmitAgentSlugStats: true,
		})
		require.NoError(t, err)

		tags := statsTags(ctx, nil)
		require.Equal(t, "stale-slug", tags["agent_slug"])
	})

	t.Run("agent_slug absent when top-level slug empty and no CtxJob", func(t *testing.T) {
		ctx := context.Background()
		ctx = AddData(ctx, &CtxData{})

		err := AddAgent(ctx, &CtxAgent{ID: 42})
		require.NoError(t, err)

		tags := statsTags(ctx, nil)
		_, exists := tags["agent_slug"]
		require.False(t, exists, "agent_slug should not be present when top-level slug is empty and no job")
	})
}

func TestLogFields_IntegrationInfo(t *testing.T) {
	t.Run("integration ID and type are included when TokenInfo is present", func(t *testing.T) {
		ctx := context.Background()
		ctx = AddData(ctx, &CtxData{})

		// Set up test data with TokenInfo
		userID := uint64(123456789)
		applicationID := uint64(987654321)
		applicationType := "oauth_app"

		err := AddUser(ctx, &UserInfo{
			ID:         userID,
			Login:      "testuser",
			TrackingID: "tracking-id",
			TokenInfo: &TokenInfo{
				ApplicationID:   applicationID,
				ApplicationType: applicationType,
				Type:            "oauth_token",
			},
		})
		require.NoError(t, err)

		// Get log fields
		_, _, logKvps := ToTelemetry(ctx, nil)

		// Convert to set of keys for easier testing
		keys := make(map[string]bool)
		for _, kvp := range logKvps {
			keys[kvp.Key] = true
		}

		// Verify integration information is present
		require.True(t, keys["gh.actor.integration_id"], "gh.actor.integration_id should be present")
		require.True(t, keys["gh.actor.integration_type"], "gh.actor.integration_type should be present")

		// Verify existing fields are still present
		require.True(t, keys["gh.actor.id"], "gh.actor.id should be present")
		require.True(t, keys["gh.actor.tracking_id"], "gh.actor.tracking_id should be present")
	})

	t.Run("integration fields are not included when TokenInfo is nil", func(t *testing.T) {
		ctx := context.Background()
		ctx = AddData(ctx, &CtxData{})

		// Set up test data without TokenInfo
		userID := uint64(123456789)

		err := AddUser(ctx, &UserInfo{
			ID:         userID,
			Login:      "testuser",
			TrackingID: "tracking-id",
			TokenInfo:  nil, // No token info
		})
		require.NoError(t, err)

		// Get log fields
		_, _, logKvps := ToTelemetry(ctx, nil)

		// Convert to set of keys for easier testing
		keys := make(map[string]bool)
		for _, kvp := range logKvps {
			keys[kvp.Key] = true
		}

		// Verify integration information is NOT present
		require.False(t, keys["gh.actor.integration_id"], "gh.actor.integration_id should not be present")
		require.False(t, keys["gh.actor.integration_type"], "gh.actor.integration_type should not be present")

		// Verify existing fields are still present
		require.True(t, keys["gh.actor.id"], "gh.actor.id should be present")
		require.True(t, keys["gh.actor.tracking_id"], "gh.actor.tracking_id should be present")
	})

	t.Run("integration fields are not included when user is not present", func(t *testing.T) {
		ctx := context.Background()
		ctx = AddData(ctx, &CtxData{})

		// Don't add any user info

		// Get log fields
		_, _, logKvps := ToTelemetry(ctx, nil)

		// Convert to set of keys for easier testing
		keys := make(map[string]bool)
		for _, kvp := range logKvps {
			keys[kvp.Key] = true
		}

		// Verify no user-related fields are present
		require.False(t, keys["gh.actor.id"], "gh.actor.id should not be present")
		require.False(t, keys["gh.actor.tracking_id"], "gh.actor.tracking_id should not be present")
		require.False(t, keys["gh.actor.integration_id"], "gh.actor.integration_id should not be present")
		require.False(t, keys["gh.actor.integration_type"], "gh.actor.integration_type should not be present")
	})
}

func TestLogFields_HTTPRequest(t *testing.T) {
	t.Run("http request fields including url.route are present when request is provided", func(t *testing.T) {
		ctx := context.Background()
		ctx = AddData(ctx, &CtxData{})

		// Create HTTP request
		req, _ := http.NewRequest(http.MethodPost, "/jobs/owner/repo", http.NoBody)

		// Get log fields
		_, _, logKvps := ToTelemetry(ctx, req)

		// Convert to map for easier testing
		fields := make(map[string]string)
		for _, kvp := range logKvps {
			fields[kvp.Key] = kvp.String
		}

		// Verify HTTP request fields are present with expected values
		require.Equal(t, "POST", fields["http.request.method"], "http.request.method should be POST")
		require.Equal(t, "/jobs/owner/repo", fields["url.path"], "url.path should match request path")
		require.Equal(t, "unknownroute", fields["url.route"], "url.route should be unknownroute when chi router context is not available")
		// user_agent.original should be present (even if empty string)
		_, hasUserAgent := fields["user_agent.original"]
		require.True(t, hasUserAgent, "user_agent.original field should be present")
	})

	t.Run("http request fields are not present when request is nil", func(t *testing.T) {
		ctx := context.Background()
		ctx = AddData(ctx, &CtxData{})

		// Get log fields without HTTP request
		_, _, logKvps := ToTelemetry(ctx, nil)

		// Convert to set of keys for easier testing
		keys := make(map[string]bool)
		for _, kvp := range logKvps {
			keys[kvp.Key] = true
		}

		// Verify HTTP request fields are NOT present
		require.False(t, keys["http.request.method"], "http.request.method should not be present")
		require.False(t, keys["url.path"], "url.path should not be present")
		require.False(t, keys["url.route"], "url.route should not be present")
		require.False(t, keys["user_agent.original"], "user_agent.original should not be present")
	})
}

func TestLogFields_AqueductJob(t *testing.T) {
	t.Run("aqueduct job fields are present when aqueduct job is added to context", func(t *testing.T) {
		ctx := context.Background()
		ctx = AddData(ctx, &CtxData{})

		now := time.Now()
		aqueductJob := &CtxAqueductJob{
			Queue:               "test-queue",
			ID:                  "job-123",
			DeliveryAttempt:     2,
			MaxDeliveryAttempts: 5,
			SentAt:              now,
			RequeueCount:        3,
		}

		err := AddAqueductJob(ctx, aqueductJob)
		require.NoError(t, err)

		// Get log fields
		logKvps := logFields(ctx, nil)

		// Convert to map for easier testing
		fields := make(map[string]string)
		for _, kvp := range logKvps {
			if kvp.String != "" {
				fields[kvp.Key] = kvp.String
			} else if kvp.Integer != 0 {
				fields[kvp.Key] = fmt.Sprintf("%d", kvp.Integer)
			}
		}

		// Verify AqueductJob fields
		require.Equal(t, "job-123", fields["aqueduct.job.id"], "aqueduct.job.id tag should match AqueductJob ID")
		require.Equal(t, "test-queue", fields["aqueduct.job.queue"], "aqueduct.job.queue tag should match AqueductJob queue")
		require.Equal(t, "2", fields["aqueduct.job.delivery_attempt"], "aqueduct.job.delivery_attempt tag should match AqueductJob delivery attempt as string")
		require.Equal(t, "5", fields["aqueduct.job.max_delivery_attempts"], "aqueduct.job.max_delivery_attempts tag should match AqueductJob max delivery attempts as string")
		require.Equal(t, "3", fields["aqueduct.job.requeue_count"], "aqueduct.job.requeue_count tag should match AqueductJob requeue count as string")
		require.Equal(t, now.Format(time.RFC3339), fields["aqueduct.job.sent_at"], "aqueduct.job.sent_at tag should match AqueductJob sent at time")
	})
}

func TestLogFields_RequestStartedAt(t *testing.T) {
	ctx := context.Background()
	ctx = AddData(ctx, &CtxData{})

	startedAt := time.Date(2026, time.January, 27, 6, 12, 54, 0, time.UTC)
	err := AddRequestStartedAt(ctx, startedAt)
	require.NoError(t, err)

	logKvps := logFields(ctx, nil)

	fields := make(map[string]string)
	for _, kvp := range logKvps {
		if kvp.String != "" {
			fields[kvp.Key] = kvp.String
		}
	}

	require.Equal(t, startedAt.Format(time.RFC3339), fields["http.request.started_at"], "http.request.started_at should match request start time")
}

func TestExceptionTags_IntegrationInfo(t *testing.T) {
	t.Run("integration ID and type are included when TokenInfo is present", func(t *testing.T) {
		ctx := context.Background()
		ctx = AddData(ctx, &CtxData{})

		// Set up test data with TokenInfo
		userID := uint64(123456789)
		applicationID := uint64(987654321)
		applicationType := "oauth_app"

		err := AddUser(ctx, &UserInfo{
			ID:         userID,
			Login:      "testuser",
			TrackingID: "tracking-id",
			TokenInfo: &TokenInfo{
				ApplicationID:   applicationID,
				ApplicationType: applicationType,
				Type:            "oauth_token",
			},
		})
		require.NoError(t, err)

		// Get exception tags
		_, exceptionTags, _ := ToTelemetry(ctx, nil)

		// Verify integration information is present in exception tags (indexed by Sentry)
		require.Equal(t, fmt.Sprintf("%d", applicationID), exceptionTags["#gh.actor.integration_id"], "#gh.actor.integration_id should be present")
		require.Equal(t, applicationType, exceptionTags["#gh.actor.integration_type"], "#gh.actor.integration_type should be present")

		// Verify existing fields are still present
		require.Equal(t, fmt.Sprintf("%d", userID), exceptionTags["#gh.actor.id"], "#gh.actor.id should be present")
	})

	t.Run("integration fields are not included when TokenInfo is nil", func(t *testing.T) {
		ctx := context.Background()
		ctx = AddData(ctx, &CtxData{})

		// Set up test data without TokenInfo
		userID := uint64(123456789)

		err := AddUser(ctx, &UserInfo{
			ID:         userID,
			Login:      "testuser",
			TrackingID: "tracking-id",
			TokenInfo:  nil, // No token info
		})
		require.NoError(t, err)

		// Get exception tags
		_, exceptionTags, _ := ToTelemetry(ctx, nil)

		// Verify integration information is NOT present
		_, hasIntegrationID := exceptionTags["#gh.actor.integration_id"]
		require.False(t, hasIntegrationID, "#gh.actor.integration_id should not be present")
		_, hasIntegrationType := exceptionTags["#gh.actor.integration_type"]
		require.False(t, hasIntegrationType, "#gh.actor.integration_type should not be present")

		// Verify existing fields are still present
		require.Equal(t, fmt.Sprintf("%d", userID), exceptionTags["#gh.actor.id"], "#gh.actor.id should be present")
	})

	t.Run("integration fields are not included when user is not present", func(t *testing.T) {
		ctx := context.Background()
		ctx = AddData(ctx, &CtxData{})

		// Don't add any user info

		// Get exception tags
		_, exceptionTags, _ := ToTelemetry(ctx, nil)

		// Verify no user-related fields are present
		_, hasActorID := exceptionTags["#gh.actor.id"]
		require.False(t, hasActorID, "#gh.actor.id should not be present")
		_, hasIntegrationID := exceptionTags["#gh.actor.integration_id"]
		require.False(t, hasIntegrationID, "#gh.actor.integration_id should not be present")
		_, hasIntegrationType := exceptionTags["#gh.actor.integration_type"]
		require.False(t, hasIntegrationType, "#gh.actor.integration_type should not be present")
	})
}

func TestCustomAgent_Telemetry(t *testing.T) {
	t.Run("custom agent fields are included in exception tags and log fields", func(t *testing.T) {
		ctx := context.Background()
		ctx = AddData(ctx, &CtxData{})

		err := AddCustomAgent(ctx, &CtxCustomAgent{
			ID:      "agent-uuid-123",
			Name:    "my-agent",
			Path:    ".github/agents/my-agent.md",
			Scope:   "repository",
			RepoID:  42,
			OwnerID: 99,
			Version: "abc123",
		})
		require.NoError(t, err)

		_, exceptionTags, logKvps := ToTelemetry(ctx, nil)

		// Exception tags
		require.Equal(t, "agent-uuid-123", exceptionTags["#custom_agent.id"])
		require.Equal(t, "my-agent", exceptionTags["custom_agent.name"])
		require.Equal(t, ".github/agents/my-agent.md", exceptionTags["custom_agent.path"])
		require.Equal(t, "repository", exceptionTags["#custom_agent.scope"])
		require.Equal(t, "42", exceptionTags["#custom_agent.repo_id"])
		require.Equal(t, "99", exceptionTags["#custom_agent.owner_id"])

		// Log fields
		logKeys := make(map[string]bool)
		for _, kv := range logKvps {
			logKeys[kv.Key] = true
		}
		require.True(t, logKeys["custom_agent.id"])
		require.True(t, logKeys["custom_agent.name"])
		require.True(t, logKeys["custom_agent.path"])
		require.True(t, logKeys["custom_agent.scope"])
		require.True(t, logKeys["custom_agent.repo_id"])
		require.True(t, logKeys["custom_agent.owner_id"])
		require.True(t, logKeys["custom_agent.version"])
	})

	t.Run("empty custom agent fields are omitted", func(t *testing.T) {
		ctx := context.Background()
		ctx = AddData(ctx, &CtxData{})

		err := AddCustomAgent(ctx, &CtxCustomAgent{
			Name: "my-agent",
		})
		require.NoError(t, err)

		_, exceptionTags, logKvps := ToTelemetry(ctx, nil)

		// Only name should be present
		require.Equal(t, "my-agent", exceptionTags["custom_agent.name"])

		// Zero-value fields should be absent
		_, hasID := exceptionTags["#custom_agent.id"]
		require.False(t, hasID)
		_, hasPath := exceptionTags["custom_agent.path"]
		require.False(t, hasPath)
		_, hasScope := exceptionTags["#custom_agent.scope"]
		require.False(t, hasScope)
		_, hasRepoID := exceptionTags["#custom_agent.repo_id"]
		require.False(t, hasRepoID)
		_, hasOwnerID := exceptionTags["#custom_agent.owner_id"]
		require.False(t, hasOwnerID)

		logKeys := make(map[string]bool)
		for _, kv := range logKvps {
			logKeys[kv.Key] = true
		}
		require.True(t, logKeys["custom_agent.name"])
		require.False(t, logKeys["custom_agent.id"])
		require.False(t, logKeys["custom_agent.path"])
		require.False(t, logKeys["custom_agent.scope"])
		require.False(t, logKeys["custom_agent.repo_id"])
		require.False(t, logKeys["custom_agent.owner_id"])
		require.False(t, logKeys["custom_agent.version"])
	})

	t.Run("no custom agent fields when not set", func(t *testing.T) {
		ctx := context.Background()
		ctx = AddData(ctx, &CtxData{})

		_, exceptionTags, logKvps := ToTelemetry(ctx, nil)

		_, hasName := exceptionTags["custom_agent.name"]
		require.False(t, hasName)

		logKeys := make(map[string]bool)
		for _, kv := range logKvps {
			logKeys[kv.Key] = true
		}
		require.False(t, logKeys["custom_agent.name"])
	})

	t.Run("cleared custom agent removes fields", func(t *testing.T) {
		ctx := context.Background()
		ctx = AddData(ctx, &CtxData{})

		err := AddCustomAgent(ctx, &CtxCustomAgent{Name: "my-agent", RepoID: 42})
		require.NoError(t, err)

		// Clear it
		err = AddCustomAgent(ctx, nil)
		require.NoError(t, err)

		_, exceptionTags, logKvps := ToTelemetry(ctx, nil)

		_, hasName := exceptionTags["custom_agent.name"]
		require.False(t, hasName)

		logKeys := make(map[string]bool)
		for _, kv := range logKvps {
			logKeys[kv.Key] = true
		}
		require.False(t, logKeys["custom_agent.name"])
	})
}

func TestStatsTags_IntegrationClient(t *testing.T) {
	t.Run("integration_client is set from User-Agent for known client", func(t *testing.T) {
		ctx := context.Background()
		ctx = AddData(ctx, &CtxData{})

		req := httptest.NewRequest(http.MethodGet, "/test", http.NoBody)
		req.Header.Set("User-Agent", "GitHubCopilotChat/1.0.0")

		statsTags, _, _ := ToTelemetry(ctx, req)
		require.Equal(t, "GitHubCopilotChat", statsTags["integration_client"])
	})

	t.Run("integration_client is 'other' for unrecognized User-Agent", func(t *testing.T) {
		ctx := context.Background()
		ctx = AddData(ctx, &CtxData{})

		req := httptest.NewRequest(http.MethodGet, "/test", http.NoBody)
		req.Header.Set("User-Agent", "SomeUnknownClient/2.0")

		statsTags, _, _ := ToTelemetry(ctx, req)
		require.Equal(t, "SomeUnknownClient", statsTags["integration_client"])
	})

	t.Run("integration_client is absent when User-Agent is empty", func(t *testing.T) {
		ctx := context.Background()
		ctx = AddData(ctx, &CtxData{})

		req := httptest.NewRequest(http.MethodGet, "/test", http.NoBody)
		req.Header.Set("User-Agent", "")

		statsTags, _, _ := ToTelemetry(ctx, req)
		_, hasIntegrationClient := statsTags["integration_client"]
		require.False(t, hasIntegrationClient, "integration_client should not be present when User-Agent is empty")
	})

	t.Run("integration_client is absent when request is nil", func(t *testing.T) {
		ctx := context.Background()
		ctx = AddData(ctx, &CtxData{})

		statsTags, _, _ := ToTelemetry(ctx, nil)
		_, hasIntegrationClient := statsTags["integration_client"]
		require.False(t, hasIntegrationClient, "integration_client should not be present when request is nil")
	})

	t.Run("integration_client is available from context when request is nil", func(t *testing.T) {
		ctx := context.Background()
		ctx = AddData(ctx, &CtxData{})
		err := AddIntegrationClient(ctx, "GitHubCopilotChat/1.0.0")
		require.NoError(t, err)

		statsTags, _, _ := ToTelemetry(ctx, nil)
		require.Equal(t, "GitHubCopilotChat", statsTags["integration_client"])
	})

	t.Run("context integration_client takes precedence over request User-Agent", func(t *testing.T) {
		ctx := context.Background()
		ctx = AddData(ctx, &CtxData{})
		err := AddIntegrationClient(ctx, "GitHubCopilotChat/1.0.0")
		require.NoError(t, err)

		req := httptest.NewRequest(http.MethodGet, "/test", http.NoBody)
		req.Header.Set("User-Agent", "curl/8.5.0")

		statsTags, _, _ := ToTelemetry(ctx, req)
		require.Equal(t, "GitHubCopilotChat", statsTags["integration_client"])
	})
}

func TestParseClientFromUserAgent(t *testing.T) {
	tests := []struct {
		ua       string
		expected string
	}{
		{"GitHubCopilotChat/0.36.2", "GitHubCopilotChat"},
		{"GithubCopilot/1.409.0", "GithubCopilot"},
		{"VSCopilotClient/18.4.114.215", "VSCopilotClient"},
		{"copilot/0.0.355 (darwin v25.1.0)", "copilot"},
		{"github-mcp-server/remote-054c7bff", "github-mcp-server"},
		{"vscode-ai-foundry/0.18.0 some-id", "vscode-ai-foundry"},
		{"vscode-pull-request-github/0.122.1", "vscode-pull-request-github"},
		{"curl/8.5.0", "curl"},
		{"Go-http-client/1.1", "Go-http-client"},

		// Version stripping for UAs without '/'
		{"GitHub CLI 2.89.0", "GitHub CLI"},
		{"GitHub CLI v2.89.0", "GitHub CLI"},
		{"GitHub CLI 2.89.0 Agent/claude-code", "GitHub CLI Agent"},
		{"GitHub CLI 2.90.0 Agent/codex", "GitHub CLI Agent"},

		// No version to strip
		{"vscode-copilot-chat", "vscode-copilot-chat"},
		{"sweagentd", "sweagentd"},
		{"", ""},
	}

	for _, tt := range tests {
		t.Run(tt.ua, func(t *testing.T) {
			require.Equal(t, tt.expected, parseClientFromUserAgent(tt.ua))
		})
	}
}
