# typed: true
# frozen_string_literal: true

require "test_helper"

class MetricsServiceTest < GitHub::TestCase
  ResponseMock = Struct.new(:data, :error)
  ResponseDataMock = Struct.new(
    :blocks_by_repository_counts,
    :blocks_by_token_type_counts,
    :bypassed_alerts,
    :bypassed_alerts_count,
    :open_alerts,
    :closed_alerts,
    :false_positive_alerts,
    :bypass_request_ids,
    :bypasses_by_reason_counts,
    :bypasses_by_repository_counts,
    :bypasses_by_token_type_counts,
    :counts,
    :next_cursor,
    :previous_cursor,
    :successful_blocks,
    :successful_blocks_count,
    :total_blocks,
    :total_blocks_count
  )

  fixtures do
    @business = create(:business)
    @org = create(:organization, business: @business)
    @team = create(:team, organization: @org, privacy: :closed)

    @user = create(:user)
    @repo1 = create(:repository, name: "repo1", owner: @org)
    @repo2 = create(:repository, name: "repo2", owner: @org)
    @deleted_repo = create(:repository, :soft_deleted, name: "repo3", owner: @org)
    @archived_repo = create(:repository, name: "repo4", owner: @org)
    @archived_repo.set_archived

    create(:soa_repository, repository: @repo1)
    create(:soa_repository, repository: @repo2)
    create(:soa_repository, repository: @deleted_repo)
    create(:soa_repository, repository: @archived_repo)

    @resource_owner = RuleEngine::RuleSuite.create!(repository: @repo1, ref_name: "refs/heads/main", before_oid: "before", after_oid: "after", actor: @user)
  end

  context "get_token_push_protection_metrics" do
    test "successful request (repo)" do
      metrics_response = ResponseMock.new(
        error: nil,
        data: ResponseDataMock.new(
          total_blocks: 5,
          successful_blocks: 3,
          bypassed_alerts: 2
        )
      )

      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_push_protection_metrics)
        .with(has_entries(owner_id: @repo1.id, owner_scope: GitHub::Proto::SecretScanning::Api::V1::OwnerScope::REPOSITORY_SCOPE, token_type: "AWS_SECRET"))
        .returns(metrics_response)

      result = SecretScanning::Services::MetricsService.get_token_push_protection_metrics("AWS_SECRET", @repo1, @user)
      refute result.nil?
      result = T.must(result)
      assert_equal 5, result.total_block_count
      assert_equal 3, result.successful_block_count
      assert_equal 2, result.bypassed_alert_count
    end

    test "successful request (org)" do
      metrics_response = ResponseMock.new(
        error: nil,
        data: ResponseDataMock.new(
          total_blocks: 5,
          successful_blocks: 3,
          bypassed_alerts: 2
        )
      )

      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_push_protection_metrics)
        .with(has_entries(owner_id: @org.id, owner_scope: GitHub::Proto::SecretScanning::Api::V1::OwnerScope::ORGANIZATION_SCOPE, token_type: "AWS_SECRET"))
        .returns(metrics_response)

      result = SecretScanning::Services::MetricsService.get_token_push_protection_metrics("AWS_SECRET", @org, @user)
      refute result.nil?
      result = T.must(result)
      assert_equal 5, result.total_block_count
      assert_equal 3, result.successful_block_count
      assert_equal 2, result.bypassed_alert_count
    end

    test "successful request (business)" do
      metrics_response = ResponseMock.new(
        error: nil,
        data: ResponseDataMock.new(
          total_blocks: 5,
          successful_blocks: 3,
          bypassed_alerts: 2
        )
      )

      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_push_protection_metrics)
        .with(has_entries(owner_id: @business.id, owner_scope: GitHub::Proto::SecretScanning::Api::V1::OwnerScope::BUSINESS_SCOPE, token_type: "AWS_SECRET"))
        .returns(metrics_response)

      result = SecretScanning::Services::MetricsService.get_token_push_protection_metrics("AWS_SECRET", @business, @user)
      refute result.nil?
      result = T.must(result)
      assert_equal 5, result.total_block_count
      assert_equal 3, result.successful_block_count
      assert_equal 2, result.bypassed_alert_count
    end

    test "request failure returns nil" do
      metrics_response = ResponseMock.new(
        error: "Service unavailable",
        data: nil
      )

      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_push_protection_metrics).returns(metrics_response)

      result = SecretScanning::Services::MetricsService.get_token_push_protection_metrics("AWS_SECRET", @repo1, @user)
      assert result.nil?
    end
  end

  context "get_push_protection_metrics" do
    test "successful request (org)" do
      clojars_metadata = GitHub::Proto::SecretScanning::Types::V1::TokenMetadata.new(
        token_type: "CLOJARS_DEPLOY_TOKEN",
        slug: "clojars_deploy_token",
        label: "Clojars Deploy Token",
        provider: "Clojars",
      )

      adafruit_metadata = GitHub::Proto::SecretScanning::Types::V1::TokenMetadata.new(
        token_type: "ADAFRUIT_AIO_TOKEN",
        slug: "adafruit_aio_token",
        label: "Adafruit io token",
        provider: "Adafruit"
      )

      blocks_by_token_type_counts = [
        GitHub::Proto::SecretScanning::Metrics::V1::TokenTypeCount.new(
          count: 20,
          token_type: "CLOJARS_DEPLOY_TOKEN",
          token_metadata: clojars_metadata
        ),
        GitHub::Proto::SecretScanning::Metrics::V1::TokenTypeCount.new(
          count: 40,
          token_type: "ADAFRUIT_AIO_TOKEN",
          token_metadata: adafruit_metadata,
        ),
      ]

      blocks_by_repository_counts = [
        GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(
          repo_id: @repo1.id,
          count: 50,
        ),
        GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(
          repo_id: @repo2.id,
          count: 100,
        ),
      ]

      bypasses_by_token_type_counts = [
        GitHub::Proto::SecretScanning::Metrics::V1::TokenTypeCount.new(
          count: 10,
          token_type: "CLOJARS_DEPLOY_TOKEN",
          token_metadata: clojars_metadata
        ),
        GitHub::Proto::SecretScanning::Metrics::V1::TokenTypeCount.new(
          count: 15,
          token_type: "ADAFRUIT_AIO_TOKEN",
          token_metadata: adafruit_metadata,
        ),
      ]

      bypasses_by_repository_counts = [
        GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(
          repo_id: @repo1.id,
          count: 10,
        ),
        GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(
          repo_id: @repo2.id,
          count: 25,
        ),
      ]

      bypasses_by_reason_counts = [
        GitHub::Proto::SecretScanning::Metrics::V1::BypassReasonCount.new(
          bypass_reason: :FALSE_POSITIVE,
          count: 15,
        ),
        GitHub::Proto::SecretScanning::Metrics::V1::BypassReasonCount.new(
          bypass_reason: :WILL_FIX_LATER,
          count: 0,
        ),
        GitHub::Proto::SecretScanning::Metrics::V1::BypassReasonCount.new(
          bypass_reason: :USED_IN_TESTS,
          count: 5,
        ),
      ]

      push_protection_metrics_response = ResponseMock.new(
        error: nil,
        data: ResponseDataMock.new(
          total_blocks_count: 9,
          successful_blocks_count: 6,
          bypassed_alerts_count: 3,
          blocks_by_token_type_counts: blocks_by_token_type_counts,
          blocks_by_repository_counts: blocks_by_repository_counts,
          bypasses_by_token_type_counts: bypasses_by_token_type_counts,
          bypasses_by_repository_counts: bypasses_by_repository_counts,
          bypasses_by_reason_counts: bypasses_by_reason_counts,
        )
      )

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

      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_push_protection_metrics)
        .with(has_entries(
          owner_id: @org.id,
          owner_scope: GitHub::Proto::SecretScanning::Api::V1::OwnerScope::ORGANIZATION_SCOPE,
          repo_ids: [1, 2, 3]
        ))
        .returns(push_protection_metrics_response)

      SecretScanning::Services::MetricsService.expects(:get_delegated_bypass_metrics)
        .with(@org, @user, repo_ids: [1, 2, 3], exclude_repo_ids: [], repo_owners: nil, repos_in_archived_state: nil, start_date: nil, end_date: nil, token_filters: nil, bypass_request_ids: [])
        .returns([7, 78923, bypasses_by_request_status_counts])

      result, error = SecretScanning::Services::MetricsService.get_push_protection_metrics(@org, @user, repo_ids: [1, 2, 3])
      refute result.nil?
      refute error
      result = T.must(result)
      assert_equal 9, result.total_block_count
      assert_equal 6, result.successful_block_count
      assert_equal 3, result.bypassed_alert_count
      assert_equal 7, result.bypass_requests_count
      assert_equal 78923, result.mean_response_time

      assert_equal 2, result.blocks_by_token_type_counts.length
      assert_equal 20, result.blocks_by_token_type_counts[0]&.count
      assert_equal "CLOJARS_DEPLOY_TOKEN", result.blocks_by_token_type_counts[0]&.token_type
      refute result.blocks_by_token_type_counts[0]&.token_metadata.nil?
      assert_equal "CLOJARS_DEPLOY_TOKEN", result.blocks_by_token_type_counts[0]&.token_metadata&.token_type
      assert_equal "clojars_deploy_token", result.blocks_by_token_type_counts[0]&.token_metadata&.slug
      assert_equal "Clojars Deploy Token", result.blocks_by_token_type_counts[0]&.token_metadata&.label
      assert_equal "Clojars", result.blocks_by_token_type_counts[0]&.token_metadata&.provider
      assert_equal 40, result.blocks_by_token_type_counts[1]&.count
      assert_equal "ADAFRUIT_AIO_TOKEN", result.blocks_by_token_type_counts[1]&.token_type
      refute result.blocks_by_token_type_counts[1]&.token_metadata.nil?
      assert_equal "ADAFRUIT_AIO_TOKEN", result.blocks_by_token_type_counts[1]&.token_metadata&.token_type
      assert_equal "adafruit_aio_token", result.blocks_by_token_type_counts[1]&.token_metadata&.slug
      assert_equal "Adafruit io token", result.blocks_by_token_type_counts[1]&.token_metadata&.label
      assert_equal "Adafruit", result.blocks_by_token_type_counts[1]&.token_metadata&.provider

      assert_equal 2, result.blocks_by_repository_counts.length
      assert_equal @repo1.id, result.blocks_by_repository_counts[0]&.repo_id
      assert_equal "repo1", result.blocks_by_repository_counts[0]&.repo_name
      assert_equal 50, result.blocks_by_repository_counts[0]&.count
      assert_equal @repo2.id, result.blocks_by_repository_counts[1]&.repo_id
      assert_equal 100, result.blocks_by_repository_counts[1]&.count
      assert_equal "repo2", result.blocks_by_repository_counts[1]&.repo_name

      assert_equal 2, result.bypasses_by_token_type_counts.length
      assert_equal 10, result.bypasses_by_token_type_counts[0]&.count
      assert_equal "CLOJARS_DEPLOY_TOKEN", result.bypasses_by_token_type_counts[0]&.token_type
      refute result.bypasses_by_token_type_counts[0]&.token_metadata.nil?
      assert_equal "CLOJARS_DEPLOY_TOKEN", result.bypasses_by_token_type_counts[0]&.token_metadata&.token_type
      assert_equal "clojars_deploy_token", result.bypasses_by_token_type_counts[0]&.token_metadata&.slug
      assert_equal "Clojars Deploy Token", result.bypasses_by_token_type_counts[0]&.token_metadata&.label
      assert_equal "Clojars", result.bypasses_by_token_type_counts[0]&.token_metadata&.provider
      assert_equal 15, result.bypasses_by_token_type_counts[1]&.count
      assert_equal "ADAFRUIT_AIO_TOKEN", result.bypasses_by_token_type_counts[1]&.token_type
      refute result.bypasses_by_token_type_counts[1]&.token_metadata.nil?
      assert_equal "ADAFRUIT_AIO_TOKEN", result.bypasses_by_token_type_counts[1]&.token_metadata&.token_type
      assert_equal "adafruit_aio_token", result.bypasses_by_token_type_counts[1]&.token_metadata&.slug
      assert_equal "Adafruit io token", result.bypasses_by_token_type_counts[1]&.token_metadata&.label
      assert_equal "Adafruit", result.bypasses_by_token_type_counts[1]&.token_metadata&.provider

      assert_equal 2, result.bypasses_by_repository_counts.length
      assert_equal @repo1.id, result.bypasses_by_repository_counts[0]&.repo_id
      assert_equal "repo1", result.bypasses_by_repository_counts[0]&.repo_name
      assert_equal 10, result.bypasses_by_repository_counts[0]&.count
      assert_equal @repo2.id, result.bypasses_by_repository_counts[1]&.repo_id
      assert_equal 25, result.bypasses_by_repository_counts[1]&.count
      assert_equal "repo2", result.bypasses_by_repository_counts[1]&.repo_name

      assert_equal 3, result.bypasses_by_reason_counts.length
      assert_equal :FALSE_POSITIVE, result.bypasses_by_reason_counts[0]&.bypass_reason
      assert_equal 15, result.bypasses_by_reason_counts[0]&.count
      assert_equal 75, result.bypasses_by_reason_counts[0]&.percent
      assert_equal :WILL_FIX_LATER, result.bypasses_by_reason_counts[1]&.bypass_reason
      assert_equal 0, result.bypasses_by_reason_counts[1]&.count
      assert_equal 0, result.bypasses_by_reason_counts[1]&.percent
      assert_equal :USED_IN_TESTS, result.bypasses_by_reason_counts[2]&.bypass_reason
      assert_equal 5, result.bypasses_by_reason_counts[2]&.count
      assert_equal 25, result.bypasses_by_reason_counts[2]&.percent

      assert_equal 4, result.bypasses_by_request_status_counts.length
      assert_equal bypasses_by_request_status_counts, result.bypasses_by_request_status_counts
    end

    test "successful request (business)" do
      clojars_metadata = GitHub::Proto::SecretScanning::Types::V1::TokenMetadata.new(
        token_type: "CLOJARS_DEPLOY_TOKEN",
        slug: "clojars_deploy_token",
        label: "Clojars Deploy Token",
        provider: "Clojars",
      )

      adafruit_metadata = GitHub::Proto::SecretScanning::Types::V1::TokenMetadata.new(
        token_type: "ADAFRUIT_AIO_TOKEN",
        slug: "adafruit_aio_token",
        label: "Adafruit io token",
        provider: "Adafruit"
      )

      blocks_by_token_type_counts = [
        GitHub::Proto::SecretScanning::Metrics::V1::TokenTypeCount.new(
          count: 20,
          token_type: "CLOJARS_DEPLOY_TOKEN",
          token_metadata: clojars_metadata
        ),
        GitHub::Proto::SecretScanning::Metrics::V1::TokenTypeCount.new(
          count: 40,
          token_type: "ADAFRUIT_AIO_TOKEN",
          token_metadata: adafruit_metadata,
        ),
      ]

      blocks_by_repository_counts = [
        GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(
          repo_id: @repo1.id,
          count: 50,
        ),
        GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(
          repo_id: @repo2.id,
          count: 100,
        ),
      ]

      bypasses_by_token_type_counts = [
        GitHub::Proto::SecretScanning::Metrics::V1::TokenTypeCount.new(
          count: 10,
          token_type: "CLOJARS_DEPLOY_TOKEN",
          token_metadata: clojars_metadata
        ),
        GitHub::Proto::SecretScanning::Metrics::V1::TokenTypeCount.new(
          count: 15,
          token_type: "ADAFRUIT_AIO_TOKEN",
          token_metadata: adafruit_metadata,
        ),
      ]

      bypasses_by_repository_counts = [
        GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(
          repo_id: @repo1.id,
          count: 10,
        ),
        GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(
          repo_id: @repo2.id,
          count: 25,
        ),
      ]

      bypasses_by_reason_counts = [
        GitHub::Proto::SecretScanning::Metrics::V1::BypassReasonCount.new(
          bypass_reason: :FALSE_POSITIVE,
          count: 15,
        ),
        GitHub::Proto::SecretScanning::Metrics::V1::BypassReasonCount.new(
          bypass_reason: :WILL_FIX_LATER,
          count: 0,
        ),
        GitHub::Proto::SecretScanning::Metrics::V1::BypassReasonCount.new(
          bypass_reason: :USED_IN_TESTS,
          count: 5,
        ),
      ]

      push_protection_metrics_response = ResponseMock.new(
        error: nil,
        data: ResponseDataMock.new(
          total_blocks_count: 9,
          successful_blocks_count: 6,
          bypassed_alerts_count: 3,
          blocks_by_token_type_counts: blocks_by_token_type_counts,
          blocks_by_repository_counts: blocks_by_repository_counts,
          bypasses_by_token_type_counts: bypasses_by_token_type_counts,
          bypasses_by_repository_counts: bypasses_by_repository_counts,
          bypasses_by_reason_counts: bypasses_by_reason_counts,
        )
      )

      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_push_protection_metrics)
        .with(has_entries(
          owner_id: @business.id,
          owner_scope: GitHub::Proto::SecretScanning::Api::V1::OwnerScope::BUSINESS_SCOPE,
          repo_ids: [1, 2, 3]
        ))
        .returns(push_protection_metrics_response)

      result, error = SecretScanning::Services::MetricsService.get_push_protection_metrics(@business, @user, repo_ids: [1, 2, 3])
      refute result.nil?
      refute error
      result = T.must(result)
      assert_equal 9, result.total_block_count
      assert_equal 6, result.successful_block_count
      assert_equal 3, result.bypassed_alert_count

      assert_equal 2, result.blocks_by_token_type_counts.length
      assert_equal 20, result.blocks_by_token_type_counts[0]&.count
      assert_equal "CLOJARS_DEPLOY_TOKEN", result.blocks_by_token_type_counts[0]&.token_type
      refute result.blocks_by_token_type_counts[0]&.token_metadata.nil?
      assert_equal "CLOJARS_DEPLOY_TOKEN", result.blocks_by_token_type_counts[0]&.token_metadata&.token_type
      assert_equal "clojars_deploy_token", result.blocks_by_token_type_counts[0]&.token_metadata&.slug
      assert_equal "Clojars Deploy Token", result.blocks_by_token_type_counts[0]&.token_metadata&.label
      assert_equal "Clojars", result.blocks_by_token_type_counts[0]&.token_metadata&.provider
      assert_equal 40, result.blocks_by_token_type_counts[1]&.count
      assert_equal "ADAFRUIT_AIO_TOKEN", result.blocks_by_token_type_counts[1]&.token_type
      refute result.blocks_by_token_type_counts[1]&.token_metadata.nil?
      assert_equal "ADAFRUIT_AIO_TOKEN", result.blocks_by_token_type_counts[1]&.token_metadata&.token_type
      assert_equal "adafruit_aio_token", result.blocks_by_token_type_counts[1]&.token_metadata&.slug
      assert_equal "Adafruit io token", result.blocks_by_token_type_counts[1]&.token_metadata&.label
      assert_equal "Adafruit", result.blocks_by_token_type_counts[1]&.token_metadata&.provider

      assert_equal 2, result.blocks_by_repository_counts.length
      assert_equal @repo1.id, result.blocks_by_repository_counts[0]&.repo_id
      assert_equal @repo1.name_with_display_owner, result.blocks_by_repository_counts[0]&.repo_name
      assert_equal 50, result.blocks_by_repository_counts[0]&.count
      assert_equal @repo2.id, result.blocks_by_repository_counts[1]&.repo_id
      assert_equal 100, result.blocks_by_repository_counts[1]&.count
      assert_equal @repo2.name_with_display_owner, result.blocks_by_repository_counts[1]&.repo_name

      assert_equal 2, result.bypasses_by_token_type_counts.length
      assert_equal 10, result.bypasses_by_token_type_counts[0]&.count
      assert_equal "CLOJARS_DEPLOY_TOKEN", result.bypasses_by_token_type_counts[0]&.token_type
      refute result.bypasses_by_token_type_counts[0]&.token_metadata.nil?
      assert_equal "CLOJARS_DEPLOY_TOKEN", result.bypasses_by_token_type_counts[0]&.token_metadata&.token_type
      assert_equal "clojars_deploy_token", result.bypasses_by_token_type_counts[0]&.token_metadata&.slug
      assert_equal "Clojars Deploy Token", result.bypasses_by_token_type_counts[0]&.token_metadata&.label
      assert_equal "Clojars", result.bypasses_by_token_type_counts[0]&.token_metadata&.provider
      assert_equal 15, result.bypasses_by_token_type_counts[1]&.count
      assert_equal "ADAFRUIT_AIO_TOKEN", result.bypasses_by_token_type_counts[1]&.token_type
      refute result.bypasses_by_token_type_counts[1]&.token_metadata.nil?
      assert_equal "ADAFRUIT_AIO_TOKEN", result.bypasses_by_token_type_counts[1]&.token_metadata&.token_type
      assert_equal "adafruit_aio_token", result.bypasses_by_token_type_counts[1]&.token_metadata&.slug
      assert_equal "Adafruit io token", result.bypasses_by_token_type_counts[1]&.token_metadata&.label
      assert_equal "Adafruit", result.bypasses_by_token_type_counts[1]&.token_metadata&.provider

      assert_equal 2, result.bypasses_by_repository_counts.length
      assert_equal @repo1.id, result.bypasses_by_repository_counts[0]&.repo_id
      assert_equal @repo1.name_with_display_owner, result.bypasses_by_repository_counts[0]&.repo_name
      assert_equal 10, result.bypasses_by_repository_counts[0]&.count
      assert_equal @repo2.id, result.bypasses_by_repository_counts[1]&.repo_id
      assert_equal 25, result.bypasses_by_repository_counts[1]&.count
      assert_equal @repo2.name_with_display_owner, result.bypasses_by_repository_counts[1]&.repo_name

      assert_equal 3, result.bypasses_by_reason_counts.length
      assert_equal :FALSE_POSITIVE, result.bypasses_by_reason_counts[0]&.bypass_reason
      assert_equal 15, result.bypasses_by_reason_counts[0]&.count
      assert_equal 75, result.bypasses_by_reason_counts[0]&.percent
      assert_equal :WILL_FIX_LATER, result.bypasses_by_reason_counts[1]&.bypass_reason
      assert_equal 0, result.bypasses_by_reason_counts[1]&.count
      assert_equal 0, result.bypasses_by_reason_counts[1]&.percent
      assert_equal :USED_IN_TESTS, result.bypasses_by_reason_counts[2]&.bypass_reason
      assert_equal 5, result.bypasses_by_reason_counts[2]&.count
      assert_equal 25, result.bypasses_by_reason_counts[2]&.percent
    end

    test "counts by repository do not include repos that don't exist" do
      blocks_by_repository_counts = [
        GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(
          repo_id: @repo1.id,
          count: 50,
        ),
        GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(
          repo_id: @repo2.id,
          count: 100,
        ),
        GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(
          repo_id: 1234567, # this repo shouldn't show up as it doesn't exist
          count: 15,
        ),
      ]

      bypasses_by_repository_counts = [
        GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(
          repo_id: @repo1.id,
          count: 10,
        ),
        GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(
          repo_id: @repo2.id,
          count: 25,
        ),
        GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(
          repo_id: 1234567, # this repo shouldn't show up as it doesn't exist
          count: 15,
        ),
      ]

      push_protection_metrics_response = ResponseMock.new(
        error: nil,
        data: ResponseDataMock.new(
          total_blocks_count: 9,
          successful_blocks_count: 6,
          bypassed_alerts_count: 3,
          blocks_by_token_type_counts: [],
          blocks_by_repository_counts: blocks_by_repository_counts,
          bypasses_by_token_type_counts: [],
          bypasses_by_repository_counts: bypasses_by_repository_counts,
        )
      )

      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_push_protection_metrics)
        .with(has_entries(owner_id: @org.id, owner_scope: GitHub::Proto::SecretScanning::Api::V1::OwnerScope::ORGANIZATION_SCOPE))
        .returns(push_protection_metrics_response)

      result, error = SecretScanning::Services::MetricsService.get_push_protection_metrics(@org, @user)
      refute result.nil?
      refute error
      result = T.must(result)

      assert_equal 2, result.blocks_by_repository_counts.length
      assert_equal @repo1.id, result.blocks_by_repository_counts[0]&.repo_id
      assert_equal @repo2.id, result.blocks_by_repository_counts[1]&.repo_id

      assert_equal 2, result.bypasses_by_repository_counts.length
      assert_equal @repo1.id, result.bypasses_by_repository_counts[0]&.repo_id
      assert_equal @repo2.id, result.bypasses_by_repository_counts[1]&.repo_id
    end

    test "counts by repository does not include deleted repos" do
      assert @deleted_repo.deleted?

      blocks_by_repository_counts = [
        GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(
          repo_id: @repo1.id,
          count: 50,
        ),
        GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(
          repo_id: @deleted_repo.id,
          count: 100,
        ),
      ]

      bypasses_by_repository_counts = [
        GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(
          repo_id: @repo1.id,
          count: 10,
        ),
        GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(
          repo_id: @deleted_repo.id,
          count: 25,
        ),
      ]

      push_protection_metrics_response = ResponseMock.new(
        error: nil,
        data: ResponseDataMock.new(
          total_blocks_count: 9,
          successful_blocks_count: 6,
          bypassed_alerts_count: 3,
          blocks_by_token_type_counts: [],
          blocks_by_repository_counts: blocks_by_repository_counts,
          bypasses_by_token_type_counts: [],
          bypasses_by_repository_counts: bypasses_by_repository_counts,
        )
      )

      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_push_protection_metrics)
        .with(has_entries(owner_id: @org.id, owner_scope: GitHub::Proto::SecretScanning::Api::V1::OwnerScope::ORGANIZATION_SCOPE))
        .returns(push_protection_metrics_response)

      result, error = SecretScanning::Services::MetricsService.get_push_protection_metrics(@org, @user)
      refute result.nil?
      refute error
      result = T.must(result)

      assert_equal 1, result.blocks_by_repository_counts.length
      assert_equal @repo1.id, result.blocks_by_repository_counts[0]&.repo_id

      assert_equal 1, result.bypasses_by_repository_counts.length
      assert_equal @repo1.id, result.bypasses_by_repository_counts[0]&.repo_id
    end

    context "with repository ids" do
      context "when omitted" do
        test "passes empty repository ids to the request" do
          GitHub::TokenScanning::Service::Client
            .any_instance
            .expects(:get_push_protection_metrics)
            .once
            .with(has_entries({
              repo_ids: [],
              exclude_repo_ids: []
            }))
            .returns(
              ResponseMock.new(
                error: nil,
                data: ResponseDataMock.new(
                  total_blocks_count: 1,
                  successful_blocks_count: 2,
                  bypassed_alerts_count: 3
                )
              )
            )

          result, error = SecretScanning::Services::MetricsService.get_push_protection_metrics(@business, @user)

          refute error
          assert_kind_of SecretScanning::Models::PushProtectionMetrics, result
          assert_equal 1, T.must(result).total_block_count
          assert_equal 2, T.must(result).successful_block_count
          assert_equal 3, T.must(result).bypassed_alert_count
        end
      end

      context "when provided" do
        test "passes the same repo ids input to the request" do
          GitHub::TokenScanning::Service::Client
            .any_instance
            .expects(:get_push_protection_metrics)
            .once
            .with(has_entries({
              repo_ids: [1, 2, 3],
              exclude_repo_ids: [2, 4]
            }))
            .returns(
              ResponseMock.new(
                error: nil,
                data: ResponseDataMock.new(
                  total_blocks_count: 1,
                  successful_blocks_count: 2,
                  bypassed_alerts_count: 3
                )
              )
            )

          result, err = SecretScanning::Services::MetricsService.get_push_protection_metrics(
            @business,
            @user,
            repo_ids: [1, 2, 3],
            exclude_repo_ids: [2, 4]
          )

          assert_kind_of SecretScanning::Models::PushProtectionMetrics, result
          assert_equal 1, T.must(result).total_block_count
          assert_equal 2, T.must(result).successful_block_count
          assert_equal 3, T.must(result).bypassed_alert_count
        end
      end
    end

    context "repo_owners" do
      context "when omitted" do
        test "omits repo_owners from the request when not provided" do
          GitHub::TokenScanning::Service::Client
            .any_instance
            .expects(:get_push_protection_metrics)
            .once
            .with(Not(has_key(:repo_owners)))
            .returns(
              ResponseMock.new(
                error: nil,
                data: ResponseDataMock.new(
                  total_blocks_count: 1,
                  successful_blocks_count: 2,
                  bypassed_alerts_count: 3
                )
              )
            )

          result, error = SecretScanning::Services::MetricsService.get_push_protection_metrics(@business, @user)

          refute error
          assert_kind_of SecretScanning::Models::PushProtectionMetrics, result
          assert_equal 1, T.must(result).total_block_count
          assert_equal 2, T.must(result).successful_block_count
          assert_equal 3, T.must(result).bypassed_alert_count
        end
      end

      context "when provided" do
        test "queries all owners by default" do
          GitHub::TokenScanning::Service::Client
            .any_instance
            .expects(:get_push_protection_metrics)
            .once
            .with(has_entries({
              repo_owners: GitHub::Proto::SecretScanning::Api::V1::RepositoryOwners.new({
                filter_type: :ALL,
                org_ids: [],
                exclude_org_ids: [],
                user_ids: [],
                exclude_user_ids: [],
              })
            }))
            .returns(
              ResponseMock.new(
                error: nil,
                data: ResponseDataMock.new(
                  total_blocks_count: 1,
                  successful_blocks_count: 2,
                  bypassed_alerts_count: 3
                )
              )
            )

          result, error = SecretScanning::Services::MetricsService.get_push_protection_metrics(
            @business,
            @user,
            repo_owners: SecretScanning::Services::MetricsService::RepoOwnersFilters.new,
          )

          refute error
          assert_kind_of SecretScanning::Models::PushProtectionMetrics, result
          assert_equal 1, T.must(result).total_block_count
          assert_equal 2, T.must(result).successful_block_count
          assert_equal 3, T.must(result).bypassed_alert_count
        end

        test "queries using all provided owner IDs" do
          GitHub::TokenScanning::Service::Client
            .any_instance
            .expects(:get_push_protection_metrics)
            .once
            .with(has_entries({
              repo_owners: GitHub::Proto::SecretScanning::Api::V1::RepositoryOwners.new({
                filter_type: :ALL,
                org_ids: [1, 2, 3],
                exclude_org_ids: [2],
                user_ids: [4, 5, 6],
                exclude_user_ids: [5, 6],
              })
            }))
            .returns(
              ResponseMock.new(
                error: nil,
                data: ResponseDataMock.new(
                  total_blocks_count: 1,
                  successful_blocks_count: 2,
                  bypassed_alerts_count: 3
                )
              )
            )

          result, error = SecretScanning::Services::MetricsService.get_push_protection_metrics(
            @business,
            @user,
            repo_owners: SecretScanning::Services::MetricsService::RepoOwnersFilters.new(
              owner_type: SecretScanning::Services::MetricsService::RepoOwnerType::Any,
              org_ids: [1, 2, 3],
              exclude_org_ids: [2],
              user_ids: [4, 5, 6],
              exclude_user_ids: [5, 6],
            ),
          )

          refute error
          assert_kind_of SecretScanning::Models::PushProtectionMetrics, result
          assert_equal 1, T.must(result).total_block_count
          assert_equal 2, T.must(result).successful_block_count
          assert_equal 3, T.must(result).bypassed_alert_count
        end

        test "queries orgs when type is Organization" do
          GitHub::TokenScanning::Service::Client
            .any_instance
            .expects(:get_push_protection_metrics)
            .once
            .with(has_entries({
              repo_owners: GitHub::Proto::SecretScanning::Api::V1::RepositoryOwners.new({
                filter_type: :ORGANIZATION,
                org_ids: [],
                exclude_org_ids: [],
                user_ids: [],
                exclude_user_ids: [],
              })
            }))
            .returns(
              ResponseMock.new(
                error: nil,
                data: ResponseDataMock.new(
                  total_blocks_count: 1,
                  successful_blocks_count: 2,
                  bypassed_alerts_count: 3
                )
              )
            )

          result, error = SecretScanning::Services::MetricsService.get_push_protection_metrics(
            @business,
            @user,
            repo_owners: SecretScanning::Services::MetricsService::RepoOwnersFilters.new(
              owner_type: SecretScanning::Services::MetricsService::RepoOwnerType::Organization,
            )
          )

          refute error
          assert_kind_of SecretScanning::Models::PushProtectionMetrics, result
          assert_equal 1, T.must(result).total_block_count
          assert_equal 2, T.must(result).successful_block_count
          assert_equal 3, T.must(result).bypassed_alert_count
        end

        test "queries EMU users when type is User" do
          GitHub::TokenScanning::Service::Client
            .any_instance
            .expects(:get_push_protection_metrics)
            .once
            .with(has_entries({
              repo_owners: GitHub::Proto::SecretScanning::Api::V1::RepositoryOwners.new({
                filter_type: :USER,
                org_ids: [],
                exclude_org_ids: [],
                user_ids: [],
                exclude_user_ids: [],
              })
            }))
            .returns(
              ResponseMock.new(
                error: nil,
                data: ResponseDataMock.new(
                  total_blocks_count: 1,
                  successful_blocks_count: 2,
                  bypassed_alerts_count: 3
                )
              )
            )

          result, error = SecretScanning::Services::MetricsService.get_push_protection_metrics(
            @business,
            @user,
            repo_owners: SecretScanning::Services::MetricsService::RepoOwnersFilters.new(
              owner_type: SecretScanning::Services::MetricsService::RepoOwnerType::User,
            )
          )

          refute error
          assert_kind_of SecretScanning::Models::PushProtectionMetrics, result
          assert_equal 1, T.must(result).total_block_count
          assert_equal 2, T.must(result).successful_block_count
          assert_equal 3, T.must(result).bypassed_alert_count
        end
      end
    end

    context "with repos_in_archived_state" do
      context "when omitted" do
        test "default repo_archived_state is set from the request" do
          GitHub::TokenScanning::Service::Client
            .any_instance
            .expects(:get_push_protection_metrics)
            .once
            .with(has_entries({
              repo_archived_state: GitHub::Proto::SecretScanning::Api::V1::RepositoryArchivedState::ANY
            }))
            .returns(
              ResponseMock.new(
                error: nil,
                data: ResponseDataMock.new(
                  total_blocks_count: 1,
                  successful_blocks_count: 2,
                  bypassed_alerts_count: 3
                )
              )
            )

          result, error = SecretScanning::Services::MetricsService.get_push_protection_metrics(@business, @user)

          refute error
          assert_kind_of SecretScanning::Models::PushProtectionMetrics, result
          assert_equal 1, T.must(result).total_block_count
          assert_equal 2, T.must(result).successful_block_count
          assert_equal 3, T.must(result).bypassed_alert_count
        end
      end

      context "when provided" do
        test "default repo_archived_state is set from the request when nil" do
          GitHub::TokenScanning::Service::Client
            .any_instance
            .expects(:get_push_protection_metrics)
            .once
            .with(has_entries({
              repo_archived_state: GitHub::Proto::SecretScanning::Api::V1::RepositoryArchivedState::ANY
            }))
            .returns(
              ResponseMock.new(
                error: nil,
                data: ResponseDataMock.new(
                  total_blocks_count: 1,
                  successful_blocks_count: 2,
                  bypassed_alerts_count: 3
                )
              )
            )

          result, error = SecretScanning::Services::MetricsService.get_push_protection_metrics(@business, @user, repos_in_archived_state: nil)

          refute error
          assert_kind_of SecretScanning::Models::PushProtectionMetrics, result
          assert_equal 1, T.must(result).total_block_count
          assert_equal 2, T.must(result).successful_block_count
          assert_equal 3, T.must(result).bypassed_alert_count
        end

        test "queries archived repos when true" do
          GitHub::TokenScanning::Service::Client
            .any_instance
            .expects(:get_push_protection_metrics)
            .once
            .with(has_entries({
              repo_archived_state: GitHub::Proto::SecretScanning::Api::V1::RepositoryArchivedState::ARCHIVED
            }))
            .returns(
              ResponseMock.new(
                error: nil,
                data: ResponseDataMock.new(
                  total_blocks_count: 1,
                  successful_blocks_count: 2,
                  bypassed_alerts_count: 3
                )
              )
            )

          result, error = SecretScanning::Services::MetricsService.get_push_protection_metrics(@business, @user, repos_in_archived_state: true)

          refute error
          assert_kind_of SecretScanning::Models::PushProtectionMetrics, result
          assert_equal 1, T.must(result).total_block_count
          assert_equal 2, T.must(result).successful_block_count
          assert_equal 3, T.must(result).bypassed_alert_count
        end
      end
    end

    context "token_filters" do
      context "when omitted" do
        test "no token filter is set from the request" do
          GitHub::TokenScanning::Service::Client
            .any_instance
            .expects(:get_push_protection_metrics)
            .once
            .with do |request|
              SecretScanning::Services::MetricsService::PushProtectionTokenFilters.new.serialize.keys.all? do |key|
                !request.key?(key)
              end
            end

          SecretScanning::Services::MetricsService.get_push_protection_metrics(@business, @user)
        end
      end

      context "when provided" do
        test "no token filter is set from the request when nil" do
          GitHub::TokenScanning::Service::Client
            .any_instance
            .expects(:get_push_protection_metrics)
            .once
            .with do |request|
              SecretScanning::Services::MetricsService::PushProtectionTokenFilters.new.serialize.keys.all? do |key|
                !request.key?(key)
              end
            end

          SecretScanning::Services::MetricsService.get_push_protection_metrics(
            @business,
            @user,
            token_filters: nil
          )
        end

        test "token filter is set properly from request" do
          GitHub::TokenScanning::Service::Client
            .any_instance
            .expects(:get_push_protection_metrics)
            .once
            .with(has_entries({
              token_types: [],
              exclude_token_types: ["amazon_access_key"],
              token_providers: ["Amazon AWS"],
              exclude_token_providers: [],
              token_validities: [1],
              exclude_token_validities: []
            }))

          SecretScanning::Services::MetricsService.get_push_protection_metrics(
            @business,
            @user,
            token_filters: SecretScanning::Services::MetricsService::PushProtectionTokenFilters.new(
              token_types: [],
              exclude_token_types: ["amazon_access_key"],
              token_providers: ["Amazon AWS"],
              exclude_token_providers: [],
              token_validities: [1],
              exclude_token_validities: []
            ),
          )
        end
      end
    end

    context "with start and end dates" do
      context "when omitted" do
        test "dates are omitted from the request" do
          GitHub::TokenScanning::Service::Client
            .any_instance
            .expects(:get_push_protection_metrics)
            .once
            .with(Not(has_key(:start_date)))
            .with(Not(has_key(:end_date)))
            .returns(
              ResponseMock.new(
                error: nil,
                data: ResponseDataMock.new(
                  total_blocks_count: 1,
                  successful_blocks_count: 2,
                  bypassed_alerts_count: 3
                )
              )
            )

          result, error = SecretScanning::Services::MetricsService.get_push_protection_metrics(@business, @user)

          refute error
          assert_kind_of SecretScanning::Models::PushProtectionMetrics, result
          assert_equal 1, T.must(result).total_block_count
          assert_equal 2, T.must(result).successful_block_count
          assert_equal 3, T.must(result).bypassed_alert_count
        end
      end

      context "when provided" do
        test "dates are omitted from the request when nil" do
          GitHub::TokenScanning::Service::Client
            .any_instance
            .expects(:get_push_protection_metrics)
            .once
            .with(Not(has_key(:start_date)))
            .with(Not(has_key(:end_date)))
            .returns(
              ResponseMock.new(
                error: nil,
                data: ResponseDataMock.new(
                  total_blocks_count: 1,
                  successful_blocks_count: 2,
                  bypassed_alerts_count: 3
                )
              )
            )

          result, error = SecretScanning::Services::MetricsService.get_push_protection_metrics(@business, @user, start_date: nil, end_date: nil)

          refute error
          assert_kind_of SecretScanning::Models::PushProtectionMetrics, result
          assert_equal 1, T.must(result).total_block_count
          assert_equal 2, T.must(result).successful_block_count
          assert_equal 3, T.must(result).bypassed_alert_count
        end

        test "queries with dates when set to dates value" do
          now = Time.now.utc
          start_date = (now - 1.day).to_date
          end_date = now.to_date

          GitHub::TokenScanning::Service::Client
            .any_instance
            .expects(:get_push_protection_metrics)
            .once
            .with(has_entries({
              start_date: Google::Protobuf::Timestamp.new(seconds: start_date.to_time.to_i),
              end_date: Google::Protobuf::Timestamp.new(seconds: end_date.to_time.to_i)
            }))
            .returns(
              ResponseMock.new(
                error: nil,
                data: ResponseDataMock.new(
                  total_blocks_count: 1,
                  successful_blocks_count: 2,
                  bypassed_alerts_count: 3
                )
              )
            )

          result, error = SecretScanning::Services::MetricsService.get_push_protection_metrics(@business, @user, start_date:, end_date:)

          refute error
          assert_kind_of SecretScanning::Models::PushProtectionMetrics, result
          assert_equal 1, T.must(result).total_block_count
          assert_equal 2, T.must(result).successful_block_count
          assert_equal 3, T.must(result).bypassed_alert_count
        end
      end
    end

    test "request failure returns nil" do
      metrics_response = ResponseMock.new(
        error: StandardError.new("Service unavailable"),
        data: nil
      )

      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_push_protection_metrics).returns(metrics_response)

      result, error = SecretScanning::Services::MetricsService.get_push_protection_metrics(@org, @user)
      assert_nil result
      assert error # rubocop:disable GitHub/NestedSetupTeardown
    end
  end

  context "get_delegated_bypass_metrics" do
    fixtures do # rubocop:disable GitHub/NestedSetupTeardown
      @frozen_date = Date.today.freeze
      travel_to(@frozen_date) do
        reviewer = create(:user)
        @team.add_member(reviewer)
        @team.add_repository(@repo1, :admin)
        data = mock("data")
        data.stubs(:bypass_reviewers)
          .returns([GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer.new(
            id: 1,
            owner_id: @org.id,
            owner_scope: :ORGANIZATION_SCOPE,
            reviewer_id: @team.id,
            reviewer_type: :TEAM
          )])
        bypass_reviewers_response = stub(data: data, error: nil)
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_bypass_reviewers).returns(bypass_reviewers_response).at_least_once
        SecretScanning::Services::DelegatedBypassService..stubs(:can_review_bypass_request?).returns(true)

        @repo2_exemption_request = Exemptions::ExemptionRequest.create!(
          resource_owner: @resource_owner,
          requester: @user,
          resource_identifier: "ksuid",
          repository: @repo2,
          request_type: SecretScanning::Constants::EXEMPTION_REQUEST_TYPE,
          created_at: 1.day.ago,
          updated_at: 1.day.ago,
        )
        @exemption_request = Exemptions::ExemptionRequest.create!(
          resource_owner: @resource_owner,
          requester: @user,
          resource_identifier: "ksuid",
          repository: @repo1,
          request_type: SecretScanning::Constants::EXEMPTION_REQUEST_TYPE,
          created_at: 1.day.ago,
          updated_at: 1.day.ago,
        )
        @exemption_request_2 = Exemptions::ExemptionRequest.create!(
          resource_owner: @resource_owner,
          requester: @user,
          resource_identifier: "ksuid",
          repository: @repo1,
          request_type: SecretScanning::Constants::EXEMPTION_REQUEST_TYPE,
          created_at: 3.days.ago,
          updated_at: 1.day.ago,
        )
        @expired_exemption_request = Exemptions::ExemptionRequest.create!(
          resource_owner: @resource_owner,
          requester: @user,
          resource_identifier: "ksuid",
          repository: @repo1,
          request_type: SecretScanning::Constants::EXEMPTION_REQUEST_TYPE,
          created_at: 8.days.ago,
          updated_at: 8.days.ago,
          expires_at: 1.day.ago,
        )
        @new_exemption_request = Exemptions::ExemptionRequest.create!(
          resource_owner: @resource_owner,
          requester: @user,
          resource_identifier: "ksuid",
          repository: @repo1,
          request_type: SecretScanning::Constants::EXEMPTION_REQUEST_TYPE,
          created_at: 1.day.from_now,
          updated_at: 1.day.from_now,
        )
        @archived_exemption_request = Exemptions::ExemptionRequest.create!(
          resource_owner: @resource_owner,
          requester: @user,
          resource_identifier: "ksuid",
          repository: @archived_repo,
          request_type: SecretScanning::Constants::EXEMPTION_REQUEST_TYPE,
          created_at: 1.day.ago,
          updated_at: 1.day.ago,
        )

        @rejected_exemption_response = Exemptions::ExemptionResponse.create!(
          exemption_request: @expired_exemption_request,
          reviewer: reviewer,
          status: :rejected
        )
        @rejected_exemption_response_2 = Exemptions::ExemptionResponse.create!(
          exemption_request: @exemption_request_2,
          reviewer: reviewer,
          status: :rejected
        )
        @approved_exemption_response = Exemptions::ExemptionResponse.create!(
          exemption_request: @exemption_request,
          reviewer: reviewer,
          status: :approved
        )
      end
    end

    test "successful request (org)" do
      bypass_requests_count, mean_response_time, bypasses_by_request_status_counts = SecretScanning::Services::MetricsService.get_delegated_bypass_metrics(@org, @user)
      assert_equal 5, bypass_requests_count
      assert_equal 172800, mean_response_time
      assert_equal 3, bypasses_by_request_status_counts.length

      assert_equal 1, bypasses_by_request_status_counts[0]&.count
      assert_equal 20, bypasses_by_request_status_counts[0]&.percent
      assert_equal :approved, bypasses_by_request_status_counts[0]&.bypass_request_status
      assert_equal 1, bypasses_by_request_status_counts[1]&.count
      assert_equal 20, bypasses_by_request_status_counts[1]&.percent
      assert_equal :rejected, bypasses_by_request_status_counts[1]&.bypass_request_status
      assert_equal 3, bypasses_by_request_status_counts[2]&.count
      assert_equal 60, bypasses_by_request_status_counts[2]&.percent
      assert_equal :pending, bypasses_by_request_status_counts[2]&.bypass_request_status
    end

    test "successful request (business)" do
      bypass_requests_count, mean_response_time, bypasses_by_request_status_counts = SecretScanning::Services::MetricsService.get_delegated_bypass_metrics(@business, @user)
      assert_equal 5, bypass_requests_count
      assert_equal 172800, mean_response_time
      assert_equal 3, bypasses_by_request_status_counts.length

      assert_equal 1, bypasses_by_request_status_counts[0]&.count
      assert_equal 20, bypasses_by_request_status_counts[0]&.percent
      assert_equal :approved, bypasses_by_request_status_counts[0]&.bypass_request_status
      assert_equal 1, bypasses_by_request_status_counts[1]&.count
      assert_equal 20, bypasses_by_request_status_counts[1]&.percent
      assert_equal :rejected, bypasses_by_request_status_counts[1]&.bypass_request_status
      assert_equal 3, bypasses_by_request_status_counts[2]&.count
      assert_equal 60, bypasses_by_request_status_counts[2]&.percent
      assert_equal :pending, bypasses_by_request_status_counts[2]&.bypass_request_status
    end

    test "repo_ids" do
      bypass_requests_count, mean_response_time, bypasses_by_request_status_counts = SecretScanning::Services::MetricsService.get_delegated_bypass_metrics(@org, @user, repo_ids: [@repo1.id])
      assert_equal 3, bypass_requests_count
      assert_equal 172800, mean_response_time
      assert_equal 3, bypasses_by_request_status_counts.length

      assert_equal 1, bypasses_by_request_status_counts[0]&.count
      assert_equal 33, bypasses_by_request_status_counts[0]&.percent
      assert_equal :approved, bypasses_by_request_status_counts[0]&.bypass_request_status
      assert_equal 1, bypasses_by_request_status_counts[1]&.count
      assert_equal 33, bypasses_by_request_status_counts[1]&.percent
      assert_equal :rejected, bypasses_by_request_status_counts[1]&.bypass_request_status
      assert_equal 1, bypasses_by_request_status_counts[2]&.count
      assert_equal 33, bypasses_by_request_status_counts[2]&.percent
      assert_equal :pending, bypasses_by_request_status_counts[2]&.bypass_request_status
    end

    test "exclude_repo_ids" do
      bypass_requests_count, mean_response_time, bypasses_by_request_status_counts = SecretScanning::Services::MetricsService.get_delegated_bypass_metrics(@org, @user, exclude_repo_ids: [@repo1.id])
      assert_equal 2, bypass_requests_count
      assert_equal 0, mean_response_time
      assert_equal 1, bypasses_by_request_status_counts.length

      assert_equal 2, bypasses_by_request_status_counts[0]&.count
      assert_equal 100, bypasses_by_request_status_counts[0]&.percent
      assert_equal :pending, bypasses_by_request_status_counts[0]&.bypass_request_status
    end

    test "start_date" do
      bypass_requests_count, mean_response_time, bypasses_by_request_status_counts = SecretScanning::Services::MetricsService.get_delegated_bypass_metrics(@org, @user, start_date: (Time.now - 2.days).to_date)
      assert_equal 4, bypass_requests_count
      assert_equal 86400, mean_response_time
      assert_equal 2, bypasses_by_request_status_counts.length

      assert_equal 1, bypasses_by_request_status_counts[0]&.count
      assert_equal 25, bypasses_by_request_status_counts[0]&.percent
      assert_equal :approved, bypasses_by_request_status_counts[0]&.bypass_request_status
      assert_equal 3, bypasses_by_request_status_counts[1]&.count
      assert_equal 75, bypasses_by_request_status_counts[1]&.percent
      assert_equal :pending, bypasses_by_request_status_counts[1]&.bypass_request_status
    end

    test "end_date" do
      bypass_requests_count, mean_response_time, bypasses_by_request_status_counts = SecretScanning::Services::MetricsService.get_delegated_bypass_metrics(@org, @user, end_date: Time.now.to_date)
      assert_equal 4, bypass_requests_count
      assert_equal 172800, mean_response_time
      assert_equal 3, bypasses_by_request_status_counts.length

      assert_equal 1, bypasses_by_request_status_counts[0]&.count
      assert_equal 25, bypasses_by_request_status_counts[0]&.percent
      assert_equal :approved, bypasses_by_request_status_counts[0]&.bypass_request_status
      assert_equal 1, bypasses_by_request_status_counts[1]&.count
      assert_equal 25, bypasses_by_request_status_counts[1]&.percent
      assert_equal :rejected, bypasses_by_request_status_counts[1]&.bypass_request_status
      assert_equal 2, bypasses_by_request_status_counts[2]&.count
      assert_equal 50, bypasses_by_request_status_counts[2]&.percent
      assert_equal :pending, bypasses_by_request_status_counts[2]&.bypass_request_status
    end

    context "repos_in_archived_state" do
      test "archived is true" do
        bypass_requests_count, mean_response_time, bypasses_by_request_status_counts = SecretScanning::Services::MetricsService.get_delegated_bypass_metrics(@org, @user, repos_in_archived_state: true)
        assert_equal 1, bypass_requests_count
        assert_equal 0, mean_response_time
        assert_equal 1, bypasses_by_request_status_counts.length

        assert_equal 1, bypasses_by_request_status_counts[0]&.count
        assert_equal 100, bypasses_by_request_status_counts[0]&.percent
        assert_equal :pending, bypasses_by_request_status_counts[0]&.bypass_request_status
      end

      test "archived is false" do
        bypass_requests_count, mean_response_time, bypasses_by_request_status_counts = SecretScanning::Services::MetricsService.get_delegated_bypass_metrics(@org, @user, repos_in_archived_state: false)
        assert_equal 4, bypass_requests_count
        assert_equal 172800, mean_response_time
        assert_equal 3, bypasses_by_request_status_counts.length

        assert_equal 1, bypasses_by_request_status_counts[0]&.count
        assert_equal 25, bypasses_by_request_status_counts[0]&.percent
        assert_equal :approved, bypasses_by_request_status_counts[0]&.bypass_request_status
        assert_equal 1, bypasses_by_request_status_counts[1]&.count
        assert_equal 25, bypasses_by_request_status_counts[1]&.percent
        assert_equal :rejected, bypasses_by_request_status_counts[1]&.bypass_request_status
        assert_equal 2, bypasses_by_request_status_counts[2]&.count
        assert_equal 50, bypasses_by_request_status_counts[2]&.percent
        assert_equal :pending, bypasses_by_request_status_counts[2]&.bypass_request_status
      end
    end

    context "bypass_request_ids" do
      test "applied if token_filters is not nil" do
        bypass_requests_count, mean_response_time, bypasses_by_request_status_counts = SecretScanning::Services::MetricsService.get_delegated_bypass_metrics(
          @org,
          @user,
          bypass_request_ids: [@exemption_request.id, @exemption_request_2.id],
          token_filters: SecretScanning::Services::MetricsService::PushProtectionTokenFilters.new(
            token_types: [],
            exclude_token_types: ["amazon_access_key"],
            token_providers: ["Amazon AWS"],
            exclude_token_providers: [],
            token_validities: [1],
            exclude_token_validities: [],
          ),
        )
        assert_equal 2, bypass_requests_count
        assert_equal 172800, mean_response_time
        assert_equal 2, bypasses_by_request_status_counts.length

        assert_equal 1, bypasses_by_request_status_counts[0]&.count
        assert_equal 50, bypasses_by_request_status_counts[0]&.percent
        assert_equal :approved, bypasses_by_request_status_counts[0]&.bypass_request_status
        assert_equal 1, bypasses_by_request_status_counts[1]&.count
        assert_equal 50, bypasses_by_request_status_counts[1]&.percent
        assert_equal :rejected, bypasses_by_request_status_counts[1]&.bypass_request_status
      end

      test "skipped if token_filters is nil" do
        bypass_requests_count, mean_response_time, bypasses_by_request_status_counts = SecretScanning::Services::MetricsService.get_delegated_bypass_metrics(@org, @user, bypass_request_ids: [@exemption_request.id, @exemption_request_2.id])
        assert_equal 5, bypass_requests_count
        assert_equal 172800, mean_response_time
        assert_equal 3, bypasses_by_request_status_counts.length

        assert_equal 1, bypasses_by_request_status_counts[0]&.count
        assert_equal 20, bypasses_by_request_status_counts[0]&.percent
        assert_equal :approved, bypasses_by_request_status_counts[0]&.bypass_request_status
        assert_equal 1, bypasses_by_request_status_counts[1]&.count
        assert_equal 20, bypasses_by_request_status_counts[1]&.percent
        assert_equal :rejected, bypasses_by_request_status_counts[1]&.bypass_request_status
        assert_equal 3, bypasses_by_request_status_counts[2]&.count
        assert_equal 60, bypasses_by_request_status_counts[2]&.percent
        assert_equal :pending, bypasses_by_request_status_counts[2]&.bypass_request_status
      end
    end

    context "repo_owners" do
      test "any type applies org and user filters" do
        bypass_requests_count, mean_response_time, bypasses_by_request_status_counts = SecretScanning::Services::MetricsService.get_delegated_bypass_metrics(
          @business,
          @user,
          repo_owners: SecretScanning::Services::MetricsService::RepoOwnersFilters.new(
            owner_type: SecretScanning::Services::MetricsService::RepoOwnerType::Any,
            org_ids: [@org.id],
            exclude_org_ids: [2],
            user_ids: [4, 5, 6],
            exclude_user_ids: [5, 6],
          ),
        )
        assert_equal 5, bypass_requests_count
        assert_equal 172800, mean_response_time
        assert_equal 3, bypasses_by_request_status_counts.length

        assert_equal 1, bypasses_by_request_status_counts[0]&.count
        assert_equal 20, bypasses_by_request_status_counts[0]&.percent
        assert_equal :approved, bypasses_by_request_status_counts[0]&.bypass_request_status
        assert_equal 1, bypasses_by_request_status_counts[1]&.count
        assert_equal 20, bypasses_by_request_status_counts[1]&.percent
        assert_equal :rejected, bypasses_by_request_status_counts[1]&.bypass_request_status
        assert_equal 3, bypasses_by_request_status_counts[2]&.count
        assert_equal 60, bypasses_by_request_status_counts[2]&.percent
        assert_equal :pending, bypasses_by_request_status_counts[2]&.bypass_request_status
      end

      test "org type applies org filters" do
        bypass_requests_count, mean_response_time, bypasses_by_request_status_counts = SecretScanning::Services::MetricsService.get_delegated_bypass_metrics(
          @business,
          @user,
          repo_owners: SecretScanning::Services::MetricsService::RepoOwnersFilters.new(
            owner_type: SecretScanning::Services::MetricsService::RepoOwnerType::Organization,
            org_ids: [@org.id],
            exclude_org_ids: [2],
            user_ids: [4, 5, 6],
            exclude_user_ids: [5, 6],
          ),
        )
        assert_equal 5, bypass_requests_count
        assert_equal 172800, mean_response_time
        assert_equal 3, bypasses_by_request_status_counts.length

        assert_equal 1, bypasses_by_request_status_counts[0]&.count
        assert_equal 20, bypasses_by_request_status_counts[0]&.percent
        assert_equal :approved, bypasses_by_request_status_counts[0]&.bypass_request_status
        assert_equal 1, bypasses_by_request_status_counts[1]&.count
        assert_equal 20, bypasses_by_request_status_counts[1]&.percent
        assert_equal :rejected, bypasses_by_request_status_counts[1]&.bypass_request_status
        assert_equal 3, bypasses_by_request_status_counts[2]&.count
        assert_equal 60, bypasses_by_request_status_counts[2]&.percent
        assert_equal :pending, bypasses_by_request_status_counts[2]&.bypass_request_status
      end

      test "user type applies user filters" do
        bypass_requests_count, mean_response_time, bypasses_by_request_status_counts = SecretScanning::Services::MetricsService.get_delegated_bypass_metrics(
          @business,
          @user,
          repo_owners: SecretScanning::Services::MetricsService::RepoOwnersFilters.new(
            owner_type: SecretScanning::Services::MetricsService::RepoOwnerType::User,
            org_ids: [@org.id],
            exclude_org_ids: [2],
            user_ids: [41, 51, 61],
            exclude_user_ids: [51, 61],
          ),
        )
        assert_equal 0, bypass_requests_count
        assert_equal 0, mean_response_time
        assert_equal 0, bypasses_by_request_status_counts.length
      end
    end
  end

  context "get_push_protection_metrics_for_repos" do
    context "when the response is nil" do
      test "returns nil and that an error occurred" do
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_push_protection_metrics_for_repos).returns(nil)
        result, err = SecretScanning::Services::MetricsService.get_push_protection_metrics_for_repos(@org, @user)

        assert_nil(result)
        assert(err)
      end
    end

    context "when the response has an error" do
      test "returns nil and that an error occurred" do
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_push_protection_metrics_for_repos).returns(ResponseMock.new(error: StandardError.new("error")))
        result, err = SecretScanning::Services::MetricsService.get_push_protection_metrics_for_repos(@org, @user)

        assert_nil(result)
        assert(err)
      end
    end

    context "when the data is nil" do
      test "returns nil and that an error did not occur" do
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_push_protection_metrics_for_repos).returns(ResponseMock.new(error: nil, data: nil))
        result, err = SecretScanning::Services::MetricsService.get_push_protection_metrics_for_repos(@org, @user)

        assert_nil(result)
        refute(err)
      end
    end

    test "returns data and that an error did not occur" do
      GitHub::TokenScanning::Service::Client
        .any_instance
        .expects(:get_push_protection_metrics_for_repos)
        .returns(
          ResponseMock.new(
            error: nil,
            data: ResponseDataMock.new(
              total_blocks_count: 1,
              successful_blocks_count: 2,
              bypassed_alerts_count: 3
            )
          ))

      result, err = SecretScanning::Services::MetricsService.get_push_protection_metrics_for_repos(@org, @user)

      assert_kind_of(SecretScanning::Models::PushProtectionMetricsForRepos, result)
      assert_equal(1, T.must(result).total_block_count)
      assert_equal(2, T.must(result).successful_block_count)
      assert_equal(3, T.must(result).bypassed_alert_count)
      refute(err)
    end

    context "repo_owners" do
      context "when omitted" do
        test "omits repo_owners from the request when not provided" do
          GitHub::TokenScanning::Service::Client
            .any_instance
            .expects(:get_push_protection_metrics_for_repos)
            .once
            .with(Not(has_key(:repo_owners)))
            .returns(
              ResponseMock.new(
                error: nil,
                data: ResponseDataMock.new(
                  total_blocks_count: 1,
                  successful_blocks_count: 2,
                  bypassed_alerts_count: 3
                )
              )
            )

          result, err = SecretScanning::Services::MetricsService.get_push_protection_metrics_for_repos(@business, @user)

          assert_kind_of SecretScanning::Models::PushProtectionMetricsForRepos, result
          assert_equal 1, T.must(result).total_block_count
          assert_equal 2, T.must(result).successful_block_count
          assert_equal 3, T.must(result).bypassed_alert_count
          refute err
        end
      end

      context "when provided" do
        test "queries all owners by default" do
          GitHub::TokenScanning::Service::Client
            .any_instance
            .expects(:get_push_protection_metrics_for_repos)
            .once
            .with(has_entries({
              repo_owners: GitHub::Proto::SecretScanning::Api::V1::RepositoryOwners.new({
                filter_type: :ALL,
                org_ids: [],
                exclude_org_ids: [],
                user_ids: [],
                exclude_user_ids: [],
              })
            }))
            .returns(
              ResponseMock.new(
                error: nil,
                data: ResponseDataMock.new(
                  total_blocks_count: 1,
                  successful_blocks_count: 2,
                  bypassed_alerts_count: 3
                )
              )
            )

          result, err = SecretScanning::Services::MetricsService.get_push_protection_metrics_for_repos(
            @business,
            @user,
            repo_owners: SecretScanning::Services::MetricsService::RepoOwnersFilters.new,
          )

          assert_kind_of SecretScanning::Models::PushProtectionMetricsForRepos, result
          assert_equal 1, T.must(result).total_block_count
          assert_equal 2, T.must(result).successful_block_count
          assert_equal 3, T.must(result).bypassed_alert_count
          refute err
        end

        test "queries using all provided owner IDs" do
          GitHub::TokenScanning::Service::Client
            .any_instance
            .expects(:get_push_protection_metrics_for_repos)
            .once
            .with(has_entries({
              repo_owners: GitHub::Proto::SecretScanning::Api::V1::RepositoryOwners.new({
                filter_type: :ALL,
                org_ids: [1, 2, 3],
                exclude_org_ids: [2],
                user_ids: [4, 5, 6],
                exclude_user_ids: [5, 6],
              })
            }))
            .returns(
              ResponseMock.new(
                error: nil,
                data: ResponseDataMock.new(
                  total_blocks_count: 1,
                  successful_blocks_count: 2,
                  bypassed_alerts_count: 3
                )
              )
            )

          result, err = SecretScanning::Services::MetricsService.get_push_protection_metrics_for_repos(
            @business,
            @user,
            repo_owners: SecretScanning::Services::MetricsService::RepoOwnersFilters.new(
              owner_type: SecretScanning::Services::MetricsService::RepoOwnerType::Any,
              org_ids: [1, 2, 3],
              exclude_org_ids: [2],
              user_ids: [4, 5, 6],
              exclude_user_ids: [5, 6],
            ),
          )

          assert_kind_of SecretScanning::Models::PushProtectionMetricsForRepos, result
          assert_equal 1, T.must(result).total_block_count
          assert_equal 2, T.must(result).successful_block_count
          assert_equal 3, T.must(result).bypassed_alert_count
          refute err
        end

        test "queries orgs when type is Organization" do
          GitHub::TokenScanning::Service::Client
            .any_instance
            .expects(:get_push_protection_metrics_for_repos)
            .once
            .with(has_entries({
              repo_owners: GitHub::Proto::SecretScanning::Api::V1::RepositoryOwners.new({
                filter_type: :ORGANIZATION,
                org_ids: [],
                exclude_org_ids: [],
                user_ids: [],
                exclude_user_ids: [],
              })
            }))
            .returns(
              ResponseMock.new(
                error: nil,
                data: ResponseDataMock.new(
                  total_blocks_count: 1,
                  successful_blocks_count: 2,
                  bypassed_alerts_count: 3
                )
              )
            )

          result, err = SecretScanning::Services::MetricsService.get_push_protection_metrics_for_repos(
            @business,
            @user,
            repo_owners: SecretScanning::Services::MetricsService::RepoOwnersFilters.new(
              owner_type: SecretScanning::Services::MetricsService::RepoOwnerType::Organization,
            )
          )

          assert_kind_of SecretScanning::Models::PushProtectionMetricsForRepos, result
          assert_equal 1, T.must(result).total_block_count
          assert_equal 2, T.must(result).successful_block_count
          assert_equal 3, T.must(result).bypassed_alert_count
          refute err
        end

        test "queries EMU users when type is User" do
          GitHub::TokenScanning::Service::Client
            .any_instance
            .expects(:get_push_protection_metrics_for_repos)
            .once
            .with(has_entries({
              repo_owners: GitHub::Proto::SecretScanning::Api::V1::RepositoryOwners.new({
                filter_type: :USER,
                org_ids: [],
                exclude_org_ids: [],
                user_ids: [],
                exclude_user_ids: [],
              })
            }))
            .returns(
              ResponseMock.new(
                error: nil,
                data: ResponseDataMock.new(
                  total_blocks_count: 1,
                  successful_blocks_count: 2,
                  bypassed_alerts_count: 3
                )
              )
            )

          result, err = SecretScanning::Services::MetricsService.get_push_protection_metrics_for_repos(
            @business,
            @user,
            repo_owners: SecretScanning::Services::MetricsService::RepoOwnersFilters.new(
              owner_type: SecretScanning::Services::MetricsService::RepoOwnerType::User,
            )
          )

          assert_kind_of SecretScanning::Models::PushProtectionMetricsForRepos, result
          assert_equal 1, T.must(result).total_block_count
          assert_equal 2, T.must(result).successful_block_count
          assert_equal 3, T.must(result).bypassed_alert_count
          refute err
        end
      end
    end

    context "repos_in_archived_state" do
      context "when omitted" do
        test "default repo_archived_state is set from the request" do
          GitHub::TokenScanning::Service::Client
            .any_instance
            .expects(:get_push_protection_metrics_for_repos)
            .once
            .with(has_entries({
              repo_archived_state: GitHub::Proto::SecretScanning::Api::V1::RepositoryArchivedState::ANY
            }))
            .returns(
              ResponseMock.new(
                error: nil,
                data: ResponseDataMock.new(
                  total_blocks_count: 1,
                  successful_blocks_count: 2,
                  bypassed_alerts_count: 3
                )
              )
            )

          result, err = SecretScanning::Services::MetricsService.get_push_protection_metrics_for_repos(@business, @user)

          assert_kind_of SecretScanning::Models::PushProtectionMetricsForRepos, result
          assert_equal 1, T.must(result).total_block_count
          assert_equal 2, T.must(result).successful_block_count
          assert_equal 3, T.must(result).bypassed_alert_count
          refute err
        end
      end

      context "when provided" do
        test "default repo_archived_state is set from the request when nil" do
          GitHub::TokenScanning::Service::Client
            .any_instance
            .expects(:get_push_protection_metrics_for_repos)
            .once
            .with(has_entries({
              repo_archived_state: GitHub::Proto::SecretScanning::Api::V1::RepositoryArchivedState::ANY
            }))
            .returns(
              ResponseMock.new(
                error: nil,
                data: ResponseDataMock.new(
                  total_blocks_count: 1,
                  successful_blocks_count: 2,
                  bypassed_alerts_count: 3
                )
              )
            )

          result, err = SecretScanning::Services::MetricsService.get_push_protection_metrics_for_repos(
            @business,
            @user,
            repos_in_archived_state: nil,
          )

          assert_kind_of SecretScanning::Models::PushProtectionMetricsForRepos, result
          assert_equal 1, T.must(result).total_block_count
          assert_equal 2, T.must(result).successful_block_count
          assert_equal 3, T.must(result).bypassed_alert_count
          refute err
        end

        test "queries archived repos when true" do
          GitHub::TokenScanning::Service::Client
            .any_instance
            .expects(:get_push_protection_metrics_for_repos)
            .once
            .with(has_entries({
              repo_archived_state: GitHub::Proto::SecretScanning::Api::V1::RepositoryArchivedState::ARCHIVED
            }))
            .returns(
              ResponseMock.new(
                error: nil,
                data: ResponseDataMock.new(
                  total_blocks_count: 1,
                  successful_blocks_count: 2,
                  bypassed_alerts_count: 3
                )
              )
            )

          result, err = SecretScanning::Services::MetricsService.get_push_protection_metrics_for_repos(
            @business,
            @user,
            repos_in_archived_state: true,
          )

          assert_kind_of SecretScanning::Models::PushProtectionMetricsForRepos, result
          assert_equal 1, T.must(result).total_block_count
          assert_equal 2, T.must(result).successful_block_count
          assert_equal 3, T.must(result).bypassed_alert_count
          refute err
        end

        test "queries not archived repos when false" do
          GitHub::TokenScanning::Service::Client
            .any_instance
            .expects(:get_push_protection_metrics_for_repos)
            .once
            .with(has_entries({
              repo_archived_state: GitHub::Proto::SecretScanning::Api::V1::RepositoryArchivedState::NOT_ARCHIVED
            }))
            .returns(
              ResponseMock.new(
                error: nil,
                data: ResponseDataMock.new(
                  total_blocks_count: 1,
                  successful_blocks_count: 2,
                  bypassed_alerts_count: 3
                )
              )
            )

          result, err = SecretScanning::Services::MetricsService.get_push_protection_metrics_for_repos(
            @business,
            @user,
            repos_in_archived_state: false,
          )

          assert_kind_of SecretScanning::Models::PushProtectionMetricsForRepos, result
          assert_equal 1, T.must(result).total_block_count
          assert_equal 2, T.must(result).successful_block_count
          assert_equal 3, T.must(result).bypassed_alert_count
          refute err
        end
      end
    end

    context "token_filters" do
      context "when omitted" do
        test "no token filter is set from the request" do
          GitHub::TokenScanning::Service::Client
            .any_instance
            .expects(:get_push_protection_metrics_for_repos)
            .once
            .with do |request|
              SecretScanning::Services::MetricsService::PushProtectionTokenFilters.new.serialize.keys.all? do |key|
                !request.key?(key)
              end
            end

          SecretScanning::Services::MetricsService.get_push_protection_metrics_for_repos(@business, @user)
        end
      end

      context "when provided" do
        test "no token filter is set from the request when nil" do
          GitHub::TokenScanning::Service::Client
            .any_instance
            .expects(:get_push_protection_metrics_for_repos)
            .once
            .with do |request|
              SecretScanning::Services::MetricsService::PushProtectionTokenFilters.new.serialize.keys.all? do |key|
                !request.key?(key)
              end
            end

          SecretScanning::Services::MetricsService.get_push_protection_metrics_for_repos(
            @business,
            @user,
            token_filters: nil
          )
        end

        test "token filter is set properly from request" do
          GitHub::TokenScanning::Service::Client
            .any_instance
            .expects(:get_push_protection_metrics_for_repos)
            .once
            .with(has_entries({
              token_types: [],
              exclude_token_types: ["amazon_access_key"],
              token_providers: ["Amazon AWS"],
              exclude_token_providers: [],
              token_validities: [1],
              exclude_token_validities: []
            }))

          SecretScanning::Services::MetricsService.get_push_protection_metrics_for_repos(
            @business,
            @user,
            token_filters: SecretScanning::Services::MetricsService::PushProtectionTokenFilters.new(
              token_types: [],
              exclude_token_types: ["amazon_access_key"],
              token_providers: ["Amazon AWS"],
              exclude_token_providers: [],
              token_validities: [1],
              exclude_token_validities: []
            ),
          )
        end
      end
    end
  end

  context "get_token_alert_metrics" do
    test "successful request (repo)" do
      metrics_response = ResponseMock.new(
        error: nil,
        data: ResponseDataMock.new(
          open_alerts: 30,
          closed_alerts: 12,
          false_positive_alerts: 5
        )
      )

      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_alert_metrics)
        .with(has_entries(owner_id: @repo1.id, owner_scope: GitHub::Proto::SecretScanning::Api::V1::OwnerScope::REPOSITORY_SCOPE, token_type: "AWS_SECRET"))
        .returns(metrics_response)

      result = SecretScanning::Services::MetricsService.get_token_alert_metrics("AWS_SECRET", @repo1, @user)
      refute result.nil?
      result = T.must(result)
      assert_equal 30, result.open_alert_count
      assert_equal 12, result.closed_alert_count
      assert_equal 5, result.false_positive_count
    end

    test "successful request (org)" do
      metrics_response = ResponseMock.new(
        error: nil,
        data: ResponseDataMock.new(
          open_alerts: 30,
          closed_alerts: 12,
          false_positive_alerts: 5
        )
      )

      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_alert_metrics)
        .with(has_entries(owner_id: @org.id, owner_scope: GitHub::Proto::SecretScanning::Api::V1::OwnerScope::ORGANIZATION_SCOPE, token_type: "AWS_SECRET"))
        .returns(metrics_response)

      result = SecretScanning::Services::MetricsService.get_token_alert_metrics("AWS_SECRET", @org, @user)
      refute result.nil?
      result = T.must(result)
      assert_equal 30, result.open_alert_count
      assert_equal 12, result.closed_alert_count
      assert_equal 5, result.false_positive_count
    end

    test "successful request (business)" do
      metrics_response = ResponseMock.new(
        error: nil,
        data: ResponseDataMock.new(
          open_alerts: 30,
          closed_alerts: 12,
          false_positive_alerts: 5
        )
      )

      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_alert_metrics)
        .with(has_entries(owner_id: @business.id, owner_scope: GitHub::Proto::SecretScanning::Api::V1::OwnerScope::BUSINESS_SCOPE, token_type: "AWS_SECRET"))
        .returns(metrics_response)

      result = SecretScanning::Services::MetricsService.get_token_alert_metrics("AWS_SECRET", @business, @user)
      refute result.nil?
      result = T.must(result)
      assert_equal 30, result.open_alert_count
      assert_equal 12, result.closed_alert_count
      assert_equal 5, result.false_positive_count
    end

    test "request failure returns nil" do
      metrics_response = ResponseMock.new(
        error: "Service unavailable",
        data: nil
      )

      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_alert_metrics).returns(metrics_response)

      result = SecretScanning::Services::MetricsService.get_token_alert_metrics("AWS_SECRET", @repo1, @user)
      assert result.nil?
    end
  end

  context "show all metrics" do
    test "request failure returns nil" do
      metrics_response = ResponseMock.new(
        error: "Service unavailable",
        data: nil
      )

      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_block_counts_by_token_type).returns(metrics_response)
      result = SecretScanning::Services::MetricsService.get_block_counts_by_token_type(@org, @user)
      assert result.nil?

      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_block_counts_by_repo).returns(metrics_response)
      result = SecretScanning::Services::MetricsService.get_block_counts_by_repo(@org, @user)
      assert result.nil?

      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_bypass_counts_by_token_type).returns(metrics_response)
      result = SecretScanning::Services::MetricsService.get_bypass_counts_by_token_type(@org, @user)
      assert result.nil?

      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_bypass_counts_by_repo).returns(metrics_response)
      result = SecretScanning::Services::MetricsService.get_bypass_counts_by_repo(@org, @user)
      assert result.nil?
    end

    context "get_block_counts_by_token_type" do
      test "successful request (org)" do
        metrics_response = ResponseMock.new(
          error: nil,
          data: ResponseDataMock.new(
            counts: [
              GitHub::Proto::SecretScanning::Metrics::V1::TokenTypeCount.new(token_type: "AWS_SECRET", count: 30),
              GitHub::Proto::SecretScanning::Metrics::V1::TokenTypeCount.new(token_type: "GCP_SECRET", count: 12),
            ],
            previous_cursor: nil,
            next_cursor: "foo",
          ),
        )
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_block_counts_by_token_type)
          .with(has_entries(
            owner_id: @org.id,
            owner_scope: GitHub::Proto::SecretScanning::Api::V1::OwnerScope::ORGANIZATION_SCOPE,
            cursor: nil,
            repo_ids: [1, 2, 3]
          ))
          .returns(metrics_response)
        result = T.must(SecretScanning::Services::MetricsService.get_block_counts_by_token_type(@org, @user, repo_ids: [1, 2, 3]))
        assert_equal 2, result.data.count
        assert_equal "AWS_SECRET", T.must(result.data[0]).token_type
        assert_equal 30, T.must(result.data[0]).count
        assert_equal "GCP_SECRET", T.must(result.data[1]).token_type
        assert_equal 12, T.must(result.data[1]).count
        assert_nil result.previous_cursor
        assert_equal "foo", result.next_cursor
      end

      test "successful request (business)" do
        metrics_response = ResponseMock.new(
          error: nil,
          data: ResponseDataMock.new(
            counts: [
              GitHub::Proto::SecretScanning::Metrics::V1::TokenTypeCount.new(token_type: "AWS_SECRET", count: 30),
              GitHub::Proto::SecretScanning::Metrics::V1::TokenTypeCount.new(token_type: "GCP_SECRET", count: 12),
            ],
            previous_cursor: nil,
            next_cursor: "foo",
          ),
        )
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_block_counts_by_token_type)
          .with(has_entries(
            owner_id: @business.id,
            owner_scope: GitHub::Proto::SecretScanning::Api::V1::OwnerScope::BUSINESS_SCOPE,
            cursor: nil,
            repo_ids: [1, 2, 3]
          ))
          .returns(metrics_response)
        result = T.must(SecretScanning::Services::MetricsService.get_block_counts_by_token_type(@business, @user, repo_ids: [1, 2, 3]))
        assert_equal 2, result.data.count
        assert_equal "AWS_SECRET", T.must(result.data[0]).token_type
        assert_equal 30, T.must(result.data[0]).count
        assert_equal "GCP_SECRET", T.must(result.data[1]).token_type
        assert_equal 12, T.must(result.data[1]).count
        assert_nil result.previous_cursor
        assert_equal "foo", result.next_cursor
      end

      context "with cursor" do
        context "when omitted" do
          test "passes empty cursor to the request" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_block_counts_by_token_type)
              .once
              .with(has_entries({
                cursor: nil
              }))

            result = SecretScanning::Services::MetricsService.get_block_counts_by_token_type(@business, @user)
          end
        end

        context "when provided" do
          test "passes the same cursor input to the request" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_block_counts_by_token_type)
              .once
              .with(has_entries({
                cursor: "test_cursor"
              }))

            result, err = SecretScanning::Services::MetricsService.get_block_counts_by_token_type(
              @business,
              @user,
              "test_cursor"
            )
          end
        end
      end

      context "with repository ids" do
        context "when omitted" do
          test "passes empty repository ids to the request" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_block_counts_by_token_type)
              .once
              .with(has_entries({
                repo_ids: [],
                exclude_repo_ids: []
              }))

            result = SecretScanning::Services::MetricsService.get_block_counts_by_token_type(@business, @user)
          end
        end

        context "when provided" do
          test "passes the same repo ids input to the request" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_block_counts_by_token_type)
              .once
              .with(has_entries({
                repo_ids: [1, 2, 3],
                exclude_repo_ids: [2, 4]
              }))

            result, err = SecretScanning::Services::MetricsService.get_block_counts_by_token_type(
              @business,
              @user,
              repo_ids: [1, 2, 3],
              exclude_repo_ids: [2, 4]
            )
          end
        end
      end

      context "repo_owners" do
        context "when omitted" do
          test "omits repo_owners from the request when not provided" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_block_counts_by_token_type)
              .once
              .with(Not(has_key(:repo_owners)))

            result = SecretScanning::Services::MetricsService.get_block_counts_by_token_type(@business, @user)
          end
        end

        context "when provided" do
          test "queries all owners by default" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_block_counts_by_token_type)
              .once
              .with(has_entries({
                repo_owners: GitHub::Proto::SecretScanning::Api::V1::RepositoryOwners.new({
                  filter_type: :ALL,
                  org_ids: [],
                  exclude_org_ids: [],
                  user_ids: [],
                  exclude_user_ids: [],
                })
              }))

            result = SecretScanning::Services::MetricsService.get_block_counts_by_token_type(
              @business,
              @user,
              repo_owners: SecretScanning::Services::MetricsService::RepoOwnersFilters.new,
            )
          end

          test "queries using all provided owner IDs" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_block_counts_by_token_type)
              .once
              .with(has_entries({
                repo_owners: GitHub::Proto::SecretScanning::Api::V1::RepositoryOwners.new({
                  filter_type: :ALL,
                  org_ids: [1, 2, 3],
                  exclude_org_ids: [2],
                  user_ids: [4, 5, 6],
                  exclude_user_ids: [5, 6],
                })
              }))

            result = SecretScanning::Services::MetricsService.get_block_counts_by_token_type(
              @business,
              @user,
              repo_owners: SecretScanning::Services::MetricsService::RepoOwnersFilters.new(
                owner_type: SecretScanning::Services::MetricsService::RepoOwnerType::Any,
                org_ids: [1, 2, 3],
                exclude_org_ids: [2],
                user_ids: [4, 5, 6],
                exclude_user_ids: [5, 6],
              ),
            )
          end

          test "queries orgs when type is Organization" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_block_counts_by_token_type)
              .once
              .with(has_entries({
                repo_owners: GitHub::Proto::SecretScanning::Api::V1::RepositoryOwners.new({
                  filter_type: :ORGANIZATION,
                  org_ids: [],
                  exclude_org_ids: [],
                  user_ids: [],
                  exclude_user_ids: [],
                })
              }))

            result = SecretScanning::Services::MetricsService.get_block_counts_by_token_type(
              @business,
              @user,
              repo_owners: SecretScanning::Services::MetricsService::RepoOwnersFilters.new(
                owner_type: SecretScanning::Services::MetricsService::RepoOwnerType::Organization,
              )
            )
          end

          test "queries EMU users when type is User" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_block_counts_by_token_type)
              .once
              .with(has_entries({
                repo_owners: GitHub::Proto::SecretScanning::Api::V1::RepositoryOwners.new({
                  filter_type: :USER,
                  org_ids: [],
                  exclude_org_ids: [],
                  user_ids: [],
                  exclude_user_ids: [],
                })
              }))

            result = SecretScanning::Services::MetricsService.get_block_counts_by_token_type(
              @business,
              @user,
              repo_owners: SecretScanning::Services::MetricsService::RepoOwnersFilters.new(
                owner_type: SecretScanning::Services::MetricsService::RepoOwnerType::User,
              )
            )
          end
        end
      end

      context "with repos_in_archived_state" do
        context "when omitted" do
          test "default repo_archived_state is set from the request" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_block_counts_by_token_type)
              .once
              .with(has_entries({
                repo_archived_state: GitHub::Proto::SecretScanning::Api::V1::RepositoryArchivedState::ANY
              }))

            result = SecretScanning::Services::MetricsService.get_block_counts_by_token_type(@business, @user)
          end
        end

        context "when provided" do
          test "default repo_archived_state is set from the request when nil" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_block_counts_by_token_type)
              .once
              .with(has_entries({
                repo_archived_state: GitHub::Proto::SecretScanning::Api::V1::RepositoryArchivedState::ANY
              }))

            result = SecretScanning::Services::MetricsService.get_block_counts_by_token_type(@business, @user, repos_in_archived_state: nil)
          end

          test "queries archived repos when true" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_block_counts_by_token_type)
              .once
              .with(has_entries({
                repo_archived_state: GitHub::Proto::SecretScanning::Api::V1::RepositoryArchivedState::ARCHIVED
              }))

            result = SecretScanning::Services::MetricsService.get_block_counts_by_token_type(@business, @user, repos_in_archived_state: true)
          end
        end
      end

      context "token_filters" do
        context "when omitted" do
          test "no token filter is set from the request" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_block_counts_by_token_type)
              .once
              .with do |request|
                SecretScanning::Services::MetricsService::PushProtectionTokenFilters.new.serialize.keys.all? do |key|
                  !request.key?(key)
                end
              end

            SecretScanning::Services::MetricsService.get_block_counts_by_token_type(@business, @user)
          end
        end

        context "when provided" do
          test "no token filter is set from the request when nil" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_block_counts_by_token_type)
              .once
              .with do |request|
                SecretScanning::Services::MetricsService::PushProtectionTokenFilters.new.serialize.keys.all? do |key|
                  !request.key?(key)
                end
              end

            SecretScanning::Services::MetricsService.get_block_counts_by_token_type(
              @business,
              @user,
              token_filters: nil
            )
          end

          test "token filter is set properly from request" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_block_counts_by_token_type)
              .once
              .with do |request|
                request[:token_types] == [] &&
                request[:exclude_token_types] == ["amazon_access_key"] &&
                request[:token_providers] == ["Amazon AWS"] &&
                request[:exclude_token_providers] == [] &&
                !request.key?(:token_validities) &&
                !request.key?(:exclude_token_validities)
              end

            SecretScanning::Services::MetricsService.get_block_counts_by_token_type(
              @business,
              @user,
              token_filters: SecretScanning::Services::MetricsService::PushProtectionTokenFilters.new(
                token_types: [],
                exclude_token_types: ["amazon_access_key"],
                token_providers: ["Amazon AWS"],
                exclude_token_providers: [],
                token_validities: [1],
                exclude_token_validities: []
              ),
            )
          end
        end
      end

      context "with start and end dates" do
        context "when omitted" do
          test "dates are omitted from the request" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_block_counts_by_token_type)
              .once
              .with(Not(has_key(:start_date)))
              .with(Not(has_key(:end_date)))

            result = SecretScanning::Services::MetricsService.get_block_counts_by_token_type(@business, @user)
          end
        end

        context "when provided" do
          test "dates are omitted from the request when nil" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_block_counts_by_token_type)
              .once
              .with(Not(has_key(:start_date)))
              .with(Not(has_key(:end_date)))

            result = SecretScanning::Services::MetricsService.get_block_counts_by_token_type(@business, @user, start_date: nil, end_date: nil)
          end

          test "queries with dates when set to dates value" do
            now = Time.now.utc
            start_date = (now - 1.day).to_date
            end_date = now.to_date

            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_block_counts_by_token_type)
              .once
              .with(has_entries({
                start_date: Google::Protobuf::Timestamp.new(seconds: start_date.to_time.to_i),
                end_date: Google::Protobuf::Timestamp.new(seconds: end_date.to_time.to_i)
              }))

            result = SecretScanning::Services::MetricsService.get_block_counts_by_token_type(@business, @user, start_date:, end_date:)
          end
        end
      end
    end

    context "get_block_counts_by_repo" do
      test "successful request (org)" do
        metrics_response = ResponseMock.new(
          error: nil,
          data: ResponseDataMock.new(
            counts: [
              GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(repo_id: @repo1.id, count: 20),
              GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(repo_id: @repo2.id, count: 8),
            ],
            previous_cursor: nil,
            next_cursor: "foo",
          ),
        )
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_block_counts_by_repo)
          .with(has_entries(
            owner_id: @org.id,
            owner_scope: GitHub::Proto::SecretScanning::Api::V1::OwnerScope::ORGANIZATION_SCOPE,
            cursor: nil,
            repo_ids: [1, 2, 3]
          ))
          .returns(metrics_response)
        result = T.must(SecretScanning::Services::MetricsService.get_block_counts_by_repo(@org, @user, repo_ids: [1, 2, 3]))
        assert_equal 2, result.data.count
        assert_equal @repo1.id, T.must(result.data[0]).repo_id
        assert_equal @repo1.name, T.must(result.data[0]).repo_name
        assert_equal 20, T.must(result.data[0]).count
        assert_equal @repo2.id, T.must(result.data[1]).repo_id
        assert_equal @repo2.name, T.must(result.data[1]).repo_name
        assert_equal 8, T.must(result.data[1]).count
        assert_nil result.previous_cursor
        assert_equal "foo", result.next_cursor
      end

      test "successful request (business)" do
        metrics_response = ResponseMock.new(
          error: nil,
          data: ResponseDataMock.new(
            counts: [
              GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(repo_id: @repo1.id, count: 20),
              GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(repo_id: @repo2.id, count: 8),
            ],
            previous_cursor: nil,
            next_cursor: "foo",
          ),
        )
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_block_counts_by_repo)
          .with(has_entries(
            owner_id: @business.id,
            owner_scope: GitHub::Proto::SecretScanning::Api::V1::OwnerScope::BUSINESS_SCOPE,
            cursor: nil,
            repo_ids: [1, 2, 3]
          ))
          .returns(metrics_response)
        result = T.must(SecretScanning::Services::MetricsService.get_block_counts_by_repo(@business, @user, repo_ids: [1, 2, 3]))
        assert_equal 2, result.data.count
        assert_equal @repo1.id, T.must(result.data[0]).repo_id
        assert_equal @repo1.name_with_display_owner, T.must(result.data[0]).repo_name
        assert_equal 20, T.must(result.data[0]).count
        assert_equal @repo2.id, T.must(result.data[1]).repo_id
        assert_equal @repo2.name_with_display_owner, T.must(result.data[1]).repo_name
        assert_equal 8, T.must(result.data[1]).count
        assert_nil result.previous_cursor
        assert_equal "foo", result.next_cursor
      end

      test "does not include repos that don't exist" do
        blocks_by_repository_counts = [
          GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(
            repo_id: @repo1.id,
            count: 50,
          ),
          GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(
            repo_id: @repo2.id,
            count: 100,
          ),
          GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(
            repo_id: 1234567, # this repo shouldn't show up as it doesn't exist
            count: 15,
          ),
        ]
        res = ResponseMock.new(
          data: ResponseDataMock.new(
            counts: blocks_by_repository_counts,
          )
        )

        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_block_counts_by_repo)
          .with(has_entries(owner_id: @org.id, owner_scope: GitHub::Proto::SecretScanning::Api::V1::OwnerScope::ORGANIZATION_SCOPE))
          .returns(res)

        result = SecretScanning::Services::MetricsService.get_block_counts_by_repo(@org, @user)
        refute result.nil?
        result = T.must(result)

        assert_equal 2, result.data.length
        assert_equal @repo1.id, result.data[0]&.repo_id
        assert_equal @repo2.id, result.data[1]&.repo_id
      end

      test "does not include deleted repos" do
        assert @deleted_repo.deleted?

        blocks_by_repository_counts = [
          GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(
            repo_id: @repo1.id,
            count: 50,
          ),
          GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(
            repo_id: @deleted_repo.id,
            count: 100,
          ),
        ]
        res = ResponseMock.new(
          data: ResponseDataMock.new(
            counts: blocks_by_repository_counts,
          )
        )

        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_block_counts_by_repo)
          .with(has_entries(owner_id: @org.id, owner_scope: GitHub::Proto::SecretScanning::Api::V1::OwnerScope::ORGANIZATION_SCOPE))
          .returns(res)

        result = SecretScanning::Services::MetricsService.get_block_counts_by_repo(@org, @user)
        refute result.nil?
        result = T.must(result)

        assert_equal 1, result.data.length
        assert_equal @repo1.id, result.data[0]&.repo_id
      end

      context "with cursor" do
        context "when omitted" do
          test "passes empty cursor to the request" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_block_counts_by_repo)
              .once
              .with(has_entries({
                cursor: nil
              }))

            result = SecretScanning::Services::MetricsService.get_block_counts_by_repo(@business, @user)
          end
        end

        context "when provided" do
          test "passes the same cursor input to the request" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_block_counts_by_repo)
              .once
              .with(has_entries({
                cursor: "test_cursor"
              }))

            result, err = SecretScanning::Services::MetricsService.get_block_counts_by_repo(
              @business,
              @user,
              "test_cursor"
            )
          end
        end
      end

      context "with repository ids" do
        context "when omitted" do
          test "passes empty repository ids to the request" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_block_counts_by_repo)
              .once
              .with(has_entries({
                repo_ids: [],
                exclude_repo_ids: []
              }))

            result = SecretScanning::Services::MetricsService.get_block_counts_by_repo(@business, @user)
          end
        end

        context "when provided" do
          test "passes the same repo ids input to the request" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_block_counts_by_repo)
              .once
              .with(has_entries({
                repo_ids: [1, 2, 3],
                exclude_repo_ids: [2, 4]
              }))

            result, err = SecretScanning::Services::MetricsService.get_block_counts_by_repo(
              @business,
              @user,
              repo_ids: [1, 2, 3],
              exclude_repo_ids: [2, 4]
            )
          end
        end
      end

      context "repo_owners" do
        context "when omitted" do
          test "omits repo_owners from the request when not provided" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_block_counts_by_repo)
              .once
              .with(Not(has_key(:repo_owners)))

            result = SecretScanning::Services::MetricsService.get_block_counts_by_repo(@business, @user)
          end
        end

        context "when provided" do
          test "queries all owners by default" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_block_counts_by_repo)
              .once
              .with(has_entries({
                repo_owners: GitHub::Proto::SecretScanning::Api::V1::RepositoryOwners.new({
                  filter_type: :ALL,
                  org_ids: [],
                  exclude_org_ids: [],
                  user_ids: [],
                  exclude_user_ids: [],
                })
              }))

            result = SecretScanning::Services::MetricsService.get_block_counts_by_repo(
              @business,
              @user,
              repo_owners: SecretScanning::Services::MetricsService::RepoOwnersFilters.new,
            )
          end

          test "queries using all provided owner IDs" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_block_counts_by_repo)
              .once
              .with(has_entries({
                repo_owners: GitHub::Proto::SecretScanning::Api::V1::RepositoryOwners.new({
                  filter_type: :ALL,
                  org_ids: [1, 2, 3],
                  exclude_org_ids: [2],
                  user_ids: [4, 5, 6],
                  exclude_user_ids: [5, 6],
                })
              }))

            result = SecretScanning::Services::MetricsService.get_block_counts_by_repo(
              @business,
              @user,
              repo_owners: SecretScanning::Services::MetricsService::RepoOwnersFilters.new(
                owner_type: SecretScanning::Services::MetricsService::RepoOwnerType::Any,
                org_ids: [1, 2, 3],
                exclude_org_ids: [2],
                user_ids: [4, 5, 6],
                exclude_user_ids: [5, 6],
              ),
            )
          end

          test "queries orgs when type is Organization" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_block_counts_by_repo)
              .once
              .with(has_entries({
                repo_owners: GitHub::Proto::SecretScanning::Api::V1::RepositoryOwners.new({
                  filter_type: :ORGANIZATION,
                  org_ids: [],
                  exclude_org_ids: [],
                  user_ids: [],
                  exclude_user_ids: [],
                })
              }))

            result = SecretScanning::Services::MetricsService.get_block_counts_by_repo(
              @business,
              @user,
              repo_owners: SecretScanning::Services::MetricsService::RepoOwnersFilters.new(
                owner_type: SecretScanning::Services::MetricsService::RepoOwnerType::Organization,
              )
            )
          end

          test "queries EMU users when type is User" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_block_counts_by_repo)
              .once
              .with(has_entries({
                repo_owners: GitHub::Proto::SecretScanning::Api::V1::RepositoryOwners.new({
                  filter_type: :USER,
                  org_ids: [],
                  exclude_org_ids: [],
                  user_ids: [],
                  exclude_user_ids: [],
                })
              }))

            result = SecretScanning::Services::MetricsService.get_block_counts_by_repo(
              @business,
              @user,
              repo_owners: SecretScanning::Services::MetricsService::RepoOwnersFilters.new(
                owner_type: SecretScanning::Services::MetricsService::RepoOwnerType::User,
              )
            )
          end
        end
      end

      context "with repos_in_archived_state" do
        context "when omitted" do
          test "default repo_archived_state is set from the request" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_block_counts_by_repo)
              .once
              .with(has_entries({
                repo_archived_state: GitHub::Proto::SecretScanning::Api::V1::RepositoryArchivedState::ANY
              }))

            result = SecretScanning::Services::MetricsService.get_block_counts_by_repo(@business, @user)
          end
        end

        context "when provided" do
          test "default repo_archived_state is set from the request when nil" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_block_counts_by_repo)
              .once
              .with(has_entries({
                repo_archived_state: GitHub::Proto::SecretScanning::Api::V1::RepositoryArchivedState::ANY
              }))

            result = SecretScanning::Services::MetricsService.get_block_counts_by_repo(@business, @user, repos_in_archived_state: nil)
          end

          test "queries archived repos when true" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_block_counts_by_repo)
              .once
              .with(has_entries({
                repo_archived_state: GitHub::Proto::SecretScanning::Api::V1::RepositoryArchivedState::ARCHIVED
              }))

            result = SecretScanning::Services::MetricsService.get_block_counts_by_repo(@business, @user, repos_in_archived_state: true)
          end
        end
      end

      context "token_filters" do
        context "when omitted" do
          test "no token filter is set from the request" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_block_counts_by_repo)
              .once
              .with do |request|
                SecretScanning::Services::MetricsService::PushProtectionTokenFilters.new.serialize.keys.all? do |key|
                  !request.key?(key)
                end
              end

            SecretScanning::Services::MetricsService.get_block_counts_by_repo(@business, @user)
          end
        end

        context "when provided" do
          test "no token filter is set from the request when nil" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_block_counts_by_repo)
              .once
              .with do |request|
                SecretScanning::Services::MetricsService::PushProtectionTokenFilters.new.serialize.keys.all? do |key|
                  !request.key?(key)
                end
              end

            SecretScanning::Services::MetricsService.get_block_counts_by_repo(
              @business,
              @user,
              token_filters: nil
            )
          end

          test "token filter is set properly from request" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_block_counts_by_repo)
              .once
              .with do |request|
                request[:token_types] == [] &&
                request[:exclude_token_types] == ["amazon_access_key"] &&
                request[:token_providers] == ["Amazon AWS"] &&
                request[:exclude_token_providers] == [] &&
                !request.key?(:token_validities) &&
                !request.key?(:exclude_token_validities)
              end

            SecretScanning::Services::MetricsService.get_block_counts_by_repo(
              @business,
              @user,
              token_filters: SecretScanning::Services::MetricsService::PushProtectionTokenFilters.new(
                token_types: [],
                exclude_token_types: ["amazon_access_key"],
                token_providers: ["Amazon AWS"],
                exclude_token_providers: [],
                token_validities: [1],
                exclude_token_validities: []
              ),
            )
          end
        end
      end

      context "with start and end dates" do
        context "when omitted" do
          test "dates are omitted from the request" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_block_counts_by_repo)
              .once
              .with(Not(has_key(:start_date)))
              .with(Not(has_key(:end_date)))

            result = SecretScanning::Services::MetricsService.get_block_counts_by_repo(@business, @user)
          end
        end

        context "when provided" do
          test "dates are omitted from the request when nil" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_block_counts_by_repo)
              .once
              .with(Not(has_key(:start_date)))
              .with(Not(has_key(:end_date)))

            result = SecretScanning::Services::MetricsService.get_block_counts_by_repo(@business, @user, start_date: nil, end_date: nil)
          end

          test "queries with dates when set to dates value" do
            now = Time.now.utc
            start_date = (now - 1.day).to_date
            end_date = now.to_date

            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_block_counts_by_repo)
              .once
              .with(has_entries({
                start_date: Google::Protobuf::Timestamp.new(seconds: start_date.to_time.to_i),
                end_date: Google::Protobuf::Timestamp.new(seconds: end_date.to_time.to_i)
              }))

            result = SecretScanning::Services::MetricsService.get_block_counts_by_repo(@business, @user, start_date:, end_date:)
          end
        end
      end
    end

    context "get_bypass_counts_by_token_type" do
      test "successful request (org)" do
        metrics_response = ResponseMock.new(
          error: nil,
          data: ResponseDataMock.new(
            counts: [
              GitHub::Proto::SecretScanning::Metrics::V1::TokenTypeCount.new(token_type: "AWS_SECRET", count: 30),
              GitHub::Proto::SecretScanning::Metrics::V1::TokenTypeCount.new(token_type: "GCP_SECRET", count: 12),
            ],
            previous_cursor: nil,
            next_cursor: "foo",
          ),
        )
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_bypass_counts_by_token_type)
          .with(has_entries(
            owner_id: @org.id,
            owner_scope: GitHub::Proto::SecretScanning::Api::V1::OwnerScope::ORGANIZATION_SCOPE,
            cursor: nil,
            repo_ids: [1, 2, 3]
          ))
          .returns(metrics_response)
        result = T.must(SecretScanning::Services::MetricsService.get_bypass_counts_by_token_type(@org, @user, repo_ids: [1, 2, 3]))
        assert_equal 2, result.data.count
        assert_equal "AWS_SECRET", T.must(result.data[0]).token_type
        assert_equal 30, T.must(result.data[0]).count
        assert_equal "GCP_SECRET", T.must(result.data[1]).token_type
        assert_equal 12, T.must(result.data[1]).count
        assert_nil result.previous_cursor
        assert_equal "foo", result.next_cursor
      end

      test "successful request (business)" do
        metrics_response = ResponseMock.new(
          error: nil,
          data: ResponseDataMock.new(
            counts: [
              GitHub::Proto::SecretScanning::Metrics::V1::TokenTypeCount.new(token_type: "AWS_SECRET", count: 30),
              GitHub::Proto::SecretScanning::Metrics::V1::TokenTypeCount.new(token_type: "GCP_SECRET", count: 12),
            ],
            previous_cursor: nil,
            next_cursor: "foo",
          ),
        )
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_bypass_counts_by_token_type)
          .with(has_entries(
            owner_id: @business.id,
            owner_scope: GitHub::Proto::SecretScanning::Api::V1::OwnerScope::BUSINESS_SCOPE,
            cursor: nil,
            repo_ids: [1, 2, 3]
          ))
          .returns(metrics_response)
        result = T.must(SecretScanning::Services::MetricsService.get_bypass_counts_by_token_type(@business, @user, repo_ids: [1, 2, 3]))
        assert_equal 2, result.data.count
        assert_equal "AWS_SECRET", T.must(result.data[0]).token_type
        assert_equal 30, T.must(result.data[0]).count
        assert_equal "GCP_SECRET", T.must(result.data[1]).token_type
        assert_equal 12, T.must(result.data[1]).count
        assert_nil result.previous_cursor
        assert_equal "foo", result.next_cursor
      end

      context "with cursor" do
        context "when omitted" do
          test "passes empty cursor to the request" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_bypass_counts_by_token_type)
              .once
              .with(has_entries({
                cursor: nil
              }))

            result = SecretScanning::Services::MetricsService.get_bypass_counts_by_token_type(@business, @user)
          end
        end

        context "when provided" do
          test "passes the same cursor input to the request" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_bypass_counts_by_token_type)
              .once
              .with(has_entries({
                cursor: "test_cursor"
              }))

            result, err = SecretScanning::Services::MetricsService.get_bypass_counts_by_token_type(
              @business,
              @user,
              "test_cursor"
            )
          end
        end
      end

      context "with repository ids" do
        context "when omitted" do
          test "passes empty repository ids to the request" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_bypass_counts_by_token_type)
              .once
              .with(has_entries({
                repo_ids: [],
                exclude_repo_ids: []
              }))

            result = SecretScanning::Services::MetricsService.get_bypass_counts_by_token_type(@business, @user)
          end
        end

        context "when provided" do
          test "passes the same repo ids input to the request" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_bypass_counts_by_token_type)
              .once
              .with(has_entries({
                repo_ids: [1, 2, 3],
                exclude_repo_ids: [2, 4]
              }))

            result, err = SecretScanning::Services::MetricsService.get_bypass_counts_by_token_type(
              @business,
              @user,
              repo_ids: [1, 2, 3],
              exclude_repo_ids: [2, 4]
            )
          end
        end
      end

      context "repo_owners" do
        context "when omitted" do
          test "omits repo_owners from the request when not provided" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_bypass_counts_by_token_type)
              .once
              .with(Not(has_key(:repo_owners)))

            result = SecretScanning::Services::MetricsService.get_bypass_counts_by_token_type(@business, @user)
          end
        end

        context "when provided" do
          test "queries all owners by default" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_bypass_counts_by_token_type)
              .once
              .with(has_entries({
                repo_owners: GitHub::Proto::SecretScanning::Api::V1::RepositoryOwners.new({
                  filter_type: :ALL,
                  org_ids: [],
                  exclude_org_ids: [],
                  user_ids: [],
                  exclude_user_ids: [],
                })
              }))

            result = SecretScanning::Services::MetricsService.get_bypass_counts_by_token_type(
              @business,
              @user,
              repo_owners: SecretScanning::Services::MetricsService::RepoOwnersFilters.new,
            )
          end

          test "queries using all provided owner IDs" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_bypass_counts_by_token_type)
              .once
              .with(has_entries({
                repo_owners: GitHub::Proto::SecretScanning::Api::V1::RepositoryOwners.new({
                  filter_type: :ALL,
                  org_ids: [1, 2, 3],
                  exclude_org_ids: [2],
                  user_ids: [4, 5, 6],
                  exclude_user_ids: [5, 6],
                })
              }))

            result = SecretScanning::Services::MetricsService.get_bypass_counts_by_token_type(
              @business,
              @user,
              repo_owners: SecretScanning::Services::MetricsService::RepoOwnersFilters.new(
                owner_type: SecretScanning::Services::MetricsService::RepoOwnerType::Any,
                org_ids: [1, 2, 3],
                exclude_org_ids: [2],
                user_ids: [4, 5, 6],
                exclude_user_ids: [5, 6],
              ),
            )
          end

          test "queries orgs when type is Organization" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_bypass_counts_by_token_type)
              .once
              .with(has_entries({
                repo_owners: GitHub::Proto::SecretScanning::Api::V1::RepositoryOwners.new({
                  filter_type: :ORGANIZATION,
                  org_ids: [],
                  exclude_org_ids: [],
                  user_ids: [],
                  exclude_user_ids: [],
                })
              }))

            result = SecretScanning::Services::MetricsService.get_bypass_counts_by_token_type(
              @business,
              @user,
              repo_owners: SecretScanning::Services::MetricsService::RepoOwnersFilters.new(
                owner_type: SecretScanning::Services::MetricsService::RepoOwnerType::Organization,
              )
            )
          end

          test "queries EMU users when type is User" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_bypass_counts_by_token_type)
              .once
              .with(has_entries({
                repo_owners: GitHub::Proto::SecretScanning::Api::V1::RepositoryOwners.new({
                  filter_type: :USER,
                  org_ids: [],
                  exclude_org_ids: [],
                  user_ids: [],
                  exclude_user_ids: [],
                })
              }))

            result = SecretScanning::Services::MetricsService.get_bypass_counts_by_token_type(
              @business,
              @user,
              repo_owners: SecretScanning::Services::MetricsService::RepoOwnersFilters.new(
                owner_type: SecretScanning::Services::MetricsService::RepoOwnerType::User,
              )
            )
          end
        end
      end

      context "with repos_in_archived_state" do
        context "when omitted" do
          test "default repo_archived_state is set from the request" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_bypass_counts_by_token_type)
              .once
              .with(has_entries({
                repo_archived_state: GitHub::Proto::SecretScanning::Api::V1::RepositoryArchivedState::ANY
              }))

            result = SecretScanning::Services::MetricsService.get_bypass_counts_by_token_type(@business, @user)
          end
        end

        context "when provided" do
          test "default repo_archived_state is set from the request when nil" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_bypass_counts_by_token_type)
              .once
              .with(has_entries({
                repo_archived_state: GitHub::Proto::SecretScanning::Api::V1::RepositoryArchivedState::ANY
              }))

            result = SecretScanning::Services::MetricsService.get_bypass_counts_by_token_type(@business, @user, repos_in_archived_state: nil)
          end

          test "queries archived repos when true" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_bypass_counts_by_token_type)
              .once
              .with(has_entries({
                repo_archived_state: GitHub::Proto::SecretScanning::Api::V1::RepositoryArchivedState::ARCHIVED
              }))

            result = SecretScanning::Services::MetricsService.get_bypass_counts_by_token_type(@business, @user, repos_in_archived_state: true)
          end
        end
      end

      context "token_filters" do
        context "when omitted" do
          test "no token filter is set from the request" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_bypass_counts_by_token_type)
              .once
              .with do |request|
                SecretScanning::Services::MetricsService::PushProtectionTokenFilters.new.serialize.keys.all? do |key|
                  !request.key?(key)
                end
              end

            SecretScanning::Services::MetricsService.get_bypass_counts_by_token_type(@business, @user)
          end
        end

        context "when provided" do
          test "no token filter is set from the request when nil" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_bypass_counts_by_token_type)
              .once
              .with do |request|
                SecretScanning::Services::MetricsService::PushProtectionTokenFilters.new.serialize.keys.all? do |key|
                  !request.key?(key)
                end
              end

            SecretScanning::Services::MetricsService.get_bypass_counts_by_token_type(
              @business,
              @user,
              token_filters: nil
            )
          end

          test "token filter is set properly from request" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_bypass_counts_by_token_type)
              .once
              .with(has_entries({
                token_types: [],
                exclude_token_types: ["amazon_access_key"],
                token_providers: ["Amazon AWS"],
                exclude_token_providers: [],
                token_validities: [1],
                exclude_token_validities: []
              }))

            SecretScanning::Services::MetricsService.get_bypass_counts_by_token_type(
              @business,
              @user,
              token_filters: SecretScanning::Services::MetricsService::PushProtectionTokenFilters.new(
                token_types: [],
                exclude_token_types: ["amazon_access_key"],
                token_providers: ["Amazon AWS"],
                exclude_token_providers: [],
                token_validities: [1],
                exclude_token_validities: []
              ),
            )
          end
        end
      end

      context "with start and end dates" do
        context "when omitted" do
          test "dates are omitted from the request" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_bypass_counts_by_token_type)
              .once
              .with(Not(has_key(:start_date)))
              .with(Not(has_key(:end_date)))

            result = SecretScanning::Services::MetricsService.get_bypass_counts_by_token_type(@business, @user)
          end
        end

        context "when provided" do
          test "dates are omitted from the request when nil" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_bypass_counts_by_token_type)
              .once
              .with(Not(has_key(:start_date)))
              .with(Not(has_key(:end_date)))

            result = SecretScanning::Services::MetricsService.get_bypass_counts_by_token_type(@business, @user, start_date: nil, end_date: nil)
          end

          test "queries with dates when set to dates value" do
            now = Time.now.utc
            start_date = (now - 1.day).to_date
            end_date = now.to_date

            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_bypass_counts_by_token_type)
              .once
              .with(has_entries({
                start_date: Google::Protobuf::Timestamp.new(seconds: start_date.to_time.to_i),
                end_date: Google::Protobuf::Timestamp.new(seconds: end_date.to_time.to_i)
              }))

            result = SecretScanning::Services::MetricsService.get_bypass_counts_by_token_type(@business, @user, start_date:, end_date:)
          end
        end
      end
    end

    context "get_bypass_counts_by_repo" do
      test "successful request (org)" do
        metrics_response = ResponseMock.new(
          error: nil,
          data: ResponseDataMock.new(
            counts: [
              GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(repo_id: @repo1.id, count: 20),
              GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(repo_id: @repo2.id, count: 8),
            ],
            previous_cursor: nil,
            next_cursor: "foo",
          ),
        )
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_bypass_counts_by_repo)
          .with(has_entries(
            owner_id: @org.id,
            owner_scope: GitHub::Proto::SecretScanning::Api::V1::OwnerScope::ORGANIZATION_SCOPE,
            cursor: nil,
            repo_ids: [1, 2, 3]
          ))
          .returns(metrics_response)
        result = T.must(SecretScanning::Services::MetricsService.get_bypass_counts_by_repo(@org, @user, repo_ids: [1, 2, 3]))
        assert_equal 2, result.data.count
        assert_equal @repo1.id, T.must(result.data[0]).repo_id
        assert_equal @repo1.name, T.must(result.data[0]).repo_name
        assert_equal 20, T.must(result.data[0]).count
        assert_equal @repo2.id, T.must(result.data[1]).repo_id
        assert_equal @repo2.name, T.must(result.data[1]).repo_name
        assert_equal 8, T.must(result.data[1]).count
        assert_nil result.previous_cursor
        assert_equal "foo", result.next_cursor
      end

      test "successful request (business)" do
        metrics_response = ResponseMock.new(
          error: nil,
          data: ResponseDataMock.new(
            counts: [
              GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(repo_id: @repo1.id, count: 20),
              GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(repo_id: @repo2.id, count: 8),
            ],
            previous_cursor: nil,
            next_cursor: "foo",
          ),
        )
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_bypass_counts_by_repo)
          .with(has_entries(
            owner_id: @business.id,
            owner_scope: GitHub::Proto::SecretScanning::Api::V1::OwnerScope::BUSINESS_SCOPE,
            cursor: nil,
            repo_ids: [1, 2, 3]
          ))
          .returns(metrics_response)
        result = T.must(SecretScanning::Services::MetricsService.get_bypass_counts_by_repo(@business, @user, repo_ids: [1, 2, 3]))
        assert_equal 2, result.data.count
        assert_equal @repo1.id, T.must(result.data[0]).repo_id
        assert_equal @repo1.name_with_display_owner, T.must(result.data[0]).repo_name
        assert_equal 20, T.must(result.data[0]).count
        assert_equal @repo2.id, T.must(result.data[1]).repo_id
        assert_equal @repo2.name_with_display_owner, T.must(result.data[1]).repo_name
        assert_equal 8, T.must(result.data[1]).count
        assert_nil result.previous_cursor
        assert_equal "foo", result.next_cursor
      end

      test "counts by repository do not include repos that don't exist" do
        bypasses_by_repository_counts = [
          GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(
            repo_id: @repo1.id,
            count: 10,
          ),
          GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(
            repo_id: @repo2.id,
            count: 25,
          ),
          GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(
            repo_id: 1234567, # this repo shouldn't show up as it doesn't exist
            count: 15,
          ),
        ]
        res = ResponseMock.new(
          data: ResponseDataMock.new(
            counts: bypasses_by_repository_counts,
          )
        )

        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_bypass_counts_by_repo)
          .with(has_entries(owner_id: @org.id, owner_scope: GitHub::Proto::SecretScanning::Api::V1::OwnerScope::ORGANIZATION_SCOPE))
          .returns(res)

        result = SecretScanning::Services::MetricsService.get_bypass_counts_by_repo(@org, @user)
        refute result.nil?
        result = T.must(result)

        assert_equal 2, result.data.length
        assert_equal @repo1.id, result.data[0]&.repo_id
        assert_equal @repo2.id, result.data[1]&.repo_id

        assert_equal 2, result.data.length
        assert_equal @repo1.id, result.data[0]&.repo_id
        assert_equal @repo2.id, result.data[1]&.repo_id
      end

      test "counts by repository does not include deleted repos" do
        assert @deleted_repo.deleted?

        bypasses_by_repository_counts = [
          GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(
            repo_id: @repo1.id,
            count: 10,
          ),
          GitHub::Proto::SecretScanning::Metrics::V1::RepoCount.new(
            repo_id: @deleted_repo.id,
            count: 25,
          ),
        ]
        res = ResponseMock.new(
          data: ResponseDataMock.new(
            counts: bypasses_by_repository_counts,
          )
        )

        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_bypass_counts_by_repo)
          .with(has_entries(owner_id: @org.id, owner_scope: GitHub::Proto::SecretScanning::Api::V1::OwnerScope::ORGANIZATION_SCOPE))
          .returns(res)

        result = SecretScanning::Services::MetricsService.get_bypass_counts_by_repo(@org, @user)
        refute result.nil?
        result = T.must(result)

        assert_equal 1, result.data.length
        assert_equal @repo1.id, result.data[0]&.repo_id
      end

      context "with cursor" do
        context "when omitted" do
          test "passes empty cursor to the request" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_bypass_counts_by_repo)
              .once
              .with(has_entries({
                cursor: nil
              }))

            result = SecretScanning::Services::MetricsService.get_bypass_counts_by_repo(@business, @user)
          end
        end

        context "when provided" do
          test "passes the same cursor input to the request" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_bypass_counts_by_repo)
              .once
              .with(has_entries({
                cursor: "test_cursor"
              }))

            result, err = SecretScanning::Services::MetricsService.get_bypass_counts_by_repo(
              @business,
              @user,
              "test_cursor"
            )
          end
        end
      end

      context "with repository ids" do
        context "when omitted" do
          test "passes empty repository ids to the request" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_bypass_counts_by_repo)
              .once
              .with(has_entries({
                repo_ids: [],
                exclude_repo_ids: []
              }))

            result = SecretScanning::Services::MetricsService.get_bypass_counts_by_repo(@business, @user)
          end
        end

        context "when provided" do
          test "passes the same repo ids input to the request" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_bypass_counts_by_repo)
              .once
              .with(has_entries({
                repo_ids: [1, 2, 3],
                exclude_repo_ids: [2, 4]
              }))

            result, err = SecretScanning::Services::MetricsService.get_bypass_counts_by_repo(
              @business,
              @user,
              repo_ids: [1, 2, 3],
              exclude_repo_ids: [2, 4]
            )
          end
        end
      end

      context "repo_owners" do
        context "when omitted" do
          test "omits repo_owners from the request when not provided" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_bypass_counts_by_repo)
              .once
              .with(Not(has_key(:repo_owners)))

            result = SecretScanning::Services::MetricsService.get_bypass_counts_by_repo(@business, @user)
          end
        end

        context "when provided" do
          test "queries all owners by default" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_bypass_counts_by_repo)
              .once
              .with(has_entries({
                repo_owners: GitHub::Proto::SecretScanning::Api::V1::RepositoryOwners.new({
                  filter_type: :ALL,
                  org_ids: [],
                  exclude_org_ids: [],
                  user_ids: [],
                  exclude_user_ids: [],
                })
              }))

            result = SecretScanning::Services::MetricsService.get_bypass_counts_by_repo(
              @business,
              @user,
              repo_owners: SecretScanning::Services::MetricsService::RepoOwnersFilters.new,
            )
          end

          test "queries using all provided owner IDs" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_bypass_counts_by_repo)
              .once
              .with(has_entries({
                repo_owners: GitHub::Proto::SecretScanning::Api::V1::RepositoryOwners.new({
                  filter_type: :ALL,
                  org_ids: [1, 2, 3],
                  exclude_org_ids: [2],
                  user_ids: [4, 5, 6],
                  exclude_user_ids: [5, 6],
                })
              }))

            result = SecretScanning::Services::MetricsService.get_bypass_counts_by_repo(
              @business,
              @user,
              repo_owners: SecretScanning::Services::MetricsService::RepoOwnersFilters.new(
                owner_type: SecretScanning::Services::MetricsService::RepoOwnerType::Any,
                org_ids: [1, 2, 3],
                exclude_org_ids: [2],
                user_ids: [4, 5, 6],
                exclude_user_ids: [5, 6],
              ),
            )
          end

          test "queries orgs when type is Organization" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_bypass_counts_by_repo)
              .once
              .with(has_entries({
                repo_owners: GitHub::Proto::SecretScanning::Api::V1::RepositoryOwners.new({
                  filter_type: :ORGANIZATION,
                  org_ids: [],
                  exclude_org_ids: [],
                  user_ids: [],
                  exclude_user_ids: [],
                })
              }))

            result = SecretScanning::Services::MetricsService.get_bypass_counts_by_repo(
              @business,
              @user,
              repo_owners: SecretScanning::Services::MetricsService::RepoOwnersFilters.new(
                owner_type: SecretScanning::Services::MetricsService::RepoOwnerType::Organization,
              )
            )
          end

          test "queries EMU users when type is User" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_bypass_counts_by_repo)
              .once
              .with(has_entries({
                repo_owners: GitHub::Proto::SecretScanning::Api::V1::RepositoryOwners.new({
                  filter_type: :USER,
                  org_ids: [],
                  exclude_org_ids: [],
                  user_ids: [],
                  exclude_user_ids: [],
                })
              }))

            result = SecretScanning::Services::MetricsService.get_bypass_counts_by_repo(
              @business,
              @user,
              repo_owners: SecretScanning::Services::MetricsService::RepoOwnersFilters.new(
                owner_type: SecretScanning::Services::MetricsService::RepoOwnerType::User,
              )
            )
          end
        end
      end

      context "with repos_in_archived_state" do
        context "when omitted" do
          test "default repo_archived_state is set from the request" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_bypass_counts_by_repo)
              .once
              .with(has_entries({
                repo_archived_state: GitHub::Proto::SecretScanning::Api::V1::RepositoryArchivedState::ANY
              }))

            result = SecretScanning::Services::MetricsService.get_bypass_counts_by_repo(@business, @user)
          end
        end

        context "when provided" do
          test "default repo_archived_state is set from the request when nil" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_bypass_counts_by_repo)
              .once
              .with(has_entries({
                repo_archived_state: GitHub::Proto::SecretScanning::Api::V1::RepositoryArchivedState::ANY
              }))

            result = SecretScanning::Services::MetricsService.get_bypass_counts_by_repo(@business, @user, repos_in_archived_state: nil)
          end

          test "queries archived repos when true" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_bypass_counts_by_repo)
              .once
              .with(has_entries({
                repo_archived_state: GitHub::Proto::SecretScanning::Api::V1::RepositoryArchivedState::ARCHIVED
              }))

            result = SecretScanning::Services::MetricsService.get_bypass_counts_by_repo(@business, @user, repos_in_archived_state: true)
          end
        end
      end

      context "token_filters" do
        context "when omitted" do
          test "no token filter is set from the request" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_bypass_counts_by_repo)
              .once
              .with do |request|
                SecretScanning::Services::MetricsService::PushProtectionTokenFilters.new.serialize.keys.all? do |key|
                  !request.key?(key)
                end
              end

            SecretScanning::Services::MetricsService.get_bypass_counts_by_repo(@business, @user)
          end
        end

        context "when provided" do
          test "no token filter is set from the request when nil" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_bypass_counts_by_repo)
              .once
              .with do |request|
                SecretScanning::Services::MetricsService::PushProtectionTokenFilters.new.serialize.keys.all? do |key|
                  !request.key?(key)
                end
              end

            SecretScanning::Services::MetricsService.get_bypass_counts_by_repo(
              @business,
              @user,
              token_filters: nil
            )
          end

          test "token filter is set properly from request" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_bypass_counts_by_repo)
              .once
              .with(has_entries({
                token_types: [],
                exclude_token_types: ["amazon_access_key"],
                token_providers: ["Amazon AWS"],
                exclude_token_providers: [],
                token_validities: [1],
                exclude_token_validities: []
              }))

            SecretScanning::Services::MetricsService.get_bypass_counts_by_repo(
              @business,
              @user,
              token_filters: SecretScanning::Services::MetricsService::PushProtectionTokenFilters.new(
                token_types: [],
                exclude_token_types: ["amazon_access_key"],
                token_providers: ["Amazon AWS"],
                exclude_token_providers: [],
                token_validities: [1],
                exclude_token_validities: []
              ),
            )
          end
        end
      end

      context "with start and end dates" do
        context "when omitted" do
          test "dates are omitted from the request" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_bypass_counts_by_repo)
              .once
              .with(Not(has_key(:start_date)))
              .with(Not(has_key(:end_date)))

            result = SecretScanning::Services::MetricsService.get_bypass_counts_by_repo(@business, @user)
          end
        end

        context "when provided" do
          test "dates are omitted from the request when nil" do
            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_bypass_counts_by_repo)
              .once
              .with(Not(has_key(:start_date)))
              .with(Not(has_key(:end_date)))

            result = SecretScanning::Services::MetricsService.get_bypass_counts_by_repo(@business, @user, start_date: nil, end_date: nil)
          end

          test "queries with dates when set to dates value" do
            now = Time.now.utc
            start_date = (now - 1.day).to_date
            end_date = now.to_date

            GitHub::TokenScanning::Service::Client
              .any_instance
              .expects(:get_bypass_counts_by_repo)
              .once
              .with(has_entries({
                start_date: Google::Protobuf::Timestamp.new(seconds: start_date.to_time.to_i),
                end_date: Google::Protobuf::Timestamp.new(seconds: end_date.to_time.to_i)
              }))

            result = SecretScanning::Services::MetricsService.get_bypass_counts_by_repo(@business, @user, start_date:, end_date:)
          end
        end
      end
    end
  end
end
