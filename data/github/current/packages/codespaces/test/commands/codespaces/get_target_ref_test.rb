# typed: true
# frozen_string_literal: true

require "test_helper"
module Codespaces
  class GetTargetRefTest < GitHub::TestCase
    self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
    fixtures do
      @user = create(:user)
      @repo = create(:repository, owner: @user, from_example: :simple)
      @master_head = @repo.heads.find_or_build("master")
      @head_ref = @repo.heads.create("patch-1", @master_head.target, @user)

      @older_commit = @head_ref.append_commit({ message: "some changes", committer: @user }, @user) do |files|
        files.add("file001", "foo")
      end
      @newer_commit = @head_ref.append_commit({ message: "more changes", committer: @user }, @user) do |files|
        files.add("file002", "bar")
      end
    end

    test "finds the head commit of a branch by its name" do
      assert_equal Codespaces::GetTargetRef.call(repository: @repo, name_or_oid: "master").target_oid, @master_head.target_oid
      assert_equal Codespaces::GetTargetRef.call(repository: @repo, name_or_oid: "patch-1").target_oid, @head_ref.target_oid
    end

    test "finds a commit by its SHA" do
      assert_equal Codespaces::GetTargetRef.call(repository: @repo, name_or_oid: @newer_commit.sha).target_oid, @head_ref.target_oid
    end

    test "when SHA is the head of more than one branch, uses detached head state" do
      # Create another branch from master and grab the duplicate head SHA
      shared_sha = @repo.heads.create("patch-2", @master_head.target, @user).target.oid

      assert_equal Codespaces::GetTargetRef.call(repository: @repo, name_or_oid: shared_sha).target_oid, shared_sha
    end
  end
end
