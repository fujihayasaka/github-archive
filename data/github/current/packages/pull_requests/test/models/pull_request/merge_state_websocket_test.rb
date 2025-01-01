# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestMergeStateWebSocketTest < GitHub::TestCase
  setup do
    @user   = create(:user, login: "owner")
    @forker = create(:user, login: "forker")
    @repo   = create(:repository, owner: @user, from_example: :pull_request_source)
    @fork, msg = @repo.fork(forker: @forker)

    example_repo :pull_request_fork,   @fork

    # just make a branch called "topic" for clarity
    @repo.refs.create("refs/heads/topic",
                      @repo.refs.find("master-forward-2").target_oid,
                      @user)

    @fork.refs.create("refs/heads/fork-topic",
                      @fork.refs.find("outsider-topic").target_oid,
                      @user)
    @pull = PullRequest.create_for!(@repo,
      user: @user,
      base: "#{@user}:master",
      head: "#{@user}:topic",
      title: "test pull",
      body: "aw yea")

    @fork_pull = PullRequest.create_for!(@repo,
      user: @forker,
      base: "master",
      head: "#{@forker}:fork-topic",
      title: "test fork pull",
      body: "aw no")
  end

  test "merge state update is triggered when merge state is recalculated and notify_on_merge_state_change feature flag is enabled" do
    GitHub.flipper[:notify_on_merge_state_change].enable
    channel = GitHub::WebSocket::Channels.pull_request_git_merge_state(@pull)
    GitHub::WebSocket.stubs(:notify_pull_request_channel).returns([])
    GitHub::WebSocket.expects(:notify_pull_request_channel)
      .with(@pull, channel, has_key(:pull_request_id))
      .once

    @pull.create_merge_commit
  end

  test "merge state update is not triggered when merge state is recalculated and notify_on_merge_state_change feature flag is disabled" do
    GitHub.flipper[:notify_on_merge_state_change].disable
    channel = GitHub::WebSocket::Channels.pull_request_git_merge_state(@pull)
    GitHub::WebSocket.stubs(:notify_pull_request_channel).returns([])
    GitHub::WebSocket.expects(:notify_pull_request_channel)
      .with(@pull, channel, has_key(:pull_request_id))
      .never

    @pull.create_merge_commit
  end
end
