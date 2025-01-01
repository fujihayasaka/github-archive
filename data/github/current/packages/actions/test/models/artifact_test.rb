# typed: false
# frozen_string_literal: true
require "test_helper"
require "github-launch"
require "test_helpers/launch/artifacts_exchange_helper"

class ArtifactTest < GitHub::TestCase
  include HydroTestHelpers
  include AuditLog::IntegrationTestHelpers
  include StringFromBinaryTestHelper
  include Launch::ArtifactExchangeHelper
  include DogstatsTestHelpers

  fixtures do
    @check_suite = create :check_suite_for_actions_app
    @frozen_now = Time.utc(2021, 10, 7, 21, 16, 9).freeze
  end

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
    GitHub.flipper[:actions_shared_storage_use_billing_platform].disable
    GitHub.flipper[:actions_shared_storage_skip_meuse].disable
  end

  context "notify_socket_subscribers" do
    test "notifies of new artifact created when part of a workflow run" do
      make_trusted_oauth_apps_owner
      @actions_check_suite = create(:check_suite_for_actions_app)

      GitHub::WebSocket.expects(:notify_repository_channel).twice # Old UX still requires the busy channel

      create(:artifact, check_suite: @actions_check_suite, source_url: "https://logs.github.com/some-unique-slug-step1")
    end

    test "notifies of artifact updated through the workflow run channel" do
      make_trusted_oauth_apps_owner
      @actions_check_suite = create(:check_suite_for_actions_app)
      artifact = create(:artifact, check_suite: @actions_check_suite, source_url: "https://logs.github.com/some-unique-slug-step1")

      GitHub::WebSocket.expects(:notify_repository_channel).twice # Old UX still requires the busy channel

      artifact.update(name: "new name")
    end
  end

  context "expired?" do
    test "artifacts are not expired if they were created less than 90 days ago and expires_at is unset" do
      artifact = create(:artifact, check_suite: @check_suite, source_url: "https://logs.github.com/some-unique-slug-step1", created_at: 89.days.ago)
      refute artifact.expired?
    end

    test "artifacts are expired if they were created more than 90 days ago and expires_at is unset" do
      artifact = create(:artifact, check_suite: @check_suite, source_url: "https://logs.github.com/some-unique-slug-step1", created_at: 92.days.ago)
      assert artifact.expired?
    end

    test "respects expires_at if it is set" do
      artifact = create(:artifact, check_suite: @check_suite, source_url: "https://logs.github.com/some-unique-slug-step1", expires_at: 10.days.ago)
      assert artifact.expired?
    end
  end

  context "not_expired?" do
    test "artifacts are not expired if they were created less than 90 days ago and expires_at is unset" do
      artifact = create(:artifact, check_suite: @check_suite, source_url: "https://logs.github.com/some-unique-slug-step1", created_at: 89.days.ago)
      assert artifact.not_expired?
    end

    test "artifacts are expired if they were created more than 90 days ago and expires_at is unset" do
      artifact = create(:artifact, check_suite: @check_suite, source_url: "https://logs.github.com/some-unique-slug-step1", created_at: 92.days.ago)
      refute artifact.not_expired?
    end

    test "respects expires_at if it is set" do
      artifact = create(:artifact, check_suite: @check_suite, source_url: "https://logs.github.com/some-unique-slug-step1", expires_at: 10.days.ago)
      refute artifact.not_expired?
    end
  end

  context "create" do
    test "emits hydro ADD event after being created", skip_enterprise: !GitHub.hydro_enabled? do
      assert_hydro_messages(count: 0, schema: "github.actions.v0.ArtifactStorageEvent")

      artifact = create(:artifact, check_suite: @check_suite, expires_at: 90.days.from_now)

      assert_hydro_messages(count: 1, schema: "github.actions.v0.ArtifactStorageEvent")

      message = decoded_hydro_messages.find { |msg| msg.schema == "github.actions.v0.ArtifactStorageEvent" }.data.message

      assert_equal @check_suite.repository_id, message[:artifact_repository_id]
      assert_equal :ADD, message[:artifact_event_type]
      assert_equal artifact.size, message[:artifact_size_in_bytes]
      assert_equal artifact.check_suite_id, message[:check_suite_id]
      assert_equal artifact.expires_at.to_i, message[:expires_at][:seconds]
    end
  end

  context "destroy" do
    test "emits hydro removal event before being deleted", skip_enterprise: !GitHub.hydro_enabled? do
      artifact = create(:artifact, check_suite: @check_suite, expires_at: 90.days.from_now)

      mock_delete_artifact(
        artifact_name: artifact.name,
        check_suite: @check_suite,
      )

      assert_hydro_messages(count: 1, schema: "github.actions.v0.ArtifactStorageEvent")

      artifact.destroy

      assert_hydro_messages(count: 2, schema: "github.actions.v0.ArtifactStorageEvent")

      message = decoded_hydro_messages.reverse.find { |msg| msg.schema == "github.actions.v0.ArtifactStorageEvent" }.data.message

      assert_equal @check_suite.repository_id, message[:artifact_repository_id]
      assert_equal :REMOVE, message[:artifact_event_type]
      assert_equal artifact.size, message[:artifact_size_in_bytes]
      assert_equal artifact.check_suite_id, message[:check_suite_id]
      assert_equal artifact.expires_at.to_i, message[:previously_expired_at][:seconds]
    end

    test "emits hydro removal event for billing even if storage deletion fails", skip_enterprise: !GitHub.hydro_enabled? do
      artifact = create(:artifact, check_suite: @check_suite, expires_at: 90.days.from_now)

      mock_delete_artifact(
        artifact_name: artifact.name,
        check_suite: @check_suite,
        returns_error: true
      )

      assert_hydro_messages(count: 1, schema: "github.actions.v0.ArtifactStorageEvent")

      artifact.destroy

      assert_hydro_messages(count: 2, schema: "github.actions.v0.ArtifactStorageEvent")

      message = decoded_hydro_messages.reverse.find { |msg| msg.schema == "github.actions.v0.ArtifactStorageEvent" }.data.message

      assert_equal @check_suite.repository_id, message[:artifact_repository_id]
      assert_equal :REMOVE, message[:artifact_event_type]
      assert_equal artifact.size, message[:artifact_size_in_bytes]
      assert_equal artifact.check_suite_id, message[:check_suite_id]
      assert_equal artifact.expires_at.to_i, message[:previously_expired_at][:seconds]
    end

    test "deletes the artifact from file storage", skip_enterprise: !GitHub.hydro_enabled? do
      artifact = create(:artifact, check_suite: @check_suite)
      repository_global_relay_id = @check_suite.repository.global_relay_id

      mock_delete_artifact(
        artifact_name: artifact.name,
        check_suite: @check_suite,
      )

      artifact.destroy
    end

    test "deletes the artifact from results", skip_enterprise: !GitHub.hydro_enabled? do
      ActionsResults::Twirp::ArtifactClient
        .any_instance
        .expects(:delete_artifact)
        .returns(TwirpResponse.new(
          status: 200,
          call_succeeded: true,
          value: MonolithTwirp::ActionsResults::Core::V1::DeleteArtifactFromMonolithResponse.new(
            ok: true
          )
        ))
        .once

      artifact = create(:artifact_from_results_service, check_suite: @check_suite)
      artifact.destroy
      assert_dogstats_increment(1, "actions.actions_results_artifact_delete.succeeded")
    end

    test "handles results failure", skip_enterprise: !GitHub.hydro_enabled? do
      ActionsResults::Twirp::ArtifactClient
        .any_instance
        .expects(:delete_artifact)
        .returns(TwirpResponse.new(
          status: 500,
          call_succeeded: false,
        ))
        .once

      artifact = create(:artifact_from_results_service, check_suite: @check_suite)
      artifact.destroy!
      assert_dogstats_increment(1, "actions.actions_results_artifact_delete.failed")
    end

    test "skips the individual artifact deletion from actions service when skip_file_deletion is true", skip_enterprise: !GitHub.hydro_enabled? do
      Artifact.expects(:delete_artifacts_from_actions_service).never

      artifact = create(:artifact, check_suite: @check_suite)
      artifact.skip_file_deletion = true

      artifact.destroy
    end

    test "skips the individual artifact deletion from results when skip_file_deletion is true" do
      ActionsResults::Twirp::ArtifactClient.any_instance.expects(:delete_artifact).never

      artifact = create(:artifact_from_results_service, check_suite: @check_suite)
      artifact.skip_file_deletion = true

      artifact.destroy
    end

    test "skips the individual artifact deletion from file storage when the repository and the check suite were deleted first", skip_enterprise: !GitHub.hydro_enabled? do
      artifact = create(:artifact, check_suite: @check_suite)

      mock_delete_artifact(
        artifact_name: artifact.name,
        check_suite: @check_suite,
      ).never

      @check_suite.repository.delete
      @check_suite.delete

      assert_hydro_messages(count: 1, schema: "github.actions.v0.ArtifactStorageEvent")

      artifact.reload.destroy

      assert_hydro_messages(count: 2, schema: "github.actions.v0.ArtifactStorageEvent")
      destroy_message = decoded_hydro_messages.reverse.find { |msg| msg.schema == "github.actions.v0.ArtifactStorageEvent" }.data.message

      assert_equal artifact.repository_id, destroy_message[:artifact_repository_id]
      assert_equal 0, destroy_message[:artifact_repository_owner_id]
      assert_equal :VISIBILITY_UNKNOWN, destroy_message[:artifact_repository_visibility]
      assert_equal :REMOVE, destroy_message[:artifact_event_type]
    end

    test "creates an audit log", skip_enterprise: !GitHub.hydro_enabled? do
      artifact = create(:artifact, check_suite: @check_suite, expires_at: 90.days.from_now)

      mock_delete_artifact(
        artifact_name: artifact.name,
        check_suite: @check_suite,
      )

      GitHub.context.push(actor_id: @check_suite.repository.owner.id)
      events = assert_performed_audit_entries(count: 1, only: "artifact.destroy") do
        artifact.destroy
      end

      expected_payload = {
        actor: @check_suite.repository.owner.login,
        repo: @check_suite.repository.nwo,
        operation_type: "remove",
      }

      assert_subset_hash expected_payload, events.first

      assert_nil Artifact.find_by_id(artifact.id)
    end

    test "supports emoji for name" do
      artifact = create(:artifact, name: "we ❤️ emojis")

      assert_multibyte_tracked_changes(artifact, :name)
    end
  end

  context "repository transfers owners" do
    test "triggers removal from the old owner and adds to the new owner" do
      artifact = create(:artifact, check_suite: @check_suite, expires_at: 90.days.from_now, size: 4.megabytes)
      repo = artifact.repository
      old_owner = repo.owner
      new_owner = create(:user)

      repo.transfer_ownership_to(new_owner, actor: old_owner)
      run_processor(GitHub::StreamProcessors::Actions::ArtifactStorageEventProcessor.new, allowed_primary_query_count: 5)

      old_owner_remove_event = Billing::SharedStorage::ArtifactEvent.actions_source.remove_event.find_by(owner: old_owner, source_artifact_id: artifact.id)
      assert(old_owner_remove_event.effective_at <= Time.now, "old owner effective_at should be moved forward")

      new_owner_add_event = Billing::SharedStorage::ArtifactEvent.actions_source.add_event.find_by(owner: new_owner, source_artifact_id: artifact.id)
      assert(new_owner_add_event, "new owner add event should be created")

      new_owner_remove_event = Billing::SharedStorage::ArtifactEvent.actions_source.remove_event.find_by(owner: new_owner, source_artifact_id: artifact.id)
      assert_equal(artifact.expires_at, new_owner_remove_event.effective_at)
    end

    test "does not add to new owner if artifact is expired" do
      Timecop.freeze @frozen_now do
        expired_at = 5.days.ago.change(usec: 0)
        artifact = create(:artifact, check_suite: @check_suite, expires_at: expired_at, size: 4.megabytes)
        repo = artifact.repository
        old_owner = repo.owner
        new_owner = create(:user)

        repo.transfer_ownership_to(new_owner, actor: old_owner)
        run_processor(GitHub::StreamProcessors::Actions::ArtifactStorageEventProcessor.new, allowed_primary_query_count: 1)

        old_owner_remove_event = Billing::SharedStorage::ArtifactEvent.actions_source.remove_event.find_by(owner: old_owner, source_artifact_id: artifact.id)
        assert_equal(expired_at, old_owner_remove_event.effective_at)

        new_owner_add_event = Billing::SharedStorage::ArtifactEvent.actions_source.add_event.find_by(owner: new_owner, source_artifact_id: artifact.id)
        assert_nil(new_owner_add_event)
      end
    end
  end

  context "artifact expires" do
    test "emits expired event" do
      artifact = create(:artifact, check_suite: @check_suite, expires_at: 1.hour.ago, size: 4.megabytes)

      artifact.emit_artifact_expired_event

      hydro_message = hydro_messages(schema: "github.actions.v0.ArtifactStorageEvent").last

      assert hydro_message[:artifact_id], artifact.id
      assert hydro_message[:artifact_repository_id], artifact.repository_id
      assert hydro_message[:artifact_size_in_bytes], artifact.size
      assert hydro_message[:artifact_event_type], "EXPIRED"
      assert hydro_message[:expires_at], artifact.expires_at
      assert hydro_message[:artifact_global_id], "gid://github/Artifact/#{artifact.id}"
    end
  end

  context "fetch ids from source url" do
    test "returns nil if source url is not a results url" do
      artifact = create(:artifact, check_suite: @check_suite, name: "hello-artifact", source_url: "https://logs.github.com/some-unique-slug-step1")

      assert_nil artifact.get_results_ids_from_source_url
    end

    test "returns results ids if source url is a results url" do
      artifact = create(:artifact, check_suite: @check_suite, name: "hello-artifact", source_url: "results://actions-results/run/ce7f54c7-61c7-4aae-887f-30da475f5f1a/job/ca395085-040a-526b-2ce8-bdc85f692774/artifact/hello-artifact")

      ids = artifact.get_results_ids_from_source_url
      assert ids[:workflow_job_run_backend_id], "ca395085-040a-526b-2ce8-bdc85f692774"
      assert ids[:workflow_run_backend_id], "ce7f54c7-61c7-4aae-887f-30da475f5f1a"
    end

    test "returns nil if source url is nil" do
      artifact = create(:artifact, check_suite: @check_suite, name: "hello-artifact")

      assert_nil artifact.get_results_ids_from_source_url
    end
  end
end
