# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dgit"

class PullRequestUpdateTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, plan: "pro")
    @org = create(:organization, admin: @owner)
    @repo = create(:repository, owner: @org, from_example: :review_comment_source)

    @forker = create(:user)
    @repo.add_member @forker, action: :write
    @forked = create(:fork_repository, forker: @forker, fork_repo: @repo, from_example: :review_comment_fork)
  end

  def create_pull_request
    PullRequest.create_for!(@repo,
      user: @forker,
      base: "#{@org.login}:master",
      head: "#{@forker.login}:rename-topic",
      title: "testing pull request",
      body: "just some thing",
    )
  end

  context "validations" do
    test "expects full oids for base and head" do
      update = PullRequestUpdate.new(pull_request: PullRequest.new)

      refute_predicate update, :valid?
      assert_includes update.errors[:base_oid], "should be a full commit SHA"
      assert_includes update.errors[:head_oid], "should be a full commit SHA"

      update.base_oid = "abc123"
      update.head_oid = "abc123"

      refute_predicate update, :valid?
      assert_includes update.errors[:base_oid], "should be a full commit SHA"
      assert_includes update.errors[:head_oid], "should be a full commit SHA"

      update.base_oid = "x" * 40
      update.head_oid = "x" * 40

      refute_predicate update, :valid?
      assert_includes update.errors[:base_oid], "should be a full commit SHA"
      assert_includes update.errors[:head_oid], "should be a full commit SHA"

      update.base_oid = "0dc3cbd362470af3765b1a81270da5876efd509d"
      update.head_oid = "0dc3cbd362470af3765b1a81270da5876efd509d"

      refute_predicate update, :valid?
      assert_predicate update.errors[:base_oid], :empty?
      assert_predicate update.errors[:head_oid], :empty?
    end
  end
end
