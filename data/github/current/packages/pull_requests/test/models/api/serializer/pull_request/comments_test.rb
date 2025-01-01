# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"


class Api::Serializer::CommentsTest < Api::SerializerTestCase
  fixtures do
    @owner = create(:user)
    @repo = create(:repository, owner: @owner, from_example: :simple)
    @ref = @repo.heads.create("topic", @repo.heads.find("master").target, @repo.owner)
    @commit = @ref.append_commit({ message: "Add file1", committer: @repo.owner }, @repo.owner) do |files|
      files.add("file1.txt", "line1\nline2\nline3\n")
    end
    issue = create(:issue, repository: @repo)
    @pull = PullRequest.create_for(
      @repo,
      base: "master",
      head: @ref.name,
      user: @owner,
      issue: issue
    )
    @pr_review = create(:pull_request_review, pull_request: @pull, user: @owner, body: "this is good")
    @pr_review_thread = create(:pull_request_review_thread, pull_request: @pull, pull_request_review: @pr_review)
    @pr_review_comment = create(:pull_request_review_comment,
      pull_request: @pull,
      user: @owner,
      pull_request_review: @pr_review,
      pull_request_review_thread: @pr_review_thread
    )
    @ref.freeze
    @commit.freeze
  end

  context "#pull_request_thread_comment_hash" do
    test "returns the expected base attributes" do
      output = serialize_hash_method(:pull_request_thread_comment_hash, @pr_review_comment)

      assert_equal @pr_review_comment.id, output["id"]
      assert_equal "#{GitHub.api_url}/repos/#{@repo.nwo}/pulls/#{@pull.number}/threads/#{@pr_review_thread.id}/comments/#{@pr_review_comment.id}", output["url"]
      assert_equal @pull.number, output["pull_request_id"]
      assert_equal @owner.login, output["user"]["login"]
      assert_equal "OWNER", output["author_association"]
      assert_equal @pr_review_comment.body, output["body"]
    end
  end
end
