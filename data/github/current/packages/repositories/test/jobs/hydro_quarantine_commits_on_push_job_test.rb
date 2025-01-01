# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroQuarantineCommitsOnPushJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include DogstatsTestHelpers
  include HydroTestHelpers
  include GitHub::LoggerHelper
  include PushTestHelper

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

      with_hydro_publisher(GitHub.aqueduct_fallback_hydro_publisher.hydro_publisher) do
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

      with_hydro_publisher(GitHub.aqueduct_fallback_hydro_publisher.hydro_publisher) do
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

  test "handles missing quarantine" do
    SpokesAPI::Client.any_instance.stubs(:list_quarantine_commits).raises(SpokesAPI::NotFound.new("quarantine directory could not be found"))

    assert_logged(
      "Body" => "Failed to list quarantine commits",
      "gh.job.name" => "HydroQuarantineCommitsOnPushJob",
      "gh.push_state" => @message[:quarantine_push_state].strip,
      "gh.repo.id" => @repository.id.to_s,
      "exception.message" => "quarantine directory could not be found",
      "gh.request_id" => "request_123",
    ) do
      perform_hydro_message_job(@message.merge(request_context: { request_id: "request_123" }), schema: "github.repositories.v1.Pushed", queue: "hydro_quarantine_commits_on_push")
    end

    assert_dogstats_increment 1, "quarantine_commits_on_push_job.quarantine_not_found"
  end

  test "retries on spokes resource exhausted errors 9 times" do
    SpokesAPI::Client.any_instance.stubs(:list_quarantine_commits)
      .raises(SpokesAPI::ResourceExhausted)
      .then.raises(SpokesAPI::ResourceExhausted)
      .then.raises(SpokesAPI::ResourceExhausted)
      .then.raises(SpokesAPI::ResourceExhausted)
      .then.raises(SpokesAPI::ResourceExhausted)
      .then.raises(SpokesAPI::ResourceExhausted)
      .then.raises(SpokesAPI::ResourceExhausted)
      .then.raises(SpokesAPI::ResourceExhausted)
      .then.raises(SpokesAPI::ResourceExhausted)
      .then.returns(@first_page)
      .then.returns(@second_page)

    trigger_push_event(@repository.shard_path, @repository.owner, [], perform_hydro_push_jobs: [HydroQuarantineCommitsOnPushJob], **@message)

    with_hydro_publisher(GitHub.aqueduct_fallback_hydro_publisher.hydro_publisher) do
      assert_hydro_messages(count: 2, schema: "github.repositories.v1.CommitsCreated")
    end
  end

  test "Listing quarantine commits picks up from last cursor on resource exhausted error" do
    SpokesAPI::Client.any_instance.unstub(:list_quarantine_commits)
    # Load the first page successfully
    SpokesAPI::Client.any_instance.expects(:list_quarantine_commits).with(
      push_state: @push_state,
      cursor: nil,
    ).once.returns(@first_page)

    # Error and retry when loading the second page.
    # Then, on retry, pass in the cursor from the first page.
    SpokesAPI::Client.any_instance.expects(:list_quarantine_commits).with(
      push_state: @push_state,
      cursor: @first_page.next_cursor,
    ).twice.raises(SpokesAPI::ResourceExhausted).then.returns(@second_page)

    trigger_push_event(@repository.shard_path, @repository.owner, [], perform_hydro_push_jobs: [HydroQuarantineCommitsOnPushJob], **@message)

    with_hydro_publisher(GitHub.aqueduct_fallback_hydro_publisher.hydro_publisher) do
      assert_hydro_messages(count: 2, schema: "github.repositories.v1.CommitsCreated")
    end
  end if GitHub.flipper[:quarantine_job_retry_cursor].enabled?

  private

  def list_quarantine_commits_response(size:, has_next_page: nil)
    GitHub::Spokes::Proto::Commits::V1::ListCommitsResponse.new(
      commits: [GitHub::Spokes::Proto::Commits::V1::CommitItem.new(oid: GitHub::Spokes::Proto::Types::V1::ObjectID.new(id: SecureRandom.hex(20)))] * size,
      next_cursor: has_next_page && GitHub::Spokes::Proto::Types::V1::Cursor.new(cursor: "cursor-#{SecureRandom.hex(4)}"),
    )
  end
end
