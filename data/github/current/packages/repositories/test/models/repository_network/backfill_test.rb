# typed: true
# frozen_string_literal: true

require "test_helper"
require "github/transitions/backfill_repository_networks"

class RepositoryNetworkBackfillTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, name: "mrowner", plan: "medium")
    @repo  = create(:repository, name: "network_test", owner: @owner)
    @repos = Array.new(1) { create(:fork_repository, forker: create(:user), fork_repo: @repo) }
    @repos.last.update_attribute :pushed_at, Time.now + 100000
    @network = @repo.reload_network
  end

  test "recalculating attributes from repositories table" do
    refute_nil @repo.source_id
    assert_equal "localhost", @repo.route

    @network.recalculate!
    assert_equal GitHub.dgit_default_copies, GitHub::DGit::Routing.all_network_replicas(@network.id).size
    assert_equal 0, @network.pushed_count
    assert_equal @repos.last.pushed_at.to_i, @network.pushed_at.to_i
    assert_equal 0, @network.pushed_count_since_maintenance
    assert_equal @repo.id, @network.root_id
    assert_equal @repo, @network.root
  end

  test "backfilling a network record" do
    @repo.network.destroy
    assert !RepositoryNetwork.exists?(@network.id)
    RepositoryNetwork.backfill!(@repo.source_id)
    assert RepositoryNetwork.exists?(@network.id)
  end

  test "running the backfill transition" do
    @repo.network.destroy
    assert !RepositoryNetwork.exists?(@network.id)

    trans = GitHub::Transitions::BackfillRepositoryNetworks.new
    trans.perform

    assert RepositoryNetwork.exists?(@network.id)
  end
end
