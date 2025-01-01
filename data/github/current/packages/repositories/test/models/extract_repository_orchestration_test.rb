# typed: true
# frozen_string_literal: true

require "test_helper"

class ExtractRepositoryOrchestrationTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @owner = create(:user)
    @root = create(:public_repository, name: "public", owner: @owner, from_example: :simple)

    @forker1 = create(:user)
    @fork1 = create(:fork_repository, forker: @forker1, fork_repo: @root)
    @forker2 = create(:user)
    @fork2 = create(:fork_repository, forker: @forker2, fork_repo: @root)

    @org = create(:enterprise_linked_organization)
    @member = create(:user)
    @org.add_member(@member)
    @org.allow_private_repository_forking(actor: @org.admin, policy: Configurable::AllowPrivateRepositoryForking::EVERYWHERE)

    @org_repo = create(:repository, owner: @org, internal: true, from_example: :repository_test_simple)
    @org_fork = create(:fork_repository, forker: @member, fork_repo: @org_repo, private: true)
    @org_fork.update_default_branch("special")

    # create an internal org-owned fork of an internal repo
    @int_fork = create(:fork_repository, :org_owned_internal, forker: @member, fork_repo: @org_repo, organization: @org)

    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  def compute_checksum(repo)
    nw_reader = GitHub::DGit::Routing.preferred_reader_for_network(repo.network_id)
    out = GitHub::DGit::Maintenance.recompute_checksums(repo, nw_reader)
    out[:repo]
  end

  test "extract and attach private fork" do
    assert_equal "special", @org_fork.default_branch
    before_checksum = compute_checksum(@org_fork)

    extract_repo(@org_fork)
    @org_fork.reload
    @org_fork.dgit_reload_routes!

    refute_equal @org_repo.id, @org_fork.network.root.id
    assert_equal @org_repo.id, @org_repo.network.root.id
    assert_equal @org_fork.network.id, @org_fork.network.id
    assert_equal "special", @org_fork.default_branch
    after_checksum = compute_checksum(@org_fork)
    assert_equal before_checksum, after_checksum

    o = @org_fork.attach_to!(@org_repo)
    perform_enqueued_jobs(only: RepositoryOrchestrationJob)

    @org_fork.reload
    @org_fork.dgit_reload_routes!
    assert_equal @org_repo.network.id, @org_fork.network.id
    assert_equal @org_repo.id, @org_fork.network.root.id
    assert_equal "special", @org_fork.default_branch
    after_checksum = compute_checksum(@org_fork)
    assert_equal before_checksum, after_checksum
  end

  test "extract and attach internal fork" do
    assert_equal "internal", @int_fork.visibility
    extract_repo(@int_fork)
    @int_fork.reload
    refute_equal @org_repo.id, @int_fork.network.root.id

    o = @int_fork.attach_to!(@org_repo)
    perform_enqueued_jobs(only: RepositoryOrchestrationJob)
    assert_equal "succeeded", o.reload.state

    @int_fork.reload
    assert_equal @org_repo.network.id, @int_fork.network.id
  end

  test "copies push rules" do
    GitHub.flipper[:push_rulesets].enable

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

    extract_repo(org2_fork)
    org2_fork.reload

    assert_equal org2_fork.id, org2_fork.network.root.id
    push_rules = RepositoryRuleset.load_for(source: org2_fork, include_parents: false, targets: ["push"])
    assert_equal 1, push_rules.size
    rule = T.must(push_rules.first)
    assert rule.enabled?
    assert_equal 77, T.must(rule.rule_configurations.first).parameters["max_file_path_length"]
  end

  test "should publish Extracted event" do
    with_hydro_publisher(GitHub.sync_hydro_publisher) do
      extract_repo(@fork1)

      message = {
        repository_id: @fork1.id,
        was_root: false,
        was_fork: true,
        old_network_id: @root.network_id,
        old_parent_id: @root.id,
        old_organization_id: 0,
        network_size: 3
      }
      assert_hydro_published(message, schema: "github.repositories.v1.Extracted")
      assert_hydro_messages(count: 1, schema: "github.repositories.v1.Extracted")
    end
  end

  test "extracting an org owned private repo syncs org_owned_private_networks_with_forks" do
    GitHub.flipper[:sync_org_owned_private_network_with_forks].enable

    admin = create(:user)
    org = create(:organization, admin: admin)
    org.allow_private_repository_forking(actor: admin)
    other_org = create(:organization, admin: admin)
    other_org.allow_private_repository_forking(actor: admin)
    repo = create(:private_repository, owner: org)
    fork = create(:fork_repository, forker: admin, fork_repo: repo, organization: other_org)
    other_fork = create(:fork_repository, forker: admin, fork_repo: fork)

    assert OrgOwnedPrivateNetworkWithForks.where(network_id: repo.network_id, owner_id: repo.owner_id).exists?

    # One OrgOwnedPrivateNetworkWithForks is created for the new network, one deleted for the old
    assert_difference("::OrgOwnedPrivateNetworkWithForks.count", 0) do
      extract_repo(fork)
    end
    refute OrgOwnedPrivateNetworkWithForks.where(network_id: repo.network_id, owner_id: repo.owner_id).exists?
    assert OrgOwnedPrivateNetworkWithForks.where(network_id: fork.reload.network_id, owner_id: fork.owner_id).exists?
  end

  test "extracting the only fork of an org owned private repo removes org_owned_private_networks_with_forks record" do
    GitHub.flipper[:sync_org_owned_private_network_with_forks].enable

    admin = create(:user)
    org = create(:organization, admin: admin)
    org.allow_private_repository_forking(actor: admin)
    other_org = create(:organization, admin: admin)
    other_org.allow_private_repository_forking(actor: admin)
    repo = create(:private_repository, owner: org)
    fork = create(:fork_repository, forker: admin, fork_repo: repo, organization: other_org)

    assert OrgOwnedPrivateNetworkWithForks.where(network_id: repo.network_id, owner_id: repo.owner_id).exists?

    assert_difference("::OrgOwnedPrivateNetworkWithForks.count", -1) do
      extract_repo(fork)
    end

    refute OrgOwnedPrivateNetworkWithForks.where(network_id: repo.network_id, owner_id: repo.owner_id).exists?
  end

  def extract_repo(repo, perform_jobs: [])
    o = RepositoryOrchestration.extract(repo)
    perform_orchestration(o, perform_jobs:)
  end

  def perform_orchestration(orchestration, perform_jobs: [])
    jobs = ([RepositoryOrchestrationJob] + perform_jobs).uniq
    perform_enqueued_jobs(only: jobs) do
      orchestration.execute
    end
    assert_equal "succeeded", orchestration.reload.state, "extract failed in #{orchestration.step_name}, #{orchestration.error_message}"
    orchestration
  end
end
