# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryConsistencyCheckTest < GitHub::TestCase
  fixtures do
    @owner = create :user, login: "owner"
    @repo = create(:repository, name: "some-repo", owner: @owner)

    @forker = create(:user, login: "fork-owner")
    @fork = create(:fork_repository, forker: @forker, fork_repo: @repo)

    @forker2 = create(:user, login: "fork-owner2")
    @fork2 = create(:fork_repository, forker: @forker2, fork_repo: @repo)

    @fork_forker = create(:user, login: "fork-of-fork-owner")
    @fork_of_fork = create(:fork_repository, forker: @fork_forker, fork_repo: @fork)
  end

  context "verify_network_consistency" do
    test "shows no issues" do
      assert_equal [], @repo.verify_network_consistency
    end

    test "shows no parent error" do
      Repository.where(id: @repo.id).update_all(parent_id: 999999999)
      assert_includes @repo.verify_network_consistency, "error: network has no root"
    end

    test "parent missing parent" do
      @repo.delete
      assert_includes @repo.verify_network_consistency, "error: repository fork-owner/some-repo parent is missing: #{@repo.id}"
    end

    test "parent different networks" do
      network_id = create(:repository_network).id
      @fork.update_columns(source_id: network_id)
      assert_includes @repo.verify_network_consistency, "error: repository fork-of-fork-owner/some-repo parent is in different network (#{@repo.network_id} != #{network_id})"
    end

    test "parent inactive" do
      Repository.where(id: @repo.id).update_all(active: nil)
      assert_includes @repo.verify_network_consistency, "error: repository fork-owner2/some-repo parent is deleted"
    end

    test "public repo parent is private" do
      Repository.where(id: @repo.id).update_all(public: false)
      assert_includes @repo.verify_network_consistency, "error: public repository fork-owner/some-repo parent is private"
    end
  end
end
