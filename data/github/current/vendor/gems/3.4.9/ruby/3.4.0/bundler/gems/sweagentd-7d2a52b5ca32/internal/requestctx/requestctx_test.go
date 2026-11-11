package requestctx

import (
	"context"
	"fmt"
	"net/http"
	"testing"

	"github.com/github/go-http/v2/middleware/tenant"
	"github.com/stretchr/testify/require"
)

func TestBucketFunctions(t *testing.T) {
	tests := []struct {
		name                string
		bucketFunc          func(interface{}) uint64
		rangeTestCases      []interface{}
		consistencyTestCase interface{}
		distributionRange   []interface{}
	}{
		{
			name: "BucketUInt64",
			bucketFunc: func(input interface{}) uint64 {
				return bucketUInt64(input.(uint64))
			},
			rangeTestCases:      []interface{}{uint64(0), uint64(1), uint64(100), uint64(1000), uint64(10000), uint64(18446744073709551615)}, // max uint64
			consistencyTestCase: uint64(12345),
			distributionRange: func() []interface{} {
				var inputs []interface{}
				for i := uint64(0); i < 1000; i++ {
					inputs = append(inputs, i)
				}
				return inputs
			}(),
		},
		{
			name: "BucketInt64",
			bucketFunc: func(input interface{}) uint64 {
				return bucketInt64(input.(int64))
			},
			rangeTestCases:      []interface{}{int64(-9223372036854775808), int64(-1000), int64(-1), int64(0), int64(1), int64(1000), int64(9223372036854775807)}, // min and max int64
			consistencyTestCase: int64(-12345),
			distributionRange: func() []interface{} {
				var inputs []interface{}
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
					require.True(t, bucket < numberOfStatsBucketsToCoarsenTo,
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
	req, _ := http.NewRequest("POST", "/test", nil)

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

func TestBucketDistribution(t *testing.T) {
	t.Run("bucket distribution is reasonable", func(t *testing.T) {
		// Test that buckets are reasonably distributed across the range
		bucketCounts := make(map[uint64]int)

		// Generate buckets for a range of inputs
		for i := uint64(0); i < 10000; i++ {
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
			EnvelopeId: "envelope-123",
		}

		aqueductJob := &CtxAqueductJob{
			Queue: "test-queue",
			ID:    "job-123",
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
		req, _ := http.NewRequest("POST", "/test/endpoint", nil)

		// Get stats tags
		tags := statsTags(ctx, req)

		// Verify HydroMessage tags
		require.Equal(t, "test.topic.name", tags["topic"], "topic tag should match HydroEvent topic")
		require.Equal(t, "7", tags["partition"], "partition tag should match HydroEvent partition as string")

		// Verify AqueductJob tags
		require.Equal(t, "test-queue", tags["aqueduct.queue"], "aqueduct.queue tag should match AqueductJob queue")

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
		req, _ := http.NewRequest("POST", "/jobs/owner/repo", nil)

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
