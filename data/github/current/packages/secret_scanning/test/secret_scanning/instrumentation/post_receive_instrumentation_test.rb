# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Instrumentation
  class PostReceiveInstrumentationTest < GitHub::TestCase
    include HydroTestHelpers
    include HydroMessageJobTestHelpers

    include SecretScanning::Features::FeatureFlagHelper

    self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
    fixtures do
      @org = create(:organization, login: "org")
      @pusher = create(:user)

      @repository = create(:repository, owner: @org, from_example: :post_receive_job_test)
      @repository.analyze_languages

      @ref = "refs/heads/master"
      @before = "c1800491d95c42b4e96fb83f31fe8d9230c62907"
      @after = "63611721afd41f58f801d66e543d8288b4c5eb44"
      @updates = [Git::Ref::Update.new(repository: @repository, refname: @ref, before_oid: @before, after_oid: @after)]
    end

    setup do
      @post_receive_message = {
        repository_id: @repository.id,
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        ref_updates: [{
          ref: "refs/heads/master",
          before: "c1800491d95c42b4e96fb83f31fe8d9230c62907",
          after: "63611721afd41f58f801d66e543d8288b4c5eb44",
        }],
        pushed_at: Time.now,
        pusher: @pusher.login,
        run_hydro_job: true,
        enabled_flags: Repositories::HydroPushJobFlags::FLAGS.select { |f| GitHub.flipper[f].enabled? },
      }
    end

    test "hydro payload includes Secret Scanning service flags" do
      service_flags = %w[flag1 flag2 flag3]
      SecretScanning::Instrumentation::RepositoryServiceFlags.any_instance.stubs(:post_receive_service_flags).returns(service_flags)
      assert_hydro_messages(count: 0, schema: "github.v1.PostReceive")

      expected_flags = %w[flag1 flag2 flag3]

      hydro_message = {
        feature_flags: expected_flags,
      }

      message = {
        repository_id: @repository.id,
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        ref_updates: @updates.map { |u| { ref: u.refname, before: u.before_oid, after: u.after_oid } },
        pushed_at: Time.now,
        pusher: @pusher.login,
        run_hydro_job: true,
        enabled_flags: Repositories::HydroPushJobFlags::FLAGS.select { |f| GitHub.flipper[f].enabled? },
      }
      perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_repositories_on_push")
      with_hydro_publisher(GitHub.aqueduct_fallback_hydro_publisher.hydro_publisher) do
        assert_hydro_published_partial(hydro_message, schema: "github.v1.PostReceive", partition_key: @repository.id)
      end
    end

    test "message includes aleph feature flag when indexing and language are enabled", skip_enterprise: true do
      enable_feature_flag(:aleph_language_ruby)
      disable_feature_flag(:aleph_darkship_language_ruby)
      SecretScanning::Instrumentation::RepositoryServiceFlags.any_instance.stubs(:post_receive_service_flags).returns([])

      assert_hydro_messages(count: 0, schema: "github.v1.PostReceive")

      perform_hydro_message_job(@post_receive_message, schema: "github.repositories.v1.Pushed", queue: "hydro_repositories_on_push")

      hydro_message = {
        feature_flags: %w[],
        languages: %w[Ruby Go],
      }
      with_hydro_publisher(GitHub.aqueduct_fallback_hydro_publisher.hydro_publisher) do
        assert_hydro_published_partial(hydro_message, schema: "github.v1.PostReceive", partition_key: @repository.id)
      end
    end

    test "message includes aleph feature flag when darkship language indexing is enabled", skip_enterprise: true do
      disable_feature_flag(:aleph_language_ruby)
      enable_feature_flag(:aleph_darkship_language_ruby)
      SecretScanning::Instrumentation::RepositoryServiceFlags.any_instance.stubs(:post_receive_service_flags).returns([])
      assert_hydro_messages(count: 0, schema: "github.v1.PostReceive")

      perform_hydro_message_job(@post_receive_message, schema: "github.repositories.v1.Pushed", queue: "hydro_repositories_on_push")

      hydro_message = {
        feature_flags: %w[],
        languages: %w[Ruby Go],
      }
      with_hydro_publisher(GitHub.aqueduct_fallback_hydro_publisher.hydro_publisher) do
        assert_hydro_published_partial(hydro_message, schema: "github.v1.PostReceive", partition_key: @repository.id)
      end
    end

    test "message does not include aleph feature flag if language is disabled", skip_enterprise: true do
      disable_feature_flag(:aleph_darkship_language_ruby)
      disable_feature_flag(:aleph_language_ruby)
      disable_feature_flag(:aleph_language_go)
      disable_feature_flag(:aleph_darkship_language_go)
      SecretScanning::Instrumentation::RepositoryServiceFlags.any_instance.stubs(:post_receive_service_flags).returns([])

      assert_hydro_messages(count: 0, schema: "github.v1.PostReceive")
      perform_hydro_message_job(@post_receive_message, schema: "github.repositories.v1.Pushed", queue: "hydro_repositories_on_push")

      hydro_message = {
        feature_flags: %w[],
        languages: %w[Ruby Go],
      }
      with_hydro_publisher(GitHub.aqueduct_fallback_hydro_publisher.hydro_publisher) do
        assert_hydro_published_partial(hydro_message, schema: "github.v1.PostReceive", partition_key: @repository.id)
      end
    end
  end
end
