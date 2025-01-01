# typed: true
# frozen_string_literal: true

require "test_helper"

class MetricsPayloadBuilderTest < GitHub::TestCase
  fixtures do
    @payload_builder = SecretScanning::Models::React::MetricsPayloadBuilder.new.freeze
  end

  test "builds push protection metrics payload" do
    clojars_metadata = SecretScanning::Models::TokenMetadata.new(
      token_type: "CLOJARS_DEPLOY_TOKEN",
      slug: "clojars_deploy_token",
      label: "Clojars Deploy Token",
      provider: "Clojars",
    )

    adafruit_metadata = SecretScanning::Models::TokenMetadata.new(
      token_type: "ADAFRUIT_AIO_TOKEN",
      slug: "adafruit_io_key",
      label: "Adafruit IO Key",
      provider: "Adafruit"
    )

    aws_metadata = SecretScanning::Models::TokenMetadata.new(
      token_type:  "AWS_KEYID",
      slug: "aws_access_key_id",
      label: "Amazon AWS Access Key ID",
      provider: "Amazon AWS",
    )

    github_v1_metadata = SecretScanning::Models::TokenMetadata.new(
      token_type:  "GITHUB",
      slug: "github_personal_access_token",
      label: "GitHub Personal Access Token",
      provider: "Github",
    )

    github_v2_metadata = SecretScanning::Models::TokenMetadata.new(
      token_type:  "GITHUB_TOKEN_V2",
      slug: "github_personal_access_token",
      label: "GitHub Personal Access Token",
      provider: "Github",
    )

    blocks_by_token_type_counts = [
      SecretScanning::Models::TokenTypeCountMetric.new(
        count: 20,
        token_type: "GITHUB",
        token_metadata: github_v1_metadata,
      ),
      SecretScanning::Models::TokenTypeCountMetric.new(
        count: 12,
        token_type: "GITHUB_TOKEN_V2",
        token_metadata: github_v2_metadata,
      ),
      SecretScanning::Models::TokenTypeCountMetric.new(
        count: 1,
        token_type: "CLOJARS_DEPLOY_TOKEN",
        token_metadata: clojars_metadata,
      ),
      SecretScanning::Models::TokenTypeCountMetric.new(
        count: 3,
        token_type: "ADAFRUIT_AIO_KEY",
        token_metadata: adafruit_metadata,
      ),
      SecretScanning::Models::TokenTypeCountMetric.new(
        count: 15,
        token_type: "cp_1",
        token_metadata: SecretScanning::Models::TokenMetadata.new(
          token_type: "cp_1",
          slug: "hello_world",
          label: "hello world",
          provider: "CUSTOM_PATTERN"
        )
      ),
      SecretScanning::Models::TokenTypeCountMetric.new(
        count: 10,
        token_type: "TOKEN_WITH_NO_METADATA",
        token_metadata: nil
      ),
      SecretScanning::Models::TokenTypeCountMetric.new(
        count: 3,
        token_type: "AWS_KEYID",
        token_metadata: aws_metadata,
      ),
    ]

    blocks_by_repository_counts = [
      SecretScanning::Models::RepoCountMetric.new(
        count: 28,
        repo_id: 1,
        repo_name: "repo1",
      ),
      SecretScanning::Models::RepoCountMetric.new(
        count: 17,
        repo_id: 2,
        repo_name: "repo2",
      ),
      SecretScanning::Models::RepoCountMetric.new(
        count: 9,
        repo_id: 3,
        repo_name: "repo3",
      ),
      SecretScanning::Models::RepoCountMetric.new(
        count: 5,
        repo_id: 4,
        repo_name: "repo4",
      ),
      SecretScanning::Models::RepoCountMetric.new(
        count: 2,
        repo_id: 5,
        repo_name: "repo5",
      ),
    ]

    bypasses_by_token_type_counts = [
      SecretScanning::Models::TokenTypeCountMetric.new(
        count: 10,
        token_type: "GITHUB",
        token_metadata: github_v1_metadata,
      ),
      SecretScanning::Models::TokenTypeCountMetric.new(
        count: 35,
        token_type: "GITHUB_TOKEN_V2",
        token_metadata: github_v2_metadata,
      ),
      SecretScanning::Models::TokenTypeCountMetric.new(
        count: 10,
        token_type: "CLOJARS_DEPLOY_TOKEN",
        token_metadata: clojars_metadata,
      ),
      SecretScanning::Models::TokenTypeCountMetric.new(
        count: 15,
        token_type: "AWS_KEYID",
        token_metadata: aws_metadata,
      ),
      SecretScanning::Models::TokenTypeCountMetric.new(
        count: 15,
        token_type: "ADAFRUIT_AIO_KEY",
        token_metadata: adafruit_metadata,
      ),
      SecretScanning::Models::TokenTypeCountMetric.new(
        count: 30,
        token_type: "cp_1",
        token_metadata: SecretScanning::Models::TokenMetadata.new(
          token_type: "cp_1",
          slug: "hello_world",
          label: "hello world",
          provider: "CUSTOM_PATTERN"
        )
      ),
      SecretScanning::Models::TokenTypeCountMetric.new(
        count: 5,
        token_type: "TOKEN_WITH_NO_METADATA",
        token_metadata: nil
      ),
    ]

    bypasses_by_repository_counts = [
      SecretScanning::Models::RepoCountMetric.new(
        count: 17,
        repo_id: 1,
        repo_name: "repo1",
      ),
      SecretScanning::Models::RepoCountMetric.new(
        count: 12,
        repo_id: 2,
        repo_name: "repo2",
      ),
      SecretScanning::Models::RepoCountMetric.new(
        count: 10,
        repo_id: 3,
        repo_name: "repo3",
      ),
      SecretScanning::Models::RepoCountMetric.new(
        count: 7,
        repo_id: 4,
        repo_name: "repo4",
      ),
      SecretScanning::Models::RepoCountMetric.new(
        count: 5,
        repo_id: 5,
        repo_name: "repo5",
      ),
    ]

    bypasses_by_reason_counts = [
      SecretScanning::Models::BypassReasonCountMetric.new(
        count: 15,
        percent: 75,
        bypass_reason: :FALSE_POSITIVE
      ),
      SecretScanning::Models::BypassReasonCountMetric.new(
        count: 0,
        percent: 0,
        bypass_reason: :WILL_FIX_LATER
      ),
      SecretScanning::Models::BypassReasonCountMetric.new(
        count: 5,
        percent: 25,
        bypass_reason: :USED_IN_TESTS
      ),
    ]

    bypasses_by_request_status_counts = [
      SecretScanning::Models::BypassRequestStatusCountMetric.new(
        count: 3,
        percent: 43,
        bypass_request_status: :pending,
      ),
      SecretScanning::Models::BypassRequestStatusCountMetric.new(
        count: 2,
        percent: 29,
        bypass_request_status: :approved,
      ),
      SecretScanning::Models::BypassRequestStatusCountMetric.new(
        count: 1,
        percent: 14,
        bypass_request_status: :rejected,
      ),
      SecretScanning::Models::BypassRequestStatusCountMetric.new(
        count: 1,
        percent: 14,
        bypass_request_status: :cancelled,
      ),
    ]

    metrics = SecretScanning::Models::PushProtectionMetrics.new(
      total_block_count: 11,
      successful_block_count: 6,
      bypassed_alert_count: 5,
      bypass_requests_count: 7,
      mean_response_time: 78923,
      blocks_by_token_type_counts: blocks_by_token_type_counts,
      blocks_by_repository_counts: blocks_by_repository_counts,
      bypasses_by_token_type_counts: bypasses_by_token_type_counts,
      bypasses_by_repository_counts: bypasses_by_repository_counts,
      bypasses_by_reason_counts: bypasses_by_reason_counts,
      bypasses_by_request_status_counts: bypasses_by_request_status_counts,
    )
    result = @payload_builder.push_protection_metrics(metrics)

    # Only includes up to 4 items
    assert_equal 4, result[:blocks_by_token_type_counts].length
    assert_equal 4, result[:blocks_by_repository_counts].length
    assert_equal 4, result[:bypasses_by_token_type_counts].length
    assert_equal 4, result[:bypasses_by_repository_counts].length
    assert_equal 4, result[:bypasses_by_request_status_counts].length
    assert_equal(
      {
        total_blocks_count: 11,
        successful_blocks_count: 6,
        bypassed_alerts_count: 5,
        bypass_requests_count: 7,
        mean_response_time: 78923,
        blocks_by_token_type_counts: [
          {
            type: "TOKEN_TYPE",
            name: "GitHub Personal Access Token",
            slug: "github_personal_access_token",
            count: 32,
            is_custom_pattern: false,
            has_metadata: true,
          },
          {
            type: "TOKEN_TYPE",
            name: "hello world",
            slug: "hello_world",
            count: 15,
            is_custom_pattern: true,
            has_metadata: true,
          },
          {
            type: "TOKEN_TYPE",
            name: "TOKEN_WITH_NO_METADATA",
            slug: "TOKEN_WITH_NO_METADATA",
            count: 10,
            is_custom_pattern: false,
            has_metadata: false,
          },
          {
            type: "TOKEN_TYPE",
            name: "Adafruit IO Key",
            slug: "adafruit_io_key",
            count: 3,
            is_custom_pattern: false,
            has_metadata: true,
          },
        ],
        blocks_by_repository_counts: [
          {
            type: "REPOSITORY",
            name: "repo1",
            count: 28,
          },
          {
            type: "REPOSITORY",
            name: "repo2",
            count: 17,
          },
          {
            type: "REPOSITORY",
            name: "repo3",
            count: 9,
          },
          {
            type: "REPOSITORY",
            name: "repo4",
            count: 5,
          },
        ],
        bypasses_by_token_type_counts: [
          {
            type: "TOKEN_TYPE",
            name: "GitHub Personal Access Token",
            slug: "github_personal_access_token",
            count: 45,
            is_custom_pattern: false,
            has_metadata: true,
          },
          {
            type: "TOKEN_TYPE",
            name: "hello world",
            slug: "hello_world",
            count: 30,
            is_custom_pattern: true,
            has_metadata: true,
          },
          {
            type: "TOKEN_TYPE",
            name: "Adafruit IO Key",
            slug: "adafruit_io_key",
            count: 15,
            is_custom_pattern: false,
            has_metadata: true,
          },
          {
            type: "TOKEN_TYPE",
            name: "Amazon AWS Access Key ID",
            slug: "aws_access_key_id",
            count: 15,
            is_custom_pattern: false,
            has_metadata: true,
          },
        ],
        bypasses_by_repository_counts: [
          {
            type: "REPOSITORY",
            name: "repo1",
            count: 17,
          },
          {
            type: "REPOSITORY",
            name: "repo2",
            count: 12,
          },
          {
            type: "REPOSITORY",
            name: "repo3",
            count: 10,
          },
          {
            type: "REPOSITORY",
            name: "repo4",
            count: 7,
          },
        ],
        bypasses_by_reason_counts: [
          {
            type: "BYPASS_REASON",
            name: "False positives",
            count: 15,
            percent: 75,
          },
          {
            type: "BYPASS_REASON",
            name: "Fix later",
            count: 0,
            percent: 0,
          },
          {
            type: "BYPASS_REASON",
            name: "Used in tests",
            count: 5,
            percent: 25,
          }
        ],
        bypasses_by_request_status_counts: [
          {
            type: "BYPASS_REQUEST_STATUS",
            name: "Open",
            count: 3,
            percent: 43,
          },
          {
            type: "BYPASS_REQUEST_STATUS",
            name: "Approved",
            count: 2,
            percent: 29,
          },
          {
            type: "BYPASS_REQUEST_STATUS",
            name: "Rejected",
            count: 1,
            percent: 14,
          },
          {
            type: "BYPASS_REQUEST_STATUS",
            name: "Cancelled",
            count: 1,
            percent: 14,
          },
        ],
      },
      result
    )
  end
end
