# typed: true
# frozen_string_literal: true

require "test_helper"

class ExtractRepositoryOrchestrationTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @owner = create(:user)
    @root = create(:public_repository, name: "public", owner: @owner, from_example: :simple)

    @fork1 = create(:fork_repository, forker: create(:user), fork_repo: @root)
    @fork2 = create(:fork_repository, forker: create(:user), fork_repo: @root)
    @fork3 = create(:fork_repository, forker: create(:user), fork_repo: @root)
    @fork4 = create(:fork_repository, forker: create(:user), fork_repo: @root)
    @fork5 = create(:fork_repository, forker: create(:user), fork_repo: @root)
    @fork6 = create(:fork_repository, forker: create(:user), fork_repo: @root)
    @forkfork = create(:fork_repository, forker: create(:user), fork_repo: @fork1)
    @forkforkfork = create(:fork_repository, forker: create(:user), fork_repo: @forkfork)

    # create a couple wikis
    RepositoryWiki.create(repository: @fork1)
    @fork1.unsullied_wiki.setup_git_repository
    RepositoryWiki.create(repository: @forkforkfork)
    @forkforkfork.unsullied_wiki.setup_git_repository

    @org = create(:enterprise_linked_organization)
    @member = create(:user)
    @org.add_member(@member)
    @org.allow_private_repository_forking(actor: @org.admin, policy: Configurable::AllowPrivateRepositoryForking::EVERYWHERE)

    @org_repo = create(:repository, owner: @org, internal: true, from_example: :repository_test_simple)
    @org_fork = create(:fork_repository, forker: @member, fork_repo: @org_repo, private: true)
    @org_fork.update_default_branch("special")

    # create an internal org-owned fork of an internal repo
    @int_fork = create(:fork_repository, :org_owned_internal, forker: @member, fork_repo: @org_repo, organization: @org)

    example_repo_snapshot(snapshot_spokesdb: true)
  end

  setup do
    example_repo_restore
  end

  def compute_checksum(repo)
    nw_reader = GitHub::DGit::Routing.preferred_reader_for_network(repo.network_id)
    out = GitHub::DGit::Maintenance.recompute_checksums(repo, nw_reader)
    out[:checksum]
  end

  test "fail if janitor fails" do
    # inject an unexpected file into the repo that will make git-janitor unhappy
    @org_fork.rpc.ensure_initialized({ files: { "junk-file" => "junk" } })
    assert_equal "junk",  @org_fork.rpc.fs_read("junk-file", 0)

    o = RepositoryOrchestration.extract(@org_fork)
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
      o.execute
    end
    assert_equal "failed", o.reload.state
    assert_equal "janitor_fix", o.step_name
    assert_match "Unexpected file: junk-file", o.error_message
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

  test "outdated nwo on disk is not resulting in checksum mismatch" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    before_checksum = compute_checksum(@org_fork)

    # simulate that the info/nwo file has a different nwo on disk
    @org_fork.update_nwo_file("owner/simulate-different-nwo-on-disk")
    nwo_content = @org_fork.rpc.fs_read("info/nwo")
    refute_equal @org_fork.name_with_owner, nwo_content

    # nwo is part of the checksum, so it should be different now
    refute_equal before_checksum, compute_checksum(@org_fork)

    extract_repo(@org_fork)
    @org_fork.reload
    @org_fork.dgit_reload_routes!

    refute_equal @org_repo.id, @org_fork.network.root.id
    assert_equal @org_repo.id, @org_repo.network.root.id
    assert_equal @org_fork.network.id, @org_fork.network.id
    after_checksum = compute_checksum(@org_fork)
    assert_equal @org_fork.name_with_owner, @org_fork.rpc.fs_read("info/nwo")
    assert_equal before_checksum, after_checksum

    # we should not have a checksum mismatch if the nwo file was corrected
    assert_incremented_stat "repository_orchestration.step.warning", tags: ["type:ExtractRepositoryOrchestration", "step:compare_checksums"], count: 0
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

  test "records actor_id and from" do
    Audit.context.push(from: "stafftools")
    o = RepositoryOrchestration.extract(@int_fork, actor: @owner)
    perform_orchestration(o)
    o.reload
    assert_equal @owner.id, o.data[:actor_id]
    assert_equal "stafftools", o.data[:audit_from]
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

    extract_repo(org2_fork)
    org2_fork.reload

    assert_equal org2_fork.id, org2_fork.network.root.id
    push_rules = RepositoryRuleset.load_for(source: org2_fork, include_parents: false, targets: ["push"])
    assert_equal 1, push_rules.size
    rule = T.must(push_rules.first)
    assert rule.enabled?
    assert_equal 77, T.must(rule.rule_configurations.first).parameters["max_file_path_length"]
  end

  test "should extract the wiki" do
    #foo = GitHub::DGit::dev_route(@repo.original_shard_path, to_host)}/dgit-state
    extract_repo(@fork1)
    @fork1.reload
    @forkforkfork.reload

    refute_equal @root.network_id, @fork1.network_id
    assert_equal @fork1.network_id, @forkforkfork.network_id

    validate_wiki(@fork1)
    validate_wiki(@forkforkfork)
  end

  def validate_wiki(repo)
    assert repo.wiki_exists_on_disk?
    expected_wiki_path = "#{repo.network.storage_path}/#{repo.id}.wiki.git"
    assert_equal expected_wiki_path, repo.wiki_shard_path, "wikis should be moved"
    assert repo.wiki_rpc!.exist?, "wiki should exist on disk"

    DGit.paths_for_repo(repo.unsullied_wiki).each do |path|
      assert File.exist?(File.join(path, "config")), "config should exist in wiki dest: #{path}"
      assert File.exist?(File.join(path, "dgit-state")), "dgit-state should exist in wiki dest: #{path}"
    end
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
        network_size: 9
      }
      assert_hydro_published(message, schema: "github.repositories.v1.Extracted")
      assert_hydro_messages(count: 1, schema: "github.repositories.v1.Extracted")
    end
  end

  test "extracting an org owned private repo syncs org_owned_private_networks_with_forks" do
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

  test "skip if an ancestor is extracting" do
    o1 = start_extract(@fork1)
    o3 = start_extract(@forkforkfork)
    o2 = start_extract(@forkfork)
    assert_equal "running", o1.reload.state
    assert_equal "skipped", o2.reload.state
    assert_equal "an ancestor to this fork is being extracted", o2.error_message
    assert_equal "skipped", o3.reload.state
    assert_equal "an ancestor to this fork is being extracted", o3.error_message

    o1.execute
    assert_equal "succeeded", o1.reload.state

    # we need to reload the forks from disk because they changed networks
    @forkfork = Repository.find(@forkfork.id)
    @forkforkfork = Repository.find(@forkforkfork.id)

    o2 = start_extract(@forkfork)
    assert_equal "running", o2.reload.state
    o3 = start_extract(@forkforkfork)
    assert_equal "skipped", o3.reload.state
    o2.execute
    assert_equal "succeeded", o2.reload.state

    @forkforkfork = Repository.find(@forkforkfork.id)
    o3 = start_extract(@forkforkfork)
    assert_equal "running", o3.reload.state
    o3.execute
    assert_equal "succeeded", o3.reload.state
  end

  test "skip if a child is extracting" do
    o1 = start_extract(@forkforkfork)
    o2 = start_extract(@forkfork)
    o3 = start_extract(@fork1)
    assert_equal "running", o1.reload.state
    assert_equal "skipped", o2.reload.state
    assert_equal "a child fork is being extracted", o2.error_message
    assert_equal "skipped", o3.reload.state
    assert_equal "a child fork is being extracted", o3.error_message

    o1.execute
    assert_equal "succeeded", o1.reload.state

    o2 = start_extract(@forkfork)
    assert_equal "running", o2.reload.state
    o3 = start_extract(@fork1)
    assert_equal "skipped", o3.reload.state
    o2.execute
    assert_equal "succeeded", o2.reload.state

    o3 = start_extract(@fork1)
    assert_equal "running", o3.reload.state
    o3.execute
    assert_equal "succeeded", o3.reload.state
  end

  context "extract_queue" do
    test "no queues to one queue" do
      GitHub.flipper[:extract_queue_count].enable_percentage_of_time(0.0)
      o1 = start_extract(@fork1)
      o2 = start_extract(@fork2)
      o3 = start_extract(@fork3)

      assert_equal "running", o1.state
      assert_equal "running", o2.state
      assert_equal "running", o3.state
      assert_nil o1.parent_id
      assert_nil o2.parent_id
      assert_nil o3.parent_id

      # force a single queue. They should all line up behind the last one
      GitHub.flipper[:extract_queue_count].enable_percentage_of_time(1.0)
      o4 = start_extract(@fork4)
      o5 = start_extract(@fork5)
      o6 = start_extract(@fork6)
      assert_equal "waiting", o4.reload.state
      assert_equal "waiting", o5.reload.state
      assert_equal "waiting", o6.reload.state
      assert_equal o4.id, o3.reload.parent_id
      assert_equal o5.id, o4.parent_id
      assert_equal o6.id, o5.parent_id
    end

    test "one queue" do
      GitHub.flipper[:extract_queue_count].enable_percentage_of_time(1.0)
      o1 = start_extract(@fork1)
      o2 = start_extract(@fork2)
      o3 = start_extract(@fork3)

      assert_equal "running", o1.reload.state
      assert_equal "waiting", o2.reload.state
      assert_equal "waiting", o3.reload.state
      assert_equal o2.id, o1.parent_id
      assert_equal o3.id, o2.parent_id
      assert_nil   o3.parent_id

      o1.execute
      assert_equal "succeeded", o1.reload.state
      assert_equal "running", o2.reload.state
      assert_equal "waiting", o3.reload.state

      o2.execute
      assert_equal "succeeded", o2.reload.state
      assert_equal "running", o3.reload.state

      o3.execute
      assert_equal "succeeded", o3.reload.state
    end

    test "two queues" do
      GitHub.flipper[:extract_queue_count].enable_percentage_of_time(2.0)
      o1 = start_extract(@fork1)
      o2 = start_extract(@fork2)
      o3 = start_extract(@fork3)
      o4 = start_extract(@fork4)

      assert_equal "running", o1.reload.state
      assert_equal "running", o2.reload.state
      assert_equal "waiting", o3.reload.state
      assert_equal "waiting", o4.reload.state
      assert_equal o3.id, o1.parent_id
      assert_equal o4.id, o2.parent_id
      assert_nil   o3.parent_id
      assert_nil   o4.parent_id

      o1.execute
      assert_equal "succeeded", o1.reload.state
      assert_equal "running", o2.reload.state
      assert_equal "running", o3.reload.state
      assert_equal "waiting", o4.reload.state

      o2.execute
      assert_equal "succeeded", o2.reload.state
      assert_equal "running", o3.reload.state

      o3.execute
      assert_equal "succeeded", o3.reload.state
    end

    test "one then two queues" do
      GitHub.flipper[:extract_queue_count].enable_percentage_of_time(1.0)
      o1 = start_extract(@fork1)
      o2 = start_extract(@fork2)
      o3 = start_extract(@fork3)

      assert_equal "running", o1.reload.state
      assert_equal "waiting", o2.reload.state
      assert_equal "waiting", o3.reload.state
      assert_equal o2.id, o1.parent_id
      assert_equal o3.id, o2.parent_id
      assert_nil   o3.parent_id

      # allow another queue.
      GitHub.flipper[:extract_queue_count].enable_percentage_of_time(2.0)

      o4 = start_extract(@fork4)
      o5 = start_extract(@fork5)
      o6 = start_extract(@fork6)
      # o4 should run immediately, o5 should queue behind o3, and o6 should queue behind o4
      assert_equal "running", o4.reload.state
      assert_equal "waiting", o5.reload.state
      assert_equal "waiting", o6.reload.state
      assert_equal o5.id, o3.reload.parent_id
      assert_equal o6.id, o4.reload.parent_id
    end

    test "three then two queues" do
      GitHub.flipper[:extract_queue_count].enable_percentage_of_time(3.0)
      o1 = start_extract(@fork1)
      o2 = start_extract(@fork2)
      o3 = start_extract(@fork3)

      assert_equal "running", o1.reload.state
      assert_equal "running", o2.reload.state
      assert_equal "running", o3.reload.state

      # drop to 2 queues
      GitHub.flipper[:extract_queue_count].enable_percentage_of_time(2.0)

      o4 = start_extract(@fork4)
      o5 = start_extract(@fork5)
      o6 = start_extract(@fork6)
      # new orchestrations should queue behind the last two, o2 and o3.
      # nobody should queue behind the oldest one, o1
      assert_equal "waiting", o4.reload.state
      assert_equal "waiting", o5.reload.state
      assert_equal "waiting", o6.reload.state
      assert_nil o1.reload.parent_id
      assert_equal o4.id, o2.reload.parent_id
      assert_equal o5.id, o3.reload.parent_id
      assert_equal o6.id, o4.reload.parent_id
    end

    test "on_end_orchestration should reload itself to look for a parent to restart" do
      GitHub.flipper[:extract_queue_count].enable_percentage_of_time(1.0)
      o1 = start_extract(@fork1)

      # update o1 to be on the last step
      last_step = ExtractRepositoryOrchestration.all_steps.last.name
      o1.update_column(:step_name, last_step)
      o1.step_name = last_step

      # o2 should queue behind o1
      o2 = start_extract(@fork2)

      # finish running o1 without reloading from the database.
      o1.execute

      assert_equal "succeeded", o1.reload.state
      assert_equal o2.id, o1.parent_id
      assert_equal "running", o2.reload.state, "o2 should have been kicked when o1 ended"
    end

    test "can queue out of order" do
      GitHub.flipper[:extract_queue_count].enable_percentage_of_time(1.0)
      o1 = RepositoryOrchestration.extract(@fork1)
      o2 = RepositoryOrchestration.extract(@fork2)
      o3 = RepositoryOrchestration.extract(@fork3)

      # execute the orchestrations out of order
      o3.execute
      o2.execute
      o1.execute

      # assert they get queued in the right order anyway
      assert_equal o2.id, o1.reload.parent_id
      assert_equal o3.id, o2.reload.parent_id
      assert_nil o3.reload.parent_id

      assert_equal "running", o1.state
      assert_equal "waiting", o2.state
      assert_equal "waiting", o3.state
    end

    test "runs even if previous in queue failed" do
      GitHub.flipper[:extract_queue_count].enable_percentage_of_time(1.0)

      o1 = start_extract(@fork1)
      o2 = start_extract(@fork2)
      o3 = start_extract(@fork3)

      # assert they get queued in the right order anyway
      assert_equal o2.id, o1.reload.parent_id
      assert_equal o3.id, o2.reload.parent_id
      assert_nil o3.reload.parent_id

      assert_equal "running", o1.state
      assert_equal "waiting", o2.state
      assert_equal "waiting", o3.state

      # make o1 fail
      o1.repository.rpc.ensure_initialized({ files: { "junk-file" => "junk" } })
      o1.step_name = "janitor_fix"
      o1.data[:repos_to_extract] = [o1.repository.id]
      o1.save!
      o1.execute

      # o2 should still run
      assert_equal "failed", o1.reload.state
      assert_equal "running", o2.reload.state
      assert_equal "waiting", o3.reload.state
    end
  end

  context "retry" do
    test "if failed" do
      o1 = start_extract(@fork1)
      assert_equal "running", o1.state
      refute o1.can_retry_failed_orchestration?

      o1.failed!
      assert_equal "failed", o1.reload.state
      assert o1.can_retry_failed_orchestration?

      o1.abandoned!
      assert_equal "abandoned", o1.reload.state
      refute o1.can_retry_failed_orchestration?
    end

    test "if skipped" do
      # start extracting a child which will cause our extract to be skipped
      o2 = start_extract(@forkfork)
      o1 = start_extract(@fork1)
      assert_equal "skipped", o1.state
      assert o1.can_retry_failed_orchestration?

      # retry the orchestration. Should be skipped again
      o1.retry_failed_orchestration
      assert_equal "running", o1.reload.state
      o1.execute
      assert_equal "skipped", o1.reload.state
      assert_equal "inspect_environment", o1.step_name
      assert o1.can_retry_failed_orchestration?

      # finish the child orchestration
      o2.execute
      assert_equal "succeeded", o2.reload.state

      # retry the orchestration. Should succeed now
      o1.retry_failed_orchestration
      assert_equal "running", o1.reload.state
      o1.execute
      assert_equal "succeeded", o1.reload.state
    end

    test "repo deleted" do
      o1 = fail_extract(@fork1)
      assert o1.can_retry_failed_orchestration?

      @fork1.remove(User.ghost)
      refute o1.reload.can_retry_failed_orchestration?
      assert_equal "abandoned", o1.reload.state
      assert_equal "repository is deleted", o1.error_message
    end

    test "repo destroyed" do
      o1 = fail_extract(@fork1)

      @fork1.destroy!
      refute o1.reload.can_retry_failed_orchestration?
      assert_equal "abandoned", o1.reload.state
      assert_equal "repository is gone", o1.error_message
    end

    test "abandon if newer orchestration" do
      o1 = fail_extract(@fork1)
      o2 = fail_extract(@fork1)
      o3 = fail_extract(@fork2)

      assert o1.newer_orchestration?
      refute o1.can_retry_failed_orchestration?
      o1.reload
      assert_equal "abandoned", o1.state
      assert_equal "newer orchestration exists", o1.error_message

      refute o2.newer_orchestration?
      assert o2.can_retry_failed_orchestration?
      assert_equal "failed", o2.reload.state

      refute o3.newer_orchestration?
      assert o3.can_retry_failed_orchestration?
      assert_equal "failed", o3.reload.state
    end

    test "abandon if repo in unexpected network" do
      o1 = fail_extract(@fork1)
      o1.data[:old_network_id] = @fork1.network_id + 1
      o1.save!
      refute o1.can_retry_failed_orchestration?
      o1.reload
      assert_equal "abandoned", o1.state
      assert_equal "repository is on an unexpected network", o1.error_message
    end

    test "OK in new network" do
      o1 = fail_extract(@fork1)
      # simulate the repo has moved to the new network
      o1.data[:old_network_id] = @fork1.network_id + 1
      o1.data[:new_network_id] = @fork1.network_id
      o1.save!
      assert o1.can_retry_failed_orchestration?
    end

    test "no step name" do
      o1 = fail_extract(@fork1)
      o1.step_name = nil
      o1.save!
      refute o1.can_retry_failed_orchestration?
      o1.reload
      assert_equal "abandoned", o1.state
      assert_equal "no step to retry", o1.error_message
    end

    test "abandon if old network is gone" do
      o1 = fail_extract(@fork1)
      @fork1.network.destroy
      # reload to flush @old_network from cache
      o1 = ExtractRepositoryOrchestration.find(o1.id)
      refute o1.can_retry_failed_orchestration?
      o1.reload
      assert_equal "abandoned", o1.state
      assert_equal "old network is gone", o1.error_message
    end

    test "attach new network is gone" do
      o1 = fail_extract(@fork1)
      o1.data[:attach] = true
      o1.data[:new_network_id] = RepositoryNetwork.last&.id + 1
      o1.save!

      refute o1.can_retry_failed_orchestration?
      o1.reload
      assert_equal "abandoned", o1.state
      assert_equal "new network is gone so cannot attach", o1.error_message
    end

    test "works if failed" do
      o1 = fail_extract(@fork1)

      assert o1.can_retry_failed_orchestration?
      o1.reload
      assert_equal "failed", o1.state

      o1.retry_failed_orchestration
      o1.reload
      assert_equal "running", o1.state

      perform_enqueued_jobs(only: RepositoryOrchestrationJob)
      assert_equal "succeeded", o1.reload.state
    end

    test "starts at the beginning if new network is gone" do
      o1 = fail_extract(@fork1)
      o1.data[:new_network_id] = 0
      o1.attempts = 8
      o1.save!

      assert o1.can_retry_failed_orchestration?
      o1.reload
      assert_equal "failed", o1.state

      o1.retry_failed_orchestration
      o1.reload
      assert_equal "running", o1.state
      assert_equal "identify_repos", o1.step_name
      assert_equal 0, o1.attempts
      assert_nil o1.data[:new_network_id]
      assert_nil o1.data[:repos_to_extract]

      perform_enqueued_jobs(only: RepositoryOrchestrationJob)
      o1.reload
      assert_equal "succeeded", o1.state
      refute_equal @root.network_id, @fork1.reload.network_id
      assert_equal @fork1.network_id, @forkforkfork.reload.network_id
    end

    test "old_network is gone" do
      o1 = fail_extract(@fork1)

      # simulate moving to the new network and old network got deleted
      o1.step_name = "delete_source_repos"
      o1.data[:old_network_id] = RepositoryNetwork.last&.id + 1
      o1.data[:new_network_id] = @fork1.network_id
      o1.save!

      assert o1.retry_failed_orchestration
      perform_enqueued_jobs(only: RepositoryOrchestrationJob)
      assert_equal "succeeded", o1.reload.state
    end
  end

  def fail_extract(repo)
    o1 = start_extract(repo)
    o1.failed!

    # remove the orchestration job from the queue
    enqueued_jobs.clear

    o1.reload
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

  def start_extract(repo)
    o = RepositoryOrchestration.extract(repo)
    o.execute
    o
  end
end
