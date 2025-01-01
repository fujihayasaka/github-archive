# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dgit"

class RepositoryWithMachinistTest < GitHub::TestCase
  fixtures do
    @user       = create(:user, plan: "medium")
    @repo       = create(:repository, description: "boom", owner: @user, from_example: :simple_tags_repository_test)
    @fork       = create(:fork_repository, fork_repo: @repo, forker: create(:user))
    @child      = create(:fork_repository, fork_repo: @fork, forker: create(:user))
    @grandchild = create(:fork_repository, fork_repo: @child, forker: create(:user))
    @org        = create(:organization)
    @standalone = create(:repository)
    @user.protocols = { "push" => "ssh", "clone" => "gitweb" }
    @user.save!
    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  test "creates the repository network when root repository is created" do
    refute_nil @repo.network
    assert_equal @repo.network_id, @repo.network.id
    assert_equal @repo, @repo.network.root
    network_hosts = GitHub::DGit::Routing.hosts_for_network(@repo.network.id)
    repo_hosts = GitHub::DGit::Routing.hosts_for_repo(@repo.id)
    assert_equal network_hosts.sort, repo_hosts.sort
  end

  test "establishing the network_id on forks" do
    assert_equal @repo.network_id, @fork.network_id
  end

  test "establishing the network_id on deep forks" do
    assert_equal @repo.network_id, @child.network_id
  end

  test "determining if a repo is the root of a network" do
    assert @repo.network_root?
    assert @standalone.network_root?

    assert !@fork.network_root?
    assert !@child.network_root?
  end

  test "changing the network root repository" do
    original_network_id = @fork.network_id
    assert_equal @repo, @repo.network.root
    assert_equal @repo, @fork.network.root

    @fork.make_network_root!
    assert @fork.errors.empty?
    assert @fork.network_root?
    assert !@repo.reload.network_root?
    assert_equal @fork, @repo.parent
    assert_equal @fork, @child.parent
    assert_equal @fork, @repo.network.root

    [@fork, @repo, @child].each do |repo|
      assert_equal original_network_id, repo.network_id
    end
  end

  context "#reparent!" do
    test "can't reparent under a new network" do
      assert_raises ArgumentError do
        @fork.reparent!(nil)
      end
    end

    test "can't reparent under a different network" do
      assert_raises(Repository::NetworkDependency::InvalidAncestryError) do
        @fork.reparent!(@standalone)
      end
    end

    test "can't reparent with self" do
      assert_raises(Repository::NetworkDependency::InvalidAncestryError) do
        @fork.reparent!(@fork)
      end
    end

    test "can't create circular ancestry" do
      assert_equal @fork, @child.parent
      err = assert_raises(Repository::NetworkDependency::InvalidAncestryError) { @fork.reparent!(@child) }
      assert_equal @fork, @child.parent
    end

    test "updates the org" do
      org = create(:organization)
      repo = create(:private_repository)
      repo.add_member(org.admin)
      org_repo = create(:fork_repository, forker: org.admin, fork_repo: repo, organization: org)
      forker = create(:user)
      repo.add_member(forker)
      fork = create(:fork_repository, forker: forker, fork_repo: repo)

      refute_nil org_repo.organization
      assert_nil fork.organization

      fork.reparent!(org_repo)
      fork.reload
      assert_equal org, fork.organization
    end

    test "successfully reparents a fork with its grandparent" do
      assert_equal @fork, @child.parent
      @child.reparent!(@repo)
      [@child, @repo, @fork].each(&:reload)
      assert_equal @repo, @fork.parent
      assert_equal @repo, @child.parent
      assert_equal @repo.root, @child.root
      assert_equal @repo.root, @fork.root
    end

    test "can't reparent a fork with a deeply nested parent" do
      Repository::NetworkDependency.stub_const(:MAX_PARENT_DEPTH, 1) do
        assert_raises(Repository::NetworkDependency::InvalidAncestryError) { @grandchild.reparent!(@fork) }
      end
    end

    test "sets the new network root when reparenting a root repo" do
      assert_equal @repo, @fork.parent
      @repo.reparent!(@fork)
      [@child, @repo, @fork].each(&:reload)
      assert_equal @fork, @repo.parent
      assert_equal @repo.network.root, @fork
      assert_nil @fork.parent
      assert_equal @child.root, @fork.root
      assert_equal @child.root, @repo.root
    end
  end

  test "checking whether a repo is part of the same network" do
    assert @repo.in_network?(@fork)
    assert @fork.in_network?(@child)
    assert @repo.in_network?(@child)

    assert @fork.in_network?(@repo)
    assert @child.in_network?(@repo)
    assert @child.in_network?(@fork)

    assert !@standalone.in_network?(@repo)
    assert !@standalone.in_network?(@fork)
    assert !@standalone.in_network?(@child)

    assert !@repo.in_network?(@standalone)
    assert !@fork.in_network?(@standalone)
    assert !@child.in_network?(@standalone)

    [@repo, @fork, @child, @standalone].each do |repo|
      assert repo.in_network?(repo)
    end

    @repo.source_id = nil
    @fork.source_id = nil
    assert !@repo.in_network?(@fork)
    assert !@fork.in_network?(@repo)

    assert !@child.in_network?(nil)
  end

  test "accesses GitHub::Unsullied::Wiki" do
    assert_kind_of GitHub::Unsullied::Wiki, @repo.unsullied_wiki
    assert_equal "#{@repo.owner}/#{@repo}.wiki.git", @repo.unsullied_wiki.path
  end

  test "fsck a repository" do
    @simple = create(:repository, from_example: :simple)
    assert_equal "", @simple.fsck
    output = @simple.fsck!
    refute_equal "", output
    assert_equal output, @simple.fsck
    assert_equal 3, output.scan("==> git nw-fsck").size

    # Retrieving last fsck output works even if one replica has none.
    replicas = GitHub::DGit::Routing.all_repo_replicas(@simple.id)
    assert_equal 3, replicas.size
    route = replicas[0].to_route(@simple.original_shard_path)
    FileUtils.rm "#{route.path}/fsck"
    output2 = @simple.fsck
    assert_equal 2, output2.scan("==> git nw-fsck").size
  end

  test "picks user push protocol" do
    selector(@user)
    assert_equal "ssh", selector.push_protocol
    assert_equal @repo.ssh_url, selector.push_url
  end

  test "picks user clone protocol" do
    selector(@user)
    assert_equal "gitweb", selector.clone_protocol
    assert_equal @repo.gitweb_url, selector.clone_url
  end

  test "picks default with invalid user preferences" do
    @user.protocols["push"] = "abc"
    assert_equal "http", selector(@user).push_protocol
  end

  test "picks default push protocol" do
    assert_equal "http", selector.clone_protocol
    assert_equal @repo.http_url, selector.clone_url
  end

  test "git_lfs_enabled on root repository" do
    @repo.stubs(:git_lfs_config_enabled?).returns(true)
    assert @repo.network_root?
    assert @repo.git_lfs_enabled?
  end

  test "git_lfs_enabled on fork" do
    @fork.stubs(:git_lfs_config_enabled?).returns(false)
    refute @fork.network_root?

    assert_equal @repo, @fork.root
    assert @repo.network_root?
    @fork.root.stubs(:git_lfs_config_enabled?).returns(true)

    assert @fork.git_lfs_enabled?

    @fork.root.stubs(:git_lfs_config_enabled?).returns(false)
    refute @fork.git_lfs_enabled?
  end

  test "git_lfs_enabled on fork with missing root" do
    @fork.stubs(:git_lfs_config_enabled?).returns(true)
    refute @fork.network_root?

    # simulate db inconsistency by removing the repo network root
    Repository.where(id:  @repo.id).delete_all

    assert_nil @fork.root
    assert @fork.git_lfs_enabled?

    @fork.stubs(:git_lfs_config_enabled?).returns(false)
    refute @fork.git_lfs_enabled?
  end

  def selector(user = nil)
    @selector ||= @repo.protocol_selector(user)
  end

end
