# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroMarkPullRequestComparisonAsSeenJobTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @user = create(:user, :verified)
    @repo = create(:repository, owner: @user, from_example: :pull_request_history)

    assert @pull = PullRequest.create_for!(@repo,
      base: "master",
      head: "topic",
      user: @user,
      title: "test PR",
    )
    assert @pull.valid?

    @queue = HydroMarkPullRequestComparisonAsSeenJob.queue_name
    @schema = "github.pull_requests.v1.MarkPullRequestComparisonAsSeen"
  end

  def perform_hydro_message_job(data, schema:, queue:, topic:)
    encoded = encode_hydro_message(data, schema: schema)
    decoded = decode_hydro_message(encoded)

    now = Time.now

    HydroMarkPullRequestComparisonAsSeenJob.new(
      protobuf: encoded,
      headers: { topic: topic }.stringify_keys,
      queue: queue,
      schema: schema,
      timestamp: now.to_i,
      timestamp_nano: now.to_r,
      message: decoded.message,
    ).perform_now
  end

  test "marks thread as read" do
    assert_nil LastSeenPullRequestRevision.find_by(user_id: @user.id)

    message = {
      pull_request_id: @pull.id,
      user_id: @user.id,
      start_oid: @pull.merge_base,
      end_oid: @pull.head_sha,
    }

    perform_hydro_message_job(message, schema: @schema, queue: @queue, topic: @schema)

    assert LastSeenPullRequestRevision.find_by(user_id: @user.id)
  end
end
