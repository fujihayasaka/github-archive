# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroSecretScanningRepositoryVisibilityJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include HydroTestHelpers
  include SecretScanning::Features::FeatureFlagHelper

  setup do
    @queue = "hydro_secret_scanning_repository_visibility"
    @schema = "github.repositories.v1.VisibilityChanged"

    @user = create :user
    @org = create :organization, admin: @user
    @repo = create(:repository, owner: @org)
    @repo.initialize_wiki(@repo.owner)

    SecretScanning::Features::Repo::WikiScanning.any_instance.stubs(:incremental_enabled?).returns(true)
    SecretScanning::Features::Repo::WikiScanning.any_instance.stubs(:backfill_enabled?).returns(true)
  end

  test "hydro messages are published", skip_enterprise: true do
    Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)

    message = {
      repository_id: @repo.id,
      actor_id: @user.id,
      request_id: GitHub.context[:request_id],
    }

    perform_hydro_message_job(message, schema: @schema, queue: @queue)

    assert_hydro_messages(count: 1, schema: "token_scanning_service.v0.BackfillRequest")
    expected_feature_flags = [
      SecretScanning::Instrumentation::ServiceFlags::TOKEN_SCANNING_SERVICE_INGEST,
      SecretScanning::Instrumentation::ServiceFlags::LOGIN_REVOCATION_IN_URL,
      SecretScanning::Instrumentation::ServiceFlags::ALERTS_FOR_RESOLVED_BYPASS,
      SecretScanning::Instrumentation::ServiceFlags::COMMIT_METADATA_SCANNING,
      SecretScanning::Instrumentation::ServiceFlags::LOGIN_REVOCATION_COMMIT_METADATA,
      SecretScanning::Instrumentation::ServiceFlags::CONTENT_BACKFILL_SCAN,
      SecretScanning::Instrumentation::ServiceFlags::WIKI_INCREMENTAL_SCANS,
      SecretScanning::Instrumentation::ServiceFlags::WIKI_BACKFILL_SCANS,
    ]

    if feature_flag_enabled?(@repo, FeatureFlags::PERSIST_RESULTS_FOR_PUBLIC_REPOS)
      expected_feature_flags.insert(6, SecretScanning::Instrumentation::ServiceFlags::PERSIST_RESULTS_FOR_PUBLIC_REPOS)
    end

    assert_hydro_published_partial({
      feature_flags: expected_feature_flags,
      wiki_scanning: true,
    }, schema: "token_scanning_service.v0.BackfillRequest")
  end

  test "feature toggle hydro messages are published" do
    message = {
      repository_id: @repo.id,
      actor_id: @user.id,
      request_id: GitHub.context[:request_id],
    }

    perform_hydro_message_job(message, schema: @schema, queue: @queue)

    assert_hydro_messages(count: 1, schema: "github.secret_scanning.v1.SecretScanningFeatureToggled")
    assert_hydro_messages(count: 1, schema: "github.secret_scanning.v1.SecretScanningPushProtectionFeatureToggled")
  end
end
