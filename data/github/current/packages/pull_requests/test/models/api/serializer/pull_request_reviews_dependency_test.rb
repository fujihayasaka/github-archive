# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

PullRequestReviewQuery = Api::App::PlatformClient.parse <<-'GRAPHQL'
  query($id: ID!) {
    node(id: $id) {
      ... on PullRequestReview {
        ...Api::Serializer::PullRequestReviewsDependency::PullRequestReviewFragment
      }
    }
  }
GRAPHQL

PullRequestReviewCommentQuery = Api::App::PlatformClient.parse <<-'GRAPHQL'
  query($id: ID!) {
    node(id: $id) {
      ... on PullRequestReviewComment {
        ...Api::Serializer::PullRequestReviewsDependency::PullRequestReviewCommentFragment
      }
    }
  }
GRAPHQL

class PullRequestReviewsSerializersTest < Api::SerializerTestCase
  fixtures do
    @ari = create(:user, login: "ari")
    @source = create(:repository, owner: @ari, from_example: :pull_request_source)
    @bwalsh = create(:user, login: "bwalsh")
    @fork = create(:fork_repository, forker: @bwalsh, fork_repo: @source, from_example: :pull_request_fork)

    @issue = create(:issue, user: @bwalsh, repository: @source)
    @pull1 = PullRequest.create_for(@source,
      base: "master",
      head: "#{@fork.user}:topic",
      user: @issue.user,
      issue: @issue)

    @review = create(:pull_request_review, repository: @source, pull_request: @pull1, state: :commented)

    review = create(:pull_request_review, repository: @source, pull_request: @pull1, state: :pending)
    @comment1 = create(:pull_request_review_comment,
        pull_request_review: review,
        pull_request: @pull1,
        user: @ari, body: "hiya",
        commit_id: @pull1.head_sha,
        path: "file12",
        original_position: 1
    )
    review.comment!
  end

  setup do
    reset_repo_root
    example_repo :pull_request_source, @source
    example_repo :pull_request_fork,   @fork

    @pull1.create_merge_commit
  end

  context "review comments serialization" do
    test "loads basic data" do
      output = serialize_hash_method(:pull_request_review_comment_hash, @comment1)
      assert_equal "hiya", output["body"]
      assert_equal "ari", output["user"]["login"]
      assert_equal "file12", output["path"]
      assert_equal 1, output["position"]
    end

    # This should not happen, but it does and web UI also ignores them
    # (instead of crashing, see https://github.com/github/github/issues/75377)
    test "ignores comments pointing to an non-existing pull request" do
      @comment1.pull_request_id = 99999
      assert_nil output = serialize_hash_method(:pull_request_review_comment_hash, @comment1)
    end
  end

  context "#graphql_pull_request_review_hash" do
    test "payload is valid" do
      variables = {
        id: @review.global_relay_id,
      }

      results = Api::App::PlatformClient.query(PullRequestReviewQuery, variables: variables, context: { viewer: @ari })
      output = serialize_hash_method(:graphql_pull_request_review_hash, results.data.node)
      assert output.key?("id")
      assert output.key?("node_id")
      assert output.key?("user")
      assert output.key?("body")
    end

    test "payload is valid when commit doesn't exist" do
      missing_commit_oid = "1d22e6fde59c9ded9b8093cf26213a5bd9d4c5ec"
      @review.update_column(:head_sha, missing_commit_oid)

      variables = {
        id: @review.global_relay_id
      }

      results = Api::App::PlatformClient.query(PullRequestReviewQuery, variables: variables, context: { viewer: @ari })
      output = serialize_hash_method(:graphql_pull_request_review_hash, results.data.node)

      assert output.key?("commit_id")
      assert_nil output["commit_id"]
    end
  end

  context "#pull_request_review_comment_hash" do
    test "payload with reactions is valid" do
      @comment1.react(content: "heart", actor: @ari)

      output = serialize_hash_method(:pull_request_review_comment_hash, @comment1)
      assert output.key?("reactions")
    end

    test "line and position fields return sentinel value of 1 for file level comments" do
      @comment1.pull_request_review_thread.update(compressed_diff_hunk: nil, subject_type: "file", blob_position: nil)
      output = serialize_hash_method(:pull_request_review_comment_hash, @comment1)

      assert_equal "", output.fetch("diff_hunk")
      assert_equal 1, output.fetch("position")
      assert_equal 1, output.fetch("original_position")
      assert_equal 1, output.fetch("line")
      assert_equal 1, output.fetch("original_line")
    end

    test "payload includes subject type when file_level_commenting ff is enabled" do
      output = serialize_hash_method(:pull_request_review_comment_hash, @comment1)
      assert_equal "line", output.fetch("subject_type")

      @comment1.pull_request_review_thread.update(compressed_diff_hunk: nil, subject_type: "file", blob_position: nil)
      output = serialize_hash_method(:pull_request_review_comment_hash, @comment1)
      assert_equal "file", output.fetch("subject_type")
    end
  end

  context "#graphql_pull_request_review_comment_hash" do
    test "payload is valid when commit doesn't exist" do
      missing_commit_oid = "1d22e6fde59c9ded9b8093cf26213a5bd9d4c5ec"

      @comment1.pull_request_review_thread.update_column(:commit_id, missing_commit_oid)

      assert_raises GitRPC::ObjectMissing do
        @comment1.repository.commits.find(missing_commit_oid)
      end

      results = Api::App::PlatformClient.query(
        PullRequestReviewCommentQuery, variables: { id: @comment1.global_relay_id }, context: { viewer: @ari }
      )
      output = serialize_hash_method(:graphql_pull_request_review_comment_hash, results.data.node)
      assert_equal missing_commit_oid, output.fetch("commit_id")
    end
  end
end
