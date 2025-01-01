# typed: true
# frozen_string_literal: true

require "test_helper"

class UserReviewedFileTest < GitHub::TestCase
  fixtures do
    @skalnik = create(:user, login: "skalnik")
    @source = create(:repository, owner: @skalnik, name: "user_reviewed_files", from_example: :user_reviewed_files)


    @pull = PullRequest.create_for!(@source,
      user: @skalnik,
      base: "master",
      head: "add-degree-symbol-file",
      title: "some changes",
      body: "body",
    )
  end

  test "can mark a file as viewed" do
    file = UserReviewedFile.new(filepath: "degree°.txt",
      head_sha: @pull.head_sha,
      pull_request: @pull,
      user: @skalnik)

    assert file.valid?
    assert file.save
  end

  test "requires file path to be part of the PR" do
    file = UserReviewedFile.new(filepath: "bogus",
      head_sha: @pull.head_sha,
      pull_request: @pull,
      user: @skalnik)

    refute file.valid?
    assert_match(/Filepath must be part of pull request/, file.errors.full_messages.first)
  end
end
