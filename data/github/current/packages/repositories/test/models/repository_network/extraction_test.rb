# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dgit"

class RepositoryNetworkExtractionTest < GitHub::TestCase

  fixtures do
    @owner = create(:user, plan: "medium")
    @repo  = create(:private_repository, owner: @owner, from_example: :forkable)
    @repo.allow_private_repository_forking(actor: @owner)
    @public_repo = create(:repository, from_example: :forkable)
    @public_fork = create(:fork_repository, forker: create(:user), fork_repo: @public_repo)
    @public_fork_fork = create(:fork_repository, forker: create(:user), fork_repo: @public_fork)

    @repos = Array.new(4) do
      user = create(:user, plan: "micro")
      @repo.add_member user
      create(:fork_repository, fork_repo: @repo, forker: user)
    end

    @fork = @repos.first
    user = create(:user).tap { |u| @fork.add_member u }

    @forkfork = create(:fork_repository, fork_repo: @fork, forker: user)
    @repos << @forkfork

    @repos.last.update_attribute :pushed_at, Time.now + 100000

    @network = @repo.reload_network
    @public_network = @public_repo.reload_network

    @repo2 = create(:repository)
    @network2 = @repo2.network

    @user = create(:user, plan: "micro")
    @user_repo = create(:private_repository, owner: @user, from_example: :forkable)
    @user_repo.allow_private_repository_forking(actor: @user)
    @user2 = create(:user, plan: "micro")
    @user3 = create(:user, plan: "micro")
    @user_repo.add_member @user2
    @user_repo.add_member @user3

    @user2_fork = create(:fork_repository, fork_repo: @user_repo, forker: @user2)
    @user3_fork = create(:fork_repository, fork_repo: @user2_fork, forker: @user3)

    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  def new_extract(repo)
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
      repo.new_extract!
    end
    repo.reload
    repo.dgit_reload_routes! # need to flush git routes separately
  end

  test "extracting the only repo in a network does nothing" do
    assert_equal @network2, @repo2.network
    assert_equal @repo2, @network2.root

    new_extract(@repo2)
    @network2.reload

    assert_equal @network2, @repo2.network
    assert_equal @repo2, @network2.root
    DGit.check_replicas @repo2
  end

  test "if listing files raises an error during extraction, forks are returned to their previous state" do
    old_network = @public_fork.network
    RepositoryNetwork.any_instance.stubs(:enough_space_to_receive?).returns(true)
    File.new(File.join(@public_fork.shard_path, "old_svn_repo.svn"), "w").close

    new_extract(@public_fork)
    o = RepositoryOrchestration.where(repository_id: @public_fork.id).last
    assert_equal "failed", T.must(o).state

    @public_fork.reload
    @public_fork_fork.reload
    assert_equal old_network, @public_fork.network
    assert_equal old_network, @public_fork_fork.network
    refute @public_fork.locked?
    refute @public_fork_fork.locked?
    DGit.check_replicas @public_fork
  end

  test "if preparing the copy raises an error during extraction, forks are returned to their previous state" do
    old_network = @public_fork.network
    new_network = create :repository_network
    extraction = RepositoryNetwork::Storage::Extraction.new(old_network, new_network, [@public_fork, @public_fork_fork])
    new_network.rpc.expects(:prepare_copy_fork).raises(GitRPC::CommandFailed.new({ "ok" => false, "out" => "error", "status" => "1", "argv" => [] }))

    assert_raises(RepositoryNetwork::Storage::CopyForkFailed) do
      extraction.extract!
    end

    @public_fork.reload
    @public_fork_fork.reload
    assert_equal old_network, @public_fork.network
    assert_equal old_network, @public_fork_fork.network
    refute @public_fork.locked?
    refute @public_fork_fork.locked?
    DGit.check_replicas @public_fork, @public_fork_fork
  end

  test "if the copy raises an error during extraction, forks are returned to their previous state" do
    old_network = @public_fork.network
    new_network = create :repository_network
    extraction = RepositoryNetwork::Storage::Extraction.new(old_network, new_network, [@public_fork, @public_fork_fork])
    new_network.rpc.expects(:prepare_copy_fork).at_least_once.
      returns(nil)

    new_network.rpc.expects(:copy_fork).at_least_once.
      raises(GitRPC::CommandFailed.new({ "ok" => false, "out" => "error", "status" => "1", "argv" => [] }))

    assert_raises(RepositoryNetwork::Storage::CopyForkFailed) do
      extraction.extract!
    end

    @public_fork.reload
    @public_fork_fork.reload
    assert_equal old_network, @public_fork.network
    assert_equal old_network, @public_fork_fork.network
    refute @public_fork.locked?
    refute @public_fork_fork.locked?
    DGit.check_replicas @public_fork, @public_fork_fork
  end

  test "extracting a repository creates a new network and moves it on disk" do
    RepositoryWiki.create(repository: @public_fork)
    RepositoryWiki.create(repository: @public_fork_fork)
    wiki = @public_fork.unsullied_wiki
    wiki.setup_git_repository
    @public_fork.reload
    assert_equal @public_repo, @public_repo.network.root
    assert_equal @public_repo, @public_fork_fork.network.root

    old_shard = @public_fork.shard_path
    new_extract(@public_fork)
    refute_nil @public_fork.network
    refute_equal @public_network, @public_fork.network
    assert_equal @public_network, @public_fork.network.parent
    assert_equal @public_fork.network_id, @public_fork.network.id
    assert_equal @public_fork, @public_fork.network.root

    wiki_path = "#{@public_fork.network.storage_path}/#{@public_fork.id}.wiki.git"
    assert_equal wiki_path, @public_fork.unsullied_wiki(true).original_shard_path, "wikis should be moved"

    refute_equal old_shard, @public_fork.shard_path

    DGit.paths_for_repo(@public_fork).each do |path|
      assert File.exist?(path), "fork should exist at #{path}"
    end

    DGit.paths_for_repo(@public_fork.unsullied_wiki).each do |path|
      assert File.exist?(File.join(path, "config")), "config should exist in wiki dest: #{path}"
      assert !File.executable?(File.join(path, "config")), "#{path}/config should not be executable"
    end

    @public_fork_fork.reload
    DGit.paths_for_repo(@public_fork_fork).each do |path|
      assert File.exist?(path), "fork of fork should exist on at #{path}"
    end

    assert_equal @public_repo, @public_repo.reload_network.root
    DGit.check_replicas @public_fork
  end

  test "instruments extracting a repo" do
    events = subscribe "repo.extract"

    expected_payload = {
      repo: @public_fork.nwo,
      repo_id: @public_fork.id,
      public_repo: @public_fork.public?,
      old_network_id: @public_network.id
    }

    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @public_fork.extract!(network_id: @network2.id) }

    assert event = events.pop, "a repo.extract event was expected"
    assert_equal expected_payload, event.payload
  end
end
