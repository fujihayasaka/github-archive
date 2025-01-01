# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroQuarantineCommitsOnPushJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include DogstatsTestHelpers
  include HydroTestHelpers

  fixtures do
    @repository = create(:repository, from_example: :simple)

    @push_state = "quarantine_push_state"
  end

  setup do
    @message = {
      repository_id: @repository.id,
      quarantine_push_state: Base64.encode64(@push_state),
      pushed_at: Time.current,
      pusher: @repository.owner_login,
      total_ref_count: 1,
      total_branch_count: 1,
      ref_batch_number: 1,
      enabled_flags: Repositories::HydroPushJobFlags::FLAGS.select { |f| GitHub.flipper[f].enabled? },
    }

    Spokesd.enable_spokesd

    @first_page = list_quarantine_commits_response(size: 3, has_next_page: true)
    @second_page = list_quarantine_commits_response(size: 2)
    SpokesAPI::Client.any_instance.stubs(:list_quarantine_commits)
      .returns(@first_page)
      .then.returns(@second_page)
  end

  test "enumerates quarantine commits, reports stats, and clears quarantine" do
    SpokesAPI::Client.any_instance.expects(:remove_quarantine).with(push_state: @push_state).once

    perform_hydro_message_job(@message, schema: "github.repositories.v1.Pushed", queue: "hydro_quarantine_commits_on_push")

    assert_dogstats_histogram_value(5, "quarantine_commits_on_push_job.quarantine_commits")
  end

  context "publishing CommitsCreated event" do
    test "publishes events" do
      SpokesAPI::Client.any_instance.expects(:remove_quarantine).with(push_state: @push_state).once

      perform_hydro_message_job(@message, schema: "github.repositories.v1.Pushed", queue: "hydro_quarantine_commits_on_push")

      assert_dogstats_histogram_value(5, "quarantine_commits_on_push_job.quarantine_commits")

      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        assert_hydro_published(
          {
            repository_id: @repository.id,
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            created_at: @message[:pushed_at],
            commit_shas: @first_page.commits.map(&:oid).map(&:id),
            user_login: @message[:pusher],
            enabled_flags: @message[:enabled_flags]
          },
          schema: "github.repositories.v1.CommitsCreated",
          partition_key: @repository.id)

        assert_hydro_published(
          {
            repository_id: @repository.id,
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            created_at: @message[:pushed_at],
            commit_shas: @second_page.commits.map(&:oid).map(&:id),
            user_login: @message[:pusher],
            enabled_flags: @message[:enabled_flags]
          },
          schema: "github.repositories.v1.CommitsCreated",
          partition_key: @repository.id)

        assert_hydro_messages(count: 2, schema: "github.repositories.v1.CommitsCreated")
      end
    end

    test "doesn't duplicate events for ref batches" do
      # we should only handle quarantine once per push, not per ref batch
      SpokesAPI::Client.any_instance.expects(:remove_quarantine).with(push_state: @push_state).once

      # simulate a push with many ref updates, such that we have to batch them into multiple events
      perform_hydro_message_job(@message, schema: "github.repositories.v1.Pushed", queue: "hydro_quarantine_commits_on_push")
      perform_hydro_message_job(@message.merge(ref_batch_number: 2), schema: "github.repositories.v1.Pushed", queue: "hydro_quarantine_commits_on_push")

      assert_dogstats_histogram_value(5, "quarantine_commits_on_push_job.quarantine_commits")

      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        assert_hydro_published(
          {
            repository_id: @repository.id,
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            created_at: @message[:pushed_at],
            commit_shas: @first_page.commits.map(&:oid).map(&:id),
            user_login: @message[:pusher],
            enabled_flags: @message[:enabled_flags]
          },
          schema: "github.repositories.v1.CommitsCreated",
          partition_key: @repository.id)

        assert_hydro_published(
          {
            repository_id: @repository.id,
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            created_at: @message[:pushed_at],
            commit_shas: @second_page.commits.map(&:oid).map(&:id),
            user_login: @message[:pusher],
            enabled_flags: @message[:enabled_flags]
          },
          schema: "github.repositories.v1.CommitsCreated",
          partition_key: @repository.id)

        assert_hydro_messages(count: 2, schema: "github.repositories.v1.CommitsCreated")
      end
    end
  end

  private

  def list_quarantine_commits_response(size:, has_next_page: nil)
    GitHub::Spokes::Proto::Commits::V1::ListCommitsResponse.new(
      commits: [GitHub::Spokes::Proto::Commits::V1::CommitItem.new(oid: GitHub::Spokes::Proto::Types::V1::ObjectID.new(id: SecureRandom.hex(20)))] * size,
      next_cursor: has_next_page && GitHub::Spokes::Proto::Types::V1::Cursor.new(cursor: "cursor"),
    )
  end
end
