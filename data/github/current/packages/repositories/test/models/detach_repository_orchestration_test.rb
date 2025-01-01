# typed: true
# frozen_string_literal: true

require "test_helper"

class DetachRepositoryOrchestrationTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @owner = create(:user)
    @root = create(:public_repository, name: "public", owner: @owner, from_example: :simple)

    @forker = create(:user)
    @fork = create(:fork_repository, fork_repo: @root, forker: @forker)

    @forker2 = create(:user)
    @fork2 = create(:fork_repository, fork_repo: @root, forker: @forker2)

    example_repo_snapshot(snapshot_spokesdb: true)
  end

  setup do
    example_repo_restore
  end

  test "copies push rules" do
    biz = Business.first || create(:business)
    org = create(:organization, business: biz, plan: "business_plus")
    org.allow_private_repository_forking(actor: org.admin, policy: Configurable::AllowPrivateRepositoryForking::EVERYWHERE)
    org2 = create(:organization,  business: biz, plan: "business_plus")
    org2.allow_private_repository_forking(actor: org2.admin, policy: Configurable::AllowPrivateRepositoryForking::EVERYWHERE)
    repo = create(:repository, owner: org, internal: true)
    org2_fork = create(:fork_repository, forker: org2.admin, organization: org2, fork_repo: repo)

    push_ruleset = build(:repository_ruleset, target: "push", source: repo)
    push_rule = build(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 77
    })

    push_ruleset.save!
    push_rule.save!

    detach_repo(org2_fork)
    org2_fork.reload

    assert_equal org2_fork.id, org2_fork.network.root.id
    push_rules = RepositoryRuleset.load_for(source: org2_fork, include_parents: false, targets: ["push"])
    assert_equal 1, push_rules.size
    rule = T.must(push_rules.first)
    assert rule.enabled?
    assert_equal 77, T.must(rule.rule_configurations.first).parameters["max_file_path_length"]
  end

  test "should publish Detached event" do
    with_hydro_publisher(GitHub.sync_hydro_publisher) do
      detach_repo(@fork)

      message = {
        repository_id: @fork.id,
        was_root: false,
        was_fork: true,
        old_network_id: @root.network_id,
        old_parent_id: @root.id,
      }
      assert_hydro_published(message, schema: "github.repositories.v1.Detached")
      assert_hydro_messages(count: 1, schema: "github.repositories.v1.Detached")
    end
  end

  test "should pick the oldest fork as the new root" do
    detach_repo(@root)
    assert_equal @fork.id, @fork.network.reload.root_id, "fork should be the new root"
  end

  test "should pick an active fork as the new root" do
    @fork.remove(@fork.owner)
    detach_repo(@root)
    assert_equal @fork2.id, @fork2.network.reload.root_id, "active fork should be elected root"
  end

  test "should pick a new root even if all are deleted" do
    # soft-delete the only fork in the network
    @fork.remove(@fork.owner)
    @fork2.remove(@fork2.owner)
    # we allow this scenario in stafftools to let a repo get away from a network and go public.
    detach_repo(@root)
    assert_equal @fork.id, @fork.network.reload.root_id, "fork should be the new root, even though it's deleted"
  end

  test "detaching an org owned private network syncs org_owned_private_network_with_forks" do
    org = create(:organization)
    org.allow_private_repository_forking(actor: org.admins.first)
    repo = create(:private_repository, owner: org)
    fork = create(:fork_repository, forker:  org.admins.first, fork_repo: repo)

    assert OrgOwnedPrivateNetworkWithForks.where(network_id: repo.network_id, owner_id: repo.owner_id).exists?

    assert_difference("::OrgOwnedPrivateNetworkWithForks.count", -1) do
      detach_repo(repo)
    end
  end

  test "detaching public root of mixed network syncs org_owned_private_network_with_forks" do
    org = create(:organization)
    org.allow_private_repository_forking(actor: org.admins.first)
    repo = create(:private_repository, owner: org)
    fork = create(:fork_repository, organization: org, forker: org.admins.first, fork_repo: repo)

    fork.remove(fork.owner, synchronous: true)
    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
      repo.toggle_visibility(actor: org.admins.first, visibility: "public")
    end

    repo.reload
    fork.reload

    # We now have a mixed network, with a public root and a private fork
    assert repo.public?
    assert fork.private?
    assert_equal repo.network_id, fork.network_id

    assert_difference("::OrgOwnedPrivateNetworkWithForks.count", 0) do
      detach_repo(repo)
    end

    repo.reload
    fork.reload

    refute OrgOwnedPrivateNetworkWithForks.where(network_id: repo.network_id, owner_id: repo.owner_id).exists?
    refute OrgOwnedPrivateNetworkWithForks.where(network_id: fork.network_id, owner_id: fork.owner_id).exists?
  end

  def detach_repo(repo, perform_jobs: [])
    o = RepositoryOrchestration.extract(repo, include_forks: false)
    perform_orchestration(o, perform_jobs:)
  end

  def perform_orchestration(orchestration, perform_jobs: [])
    jobs = ([RepositoryOrchestrationJob] + perform_jobs).uniq
    perform_enqueued_jobs(only: jobs) do
      orchestration.execute
    end
    orchestration.reload
  end
end
