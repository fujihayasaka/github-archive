# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestDiffViewDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @pushable_user = create(:user)
    @repo = create(:repository, owner: @user, from_example: :pull_request_source)


    base_ref = @repo.heads.find("master")
    head_ref = @repo.heads.create("topic", base_ref.target, @repo.owner)

    head_ref.append_commit({
      message: "a change",
      committer: @repo.owner,
    }, @repo.owner) do |files|
      files.add("README.txt", "one\ntwo\nthree\n")
    end

    @pull = create(:pull_request,
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      base_ref: "master",
      head_repository: @repo,
      head_user: @repo.owner,
      head_ref: "topic",
      user: @repo.owner,
    )

  end

  setup do
    @pull.clear_ignore_whitespace_preference(@user)
  end

  test "ignore_whitespace returns false when key is not set" do
    refute @pull.ignore_whitespace?(@user)
  end

  test "ignore_whitespace returns true when key is set" do
    @pull.set_ignore_whitespace_preference(@user)
    assert @pull.ignore_whitespace?(@user)
  end

  test "clear_ignore_whitespace_preference deletes the key" do
    @pull.set_ignore_whitespace_preference(@user)
    assert @pull.ignore_whitespace?(@user)

    @pull.clear_ignore_whitespace_preference(@user)
    refute @pull.ignore_whitespace?(@user)
  end

  test "KV key uses user id and pull request number" do
    expected_key = "pull_requests/ignore_whitespace/user#{@user.id}.pr#{@pull.number}"
    assert_equal expected_key, @pull.ignore_whitespace_key(@user)
  end

  test "writes to the issues-pull-requests KV store" do
    new_key = "pull_requests/ignore_whitespace/user#{@user.id}.pr#{@pull.number}"

    @pull.set_ignore_whitespace_preference(@user)

    assert PullRequests::KV.for_repository(@repo).exists(new_key).value!

    @pull.clear_ignore_whitespace_preference(@user)

    refute PullRequests::KV.for_repository(@repo).exists(new_key).value!
  end
end
