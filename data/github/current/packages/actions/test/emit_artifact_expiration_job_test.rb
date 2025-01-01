# typed: true
# frozen_string_literal: true

require "test_helper"

class EmitArtifactExpirationJobTest < GitHub::TestCase
  include HydroTestHelpers
  include DogstatsTestHelpers

  fixtures do
    @repo = create(:repository)

    @check_suite = create(:check_suite, :completed, :success, repository: @repo)
  end

  setup do
    enable_feature_flag(:emit_artifact_expiration)
    @artifact = create(:artifact, check_suite: @check_suite, repository: @repo, size: 100)
    # Reset inbetween tests so we don't get the add event
    reset_hydro
  end

  context "#perform" do
    test "does not emit an event or update a non-expiring artifact" do
      @artifact.update!(expires_at: 90.days.from_now, created_at: Time.now.utc)

      assert_no_changes -> { @artifact } do
        EmitArtifactExpirationJob.perform_now
      end

      refute_hydro_messages(schema: "github.actions.v0.ArtifactStorageEvent")
    end

    test "emits an event and updates an artifact with a past expires_at" do
      @artifact.update!(expires_at: 30.minutes.ago, created_at: 30.days.ago)

      EmitArtifactExpirationJob.perform_now

      @artifact.reload
      assert @artifact.expiration_emitted

      assert_hydro_published_partial({
        artifact_repository_id: @repo.id,
        artifact_repository_visibility: @repo.visibility,
        artifact_repository_owner_id: @repo.owner_id,
        check_suite_id: @artifact.check_suite_id,
        check_run_id: 0,
        artifact_name: @artifact.name,
        artifact_size_in_bytes: @artifact.size,
        expires_at: @artifact.expires_at,
        artifact_event_type: :EXPIRED,
        artifact_id: @artifact.id
      }, schema: "github.actions.v0.ArtifactStorageEvent")

      assert_dogstats_count_value 0, "emit_artifact_expiration_job.duplicate_artifacts_emitted"
      assert_dogstats_count_value 1, "emit_artifact_expiration_job.expired_artifacts_processed_batch"
    end

    test "emits an event and updates an artifact with a past created_at" do
      @artifact.update!(expires_at: Time.now - 30.minutes, created_at: 90.days.ago - 30.minutes)

      EmitArtifactExpirationJob.perform_now

      @artifact.reload
      assert @artifact.expiration_emitted

      assert_hydro_published_partial({
          artifact_id: @artifact.id,
          artifact_repository_id: @repo.id,
          artifact_event_type: :EXPIRED,
          artifact_size_in_bytes: @artifact.size,
          check_suite_id: @check_suite.id,
      }, schema: "github.actions.v0.ArtifactStorageEvent")

      assert_dogstats_count_value 0, "emit_artifact_expiration_job.duplicate_artifacts_emitted"
      assert_dogstats_count_value 1, "emit_artifact_expiration_job.expired_artifacts_processed_batch"
    end

    test "does not emit an event or update an artifact that expired prior to the job start date" do
      @artifact.update!(expires_at: Time.new(2022, 1, 1), created_at: Time.now.utc)

      assert_no_changes -> { @artifact } do
        EmitArtifactExpirationJob.perform_now
      end

      refute_hydro_messages(schema: "github.actions.v0.ArtifactStorageEvent")
    end

  end
end
