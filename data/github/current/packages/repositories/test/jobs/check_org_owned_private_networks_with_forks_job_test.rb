# typed: true
# frozen_string_literal: true

require "test_helper"

class CheckOrgOwnedPrivateNetworksWithForksJobTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include DogstatsTestHelpers

  fixtures do
    @org = create(:organization)
    @admin = @org.admins.first
    @org.allow_private_repository_forking(actor: @admin)
    @member = create(:user)
    @org.add_member(@member)
  end

  test "logs networks which are incorrectly tracked by the org_owned_private_networks_with_forks table" do

    GitHub.presto.stubs(:run).returns([[], [[1], [2]]])

    untracked_networks = {
      "Body" => "Found networks not tracked by org_owned_private_networks_with_forks table",
      "code.namespace" => "CheckOrgOwnedPrivateNetworksWithForksJob",
      "gh.network.ids" => "[1, 2]",
    }

    incorrectly_tracked_networks = {
      "Body" => "Found networks which should not be tracked by org_owned_private_networks_with_forks table",
      "code.namespace" => "CheckOrgOwnedPrivateNetworksWithForksJob",
      "gh.network.ids" => "[1, 2]",
    }

    assert_logged(**incorrectly_tracked_networks) do
      assert_logged(**untracked_networks) do
        CheckOrgOwnedPrivateNetworksWithForksJob.perform_now
      end
    end
  end

  test "truncates network logs to first 100 incorrectly tracked networks" do

    network_ids = (1..101).map { |i| [i] }.to_a
    GitHub.presto.stubs(:run).returns([[], network_ids])

    untracked_networks = {
      "Body" => "Found networks not tracked by org_owned_private_networks_with_forks table (truncated to 100 networks)",
      "code.namespace" => "CheckOrgOwnedPrivateNetworksWithForksJob",
      "gh.network.ids" => (1..100).to_a.to_s,
    }

    incorrectly_tracked_networks = {
      "Body" => "Found networks which should not be tracked by org_owned_private_networks_with_forks table (truncated to 100 networks)",
      "code.namespace" => "CheckOrgOwnedPrivateNetworksWithForksJob",
      "gh.network.ids" => (1..100).to_a.to_s,
    }

    assert_logged(**incorrectly_tracked_networks) do
      assert_logged(**untracked_networks) do
        CheckOrgOwnedPrivateNetworksWithForksJob.perform_now
      end
    end
  end

  test "fixes networks which are untracked by the correct owner_id org_owned_private_networks_with_forks table" do
    repo = create(:private_repository, owner: @org)
    fork = create(:fork_repository, forker: @member, fork_repo: repo)

    assert OrgOwnedPrivateNetworkWithForks.find_by(network_id: repo.network.id, owner_id: @org.id)
    OrgOwnedPrivateNetworkWithForks.where(network_id: repo.network.id).update_all(owner_id: @member.id)
    assert OrgOwnedPrivateNetworkWithForks.find_by(network_id: repo.network.id, owner_id: @member.id)

    GitHub.presto.stubs(:run).returns([[], [[repo.network.id]]])

    CheckOrgOwnedPrivateNetworksWithForksJob.perform_now

    assert_dogstats_increment "repos.oopnwf.resynced", tags: ["type:untracked"]
    assert OrgOwnedPrivateNetworkWithForks.find_by(network_id: repo.network.id, owner_id: @org.id)
  end

  test "fixes networks which are untracked by the org_owned_private_networks_with_forks table" do
    repo = create(:private_repository, owner: @org)
    fork = create(:fork_repository, forker: @member, fork_repo: repo)

    assert OrgOwnedPrivateNetworkWithForks.find_by(network_id: repo.network.id, owner_id: @org.id)
    OrgOwnedPrivateNetworkWithForks.destroy_by_network_id(repo.network.id)
    refute OrgOwnedPrivateNetworkWithForks.find_by(network_id: repo.network.id, owner_id: @org.id)

    GitHub.presto.stubs(:run).returns([[], [[repo.network.id]]])

    CheckOrgOwnedPrivateNetworksWithForksJob.perform_now

    assert_dogstats_increment "repos.oopnwf.resynced", tags: ["type:untracked"]
    assert OrgOwnedPrivateNetworkWithForks.find_by(network_id: repo.network.id, owner_id: @org.id)
  end

  test "fixes networks which are incorrectly tracked by the org_owned_private_networks_with_forks table" do
    repo = create(:private_repository, owner: @org)

    refute OrgOwnedPrivateNetworkWithForks.find_by(network_id: repo.network.id, owner_id: @org.id)
    OrgOwnedPrivateNetworkWithForks.create(network_id: repo.network.id, owner_id: @org.id)
    assert OrgOwnedPrivateNetworkWithForks.find_by(network_id: repo.network.id, owner_id: @org.id)

    GitHub.presto.stubs(:run).returns([[], []]).then.returns([[], [[repo.network.id]]])

    CheckOrgOwnedPrivateNetworksWithForksJob.perform_now

    assert_dogstats_increment "repos.oopnwf.resynced", tags: ["type:should_not_be_tracked"]
    refute OrgOwnedPrivateNetworkWithForks.find_by(network_id: repo.network.id, owner_id: @org.id)
  end
end
