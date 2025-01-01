# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dgit"

class DGitForkingTest < GitHub::TestCase
  def assert_zero_failbot_reports
    reports = Failbot.reports.select do |r|
      !%w[github-slow-gitrpc].include? r["app"]
    end
    assert_equal 0, reports.length, "Expected zero Failbot.reports, but found this:\n#{Failbot.reports}"
  end

  fixtures do
    @user = create(:user)
    @forker = create(:user)
  end

  setup do
    @repo = create :repository, owner: @user, from_example: :simple
    @rc = GitHub::DGit::Routing.repo_checksum(@repo.network.id, @repo.id)
    @nr_host = GitHub::DGit::Routing.all_network_replicas(@repo.network_id).first.host
    Failbot.reports.clear
  end

  test "fork in DGit" do
    fork_repo, reason = @repo.fork(forker: @forker)
    fork_repo.clone_fork  # force creation of the fork's directory
    fork_repo.reload
    fc = GitHub::DGit::Routing.repo_checksum(fork_repo.network.id, fork_repo.id)

    assert fork_repo.exists_on_disk?, "#{fork_repo} should exist"
    assert !fork_repo.empty?, "#{fork_repo} should not be empty"
    refute_equal @rc, fc, "#{fork_repo} checksum should not match parent checksum"
    assert_match /^(\d+:)?[0-9a-f]{40}$/, fc
    frrs = GitHub::DGit::Routing.all_repo_replicas(fork_repo.id)
    assert_equal GitHub.dgit_default_copies, frrs.size
    frrs.each { |fr| assert fr.healthy? }

    rhosts = GitHub::DGit::Routing.hosts_for_repo(@repo.id)
    fhosts = GitHub::DGit::Routing.hosts_for_repo(fork_repo.id)
    assert_equal rhosts.first, fhosts.first  # primary reader must be the same
    assert_same_elements rhosts, fhosts      # other readers can be shuffled
  end

  test "fork in DGit when one replica is dormant" do
    assert_zero_failbot_reports
    ::DGit::set_network_replica_state_for_host(@repo.network.id, GitHub::DGit::DORMANT, @nr_host)

    fork_repo, reason = @repo.fork(forker: @forker)
    fork_repo.clone_fork  # force creation of the fork's directory
    fork_repo.reload
    fc = GitHub::DGit::Routing.repo_checksum(fork_repo.network.id, fork_repo.id)

    assert fork_repo.exists_on_disk?, "#{fork_repo} should exist"
    assert !fork_repo.empty?, "#{fork_repo} should not be empty"
    refute_equal @rc, fc, "#{fork_repo} checksum should not match parent checksum"
    assert_match /^(\d+:)?[0-9a-f]{40}$/, fc
    frrs = GitHub::DGit::Routing.all_repo_replicas(fork_repo.id)
    assert_equal GitHub.dgit_default_copies, frrs.size
    frrs.each do |fr|
      if fr.host == @nr_host
        refute fr.healthy?
      else
        assert fr.healthy?
      end
    end

    # hosts_for_repo is not used here because it only returns ACTIVE replicas.
    rhosts = GitHub::DGit::Routing.all_repo_replicas(@repo.id, false).map(&:host)
    fhosts = GitHub::DGit::Routing.all_repo_replicas(fork_repo.id, false).map(&:host)
    errmsg = "FAILED: rhosts: #{rhosts.inspect}\n" \
             "        fhosts: #{fhosts.inspect}\n" \
             "    rhosts repo_replicas(#{@repo.id}): #{GitHub::DGit::Routing.all_repo_replicas(@repo.id)}\n" \
             "fhosts repo_replicas(#{fork_repo.id}): #{GitHub::DGit::Routing.all_repo_replicas(fork_repo.id)}\n" \
             "Failbot.reports: #{Failbot.reports}\n"
    assert_same_elements rhosts, fhosts, errmsg      # other readers can be shuffled
    assert_equal rhosts.first, fhosts.first, errmsg  # primary reader must be the same
    assert_zero_failbot_reports
  end
end
