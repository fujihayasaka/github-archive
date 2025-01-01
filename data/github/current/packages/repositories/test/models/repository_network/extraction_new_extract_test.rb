# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dgit"

class RepositoryNetworkExtractionNewExtractTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, plan: "medium")
    @repo  = create(:private_repository, owner: @owner, from_example: :forkable)

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

    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  def extract(repo, network_id: nil, synchronous: false)
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
      repo.extract!(network_id:, synchronous:)
    end
    repo.reload
    repo.dgit_reload_routes! # need to flush git routes separately
  end

  test "new extract is not bothered by known-obsolete files" do
    ancient_file = File.join(@fork.shard_path, "dag.cache")
    File.new(ancient_file, "w").close
    FileUtils.touch(ancient_file, mtime: Time::utc(2015, 01, 01))
    extract(@fork)
    refute_nil @fork.reload.network
    refute_equal @network, @fork.network
    assert File.exist?(@fork.shard_path), "fork should exist on disk"
    refute File.exist?(File.join(@fork.shard_path, "dag.cache")), "obsolete file should not be copied"
    DGit.check_replicas @fork
  end

  test "new extract is not bothered by known-obsolete files in wiki repos" do
    RepositoryWiki.create(repository: @fork)
    wiki = @fork.unsullied_wiki
    wiki.setup_git_repository
    ancient_file = File.join(@fork.unsullied_wiki.shard_path, "dag.cache")
    File.new(ancient_file, "w").close
    FileUtils.touch(ancient_file, mtime: Time::utc(2015, 01, 01))
    extract(@fork)
    refute_nil @fork.reload.network
    refute_equal @network, @fork.network
    assert File.exist?(@fork.shard_path), "fork should exist on disk"
    refute File.exist?(File.join(@fork.shard_path, "dag.cache")), "obsolete file should not be copied"
    DGit.check_replicas @fork
  end

  test "new extract raises an error if the network to copy has unrecognized files" do
    RepositoryNetwork.any_instance.stubs(:enough_space_to_receive?).returns(true)
    File.new(File.join(@fork.shard_path, "old_svn_repo.svn"), "w").close

    extract(@fork)
    o = RepositoryOrchestration.where(repository_id: @fork.id).last
    assert_equal "failed", T.must(o).state

    DGit.check_replicas @fork
  end

  test "instruments extracting a repo into a new network" do
    events = subscribe "repo.extract"

    expected_payload = {
      repo: @fork.nwo,
      repo_id: @fork.id,
      public_repo: @fork.public?,
      old_network_id: @network.id
    }

    extract(@fork)

    assert event = events.pop, "a repo.extract event was expected"
    assert_equal expected_payload, event.payload
  end
end
