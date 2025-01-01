# typed: true
# frozen_string_literal: true

require "test_helper"

class Repositories::SupportTest < GitHub::TestCase
  fixtures do
    @user0 = create(:user, name: "user0")
    @user1 = create(:user, name: "user1")
    @user2 = create(:user, name: "user2")
    @user3 = create(:user, name: "user3")
    @user4 = create(:user, name: "user4")
    @user5 = create(:user, name: "user5")
    @user6 = create(:user, name: "user6")

    @root = create(:public_repository, owner: @user0, name: "forktest", from_example: :simple)
    @fork1 = create(:fork_repository, forker: @user1, fork_repo: @root)
    @fork2 = create(:fork_repository, forker: @user2, fork_repo: @root)
    @fork3 = create(:fork_repository, forker: @user3, fork_repo: @fork1)
    @fork4 = create(:fork_repository, forker: @user4, fork_repo: @fork2)
    @fork5 = create(:fork_repository, forker: @user5, fork_repo: @fork3)
    @deleted = create(:fork_repository, forker: @user6, fork_repo: @root)
    @network = @root.network

    @deleted.remove(User.ghost, synchronous: true)
    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  context "fix network" do
    test "invalid network" do
      invalid_id = T.must(T.must(RepositoryNetwork.last).id) + 1
      assert_raises(ActiveRecord::RecordNotFound) { Repositories::Support.fix_network(id: invalid_id) }
    end

    test "healthy network" do
      refute Repositories::Support.fix_network(id: @network.id)
    end

    test "empty network" do
      repo = create(:public_repository, owner: @user0)
      network = repo.network
      network_id = repo.network.id
      repo.delete
      assert_equal 0, network.reload.repositories.count

      errors = Repositories::Support.fix_network(id: network.id)
      assert errors
      refute RepositoryNetwork.where(id: network_id).first

      # network should be gone now
      assert_raises(ActiveRecord::RecordNotFound) { Repositories::Support.fix_network(id: network_id) }
    end

    test "deleted repo networks are ok" do
      repo = create(:public_repository, owner: @user0)
      network = repo.network
      network_id = repo.network.id
      repo.remove(User.ghost, synchronous: true)
      assert_equal 0, network.reload.repositories.count

      errors = Repositories::Support.fix_network(id: network.id)
      refute errors
      assert RepositoryNetwork.where(id: network_id).first

      # now set the root to an invalid repo id and fix it
      network.root_id = 0
      network.save
      errors = Repositories::Support.fix_network(id: network.id)
      assert errors
      assert @deleted, network.reload.root
    end

    test "nil root" do
      @root.delete
      refute @network.reload.root
      assert_nil @fork2.reload.parent

      # fix a new root
      errors = Repositories::Support.fix_network(id: @network.id)
      assert errors
      assert @network.reload.root
      assert @fork1.id, @network.root.id

      # fork2 parent should be fixed too
      assert_equal @fork1, @fork2.reload.parent
      assert_equal @fork1, @deleted.reload.parent

      # nothing left to fix
      errors = Repositories::Support.fix_network(id: @network.id)
      refute errors
    end

    test "foreign root" do
      repo = create(:public_repository, owner: @user0)
      @network.root = repo
      @network.save
      refute_equal @root, @network.reload.root

      errors = Repositories::Support.fix_network(id: @network.id)
      assert errors
      assert_equal @root, @network.reload.root

      errors = Repositories::Support.fix_network(id: @network.id)
      refute errors
    end

    test "circular reference" do
      @fork1.parent = @fork3
      @fork1.save

      @deleted.parent = nil
      @deleted.save

      assert_equal @fork1.parent, @fork3
      assert_equal @fork3.parent, @fork1
      assert_nil @deleted.parent

      errors = Repositories::Support.fix_network(id: @network.id)
      assert errors
      assert_equal @root, @fork1.reload.parent
      assert_equal @fork1, @fork3.reload.parent
      assert_equal @root, @deleted.reload.parent

      errors = Repositories::Support.fix_network(id: @network.id)
      refute errors
    end
  end

  context "fix network job" do
    test "nil root" do
      @root.delete
      refute @network.reload.root
      assert_nil @fork2.reload.parent

      # fix a new root
      RepositorySupportJob.perform_now(network_id: @network.id)
      assert @network.reload.root
      assert @fork1.id, @network.root.id
      assert_equal @fork1, @fork2.reload.parent
    end
  end

  context "delete orphaned networks" do
    test "delete orphans" do
      root1 = create(:public_repository, owner: @user0, name: "root1")
      root2 = create(:public_repository, owner: @user0, name: "root2")
      root3 = create(:public_repository, owner: @user0, name: "root3")

      # orphan the network 1 by deleting the wrong way
      root1.delete

      # delete repo in network 2
      root2.remove(User.ghost, synchronous: true)

      Repositories::Support.delete_orphaned_networks

      refute RepositoryNetwork.find_by(id: root1.source_id)
      assert RepositoryNetwork.find_by(id: root2.source_id)
      assert RepositoryNetwork.find_by(id: root3.source_id)
    end
  end

  context "find broken networks" do
    test "find broken networks" do
      root1 = create(:public_repository, owner: @user0, name: "root1")
      root2 = create(:public_repository, owner: @user0, name: "root2")
      root3 = create(:public_repository, owner: @user0, name: "root3")

      # delete the file system
      root1.rpc.remove

      # delete repo in network 2 in a healthy way
      root2.remove(User.ghost, synchronous: true)

      # delete the file system
      @fork2.remove_from_disk

      broken_repos = Repositories::Support.find_broken_repos
      broken_ids = broken_repos.map { |r| r[:id] }
      assert_same_elements [root1.id, @fork2.id], broken_ids
    end
  end
end
