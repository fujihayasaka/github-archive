# typed: true
# frozen_string_literal: true

require "test_helper"

class ReviewRequestReasonTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, login: "owner", plan: "micro")
    @forker = create(:user)

    @source = create(:private_repository, owner: @owner, name: "source", from_example: :review_comment_fork)
    @source.add_member @forker, action: :write

    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :review_comment_fork)

    @issue = create(:issue, user: @forker, repository: @source)
    @pull =
      create(:pull_request,
        repository: @source,
        base_repository: @source,
        base_user: @source.owner,
        base_ref: "master",
        head_repository: @fork,
        head_user: @fork.owner,
        head_ref: "topic",
        issue: @issue,
        user: @forker,
      )
    @issue.pull_request = @pull

    @request = @pull.review_requests.create!(reviewer: @owner)
  end

  test "validats codeowners_tree_oid" do
    reason = @request.reasons.build codeowners_path: "CODEOWNERS", codeowners_line: 1, codeowners_pattern: "*"

    refute_predicate reason, :valid?
    assert_includes reason.errors[:codeowners_tree_oid], "can't be blank"

    reason.codeowners_tree_oid = "bad data"
    refute_predicate reason, :valid?
    assert_includes reason.errors[:codeowners_tree_oid], "is invalid"

    reason.codeowners_tree_oid = "abcdef7"
    refute_predicate reason, :valid?
    assert_includes reason.errors[:codeowners_tree_oid], "is invalid"

    reason.codeowners_tree_oid = "725a9899207f0b65f51f27dba5eb77822edaf740"
    assert_predicate reason, :valid?
  end

  test "validats codeowners_path" do
    reason = @request.reasons.build codeowners_tree_oid:  "725a9899207f0b65f51f27dba5eb77822edaf740", codeowners_line: 1, codeowners_pattern: "*"

    refute_predicate reason, :valid?
    assert_includes reason.errors[:codeowners_path], "can't be blank"

    reason.codeowners_path = ".github/CODEOWNERS"
    assert_predicate reason, :valid?
  end

  test "validats codeowners_line" do
    reason = @request.reasons.build codeowners_tree_oid:  "725a9899207f0b65f51f27dba5eb77822edaf740", codeowners_path: "CODEOWNERS", codeowners_pattern: "*"

    refute_predicate reason, :valid?
    assert_includes reason.errors[:codeowners_line], "can't be blank"

    reason.codeowners_line = "bad data"
    refute_predicate reason, :valid?
    assert_includes reason.errors[:codeowners_line], "is not a number"

    reason.codeowners_line = 42
    assert_predicate reason, :valid?
  end

  test "validats codeowners_pattern" do
    reason = @request.reasons.build codeowners_tree_oid:  "725a9899207f0b65f51f27dba5eb77822edaf740", codeowners_path: "CODEOWNERS", codeowners_line: 1

    refute_predicate reason, :valid?
    assert_includes reason.errors[:codeowners_pattern], "can't be blank"

    reason.codeowners_pattern = "*.js"
    assert_predicate reason, :valid?
  end

  context "#async_codeowners_path_uri" do
    test "provides a URI of the codeowners path" do
      @commit = @source.refs.find(@pull.base_ref_name).append_commit({ message: "Add CODEOWNERS file", committer: @source.owner }, @source.owner) do |files|
        files.add("CODEOWNERS", "foobar")
      end
      reason = @request.reasons.create!(
        codeowners_tree_oid: @commit.oid,
        codeowners_path: "CODEOWNERS",
        codeowners_line: 1,
        codeowners_pattern: /foobar/,
      )

      expected_path = "/#{@source.name_with_owner}/blob/#{@commit.oid}/CODEOWNERS#L1"
      assert_equal expected_path, reason.async_codeowners_path_uri.sync.to_s
    end
  end

  test "sets `repository_id` from the review request" do
    reason = @request.reasons.create!(
      codeowners_tree_oid:  "725a9899207f0b65f51f27dba5eb77822edaf740",
      codeowners_path: "CODEOWNERS",
      codeowners_line: 1,
      codeowners_pattern: "*"
    )

    refute_nil reason.repository_id
    assert_equal @pull.repository_id, reason.repository_id
  end
end
