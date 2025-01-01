# typed: true
# frozen_string_literal: true

require "test_helper"

class WebSocketNotificationsTriggeredViaMergeabilityChangesTest < GitHub::TestCase
  setup do
    @user   = create(:user, login: "owner")
    @forker = create(:user, login: "forker")
    @repo   = create(:repository, owner: @user, from_example: :pull_request_source)
    @fork, msg = @repo.fork(forker: @forker)

    example_repo :pull_request_fork, @fork

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

  test "mergeability includes updates to base branch, head branch, and head commit statuses" do
    channel = GitHub::WebSocket::Channels.pull_request_mergeable(@pull)
    assert_includes channel, GitHub::WebSocket::Channels.commit(@pull.base_repository, @pull.head_sha)
    assert_includes channel, GitHub::WebSocket::Channels.branch(@pull.base_repository, @pull.base_ref)
    assert_includes channel, GitHub::WebSocket::Channels.branch(@pull.head_repository, @pull.head_ref)
  end

  test "mergeability across forks includes updates to base branch, head branch, and head commit statuses" do
    channel = GitHub::WebSocket::Channels.pull_request_mergeable(@fork_pull)
    assert_includes channel, GitHub::WebSocket::Channels.commit(@fork_pull.base_repository, @fork_pull.head_sha)
    assert_includes channel, GitHub::WebSocket::Channels.branch(@fork_pull.base_repository, @fork_pull.base_ref)
    assert_includes channel, GitHub::WebSocket::Channels.branch(@fork_pull.head_repository, @fork_pull.head_ref)
  end

  test "mergeability across forks when the head repository is deleted" do
    @fork_pull.head_repository.destroy
    @fork_pull.reload
    channel = GitHub::WebSocket::Channels.pull_request_mergeable(@fork_pull)
    assert_includes channel, GitHub::WebSocket::Channels.commit(@fork_pull.base_repository, @fork_pull.head_sha)
    assert_includes channel, GitHub::WebSocket::Channels.branch(@fork_pull.base_repository, @fork_pull.base_ref)
  end
end
