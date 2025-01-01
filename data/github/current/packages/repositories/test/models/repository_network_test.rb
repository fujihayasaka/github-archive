# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryNetworkTest < GitHub::TestCase
  include HydroTestHelpers
  include RepositoriesTestHelper

  fixtures do
    @owner = create(:user, name: "mrowner", plan: "medium")
    @repo  = create(:private_repository, name: "network_test", owner: @owner, from_example: :simple)
    @public_repo = create(:repository, from_example: :simple)
    @public_fork = create(:fork_repository, forker: create(:user), fork_repo: @public_repo)
    @public_fork_fork = create(:fork_repository, forker: create(:user), fork_repo: @public_fork)

    @repos = Array.new(4) do
      user = create(:user, plan: "micro")
      @repo.add_member user
      create(:fork_repository, forker: user, fork_repo: @repo)
    end

    @admin = create(:user)
    @global_org = create(:organization, admin: @admin, business: GitHub.global_business)
    @global_org.allow_private_repository_forking(actor: @admin)

    @fork = @repos.first
    @repos.last.update_attribute :pushed_at, Time.now + 100000

    @network = @repo.reload_network
    @public_network = @public_repo.reload_network

    @repo2 = create(:repository, from_example: :simple)
    @network2 = @repo2.network

    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  test "uses explicitly set primary key value" do
    repo = create(:repository, owner: @owner, from_example: :simple)
    assert_equal repo.network_id, repo.network.id
  end

  test "default values" do
    assert_equal 0, @network.pushed_count
    assert_equal 0, @network.pushed_count_since_maintenance
    assert_nil @network.pushed_at
  end

  test "root association" do
    assert_equal @repo.id, @network.root.id
  end

  test "find fork for user finds any fork in the network" do
    assert_equal @public_fork, @public_fork_fork.network.find_fork_for(@public_fork.owner)
  end

  test "#find_fork_for does not find a marked-as-deleted repo" do
    @user = @public_repo.owner
    @public_repo.remove(@user, synchronous: true)
    assert_nil @public_fork_fork.network.find_fork_for(@user)
  end

  test "creating a new network updates the root's owner's disabled flag" do
    User.any_instance.stubs(:over_plan_limit?).returns(true)

    RepositoryNetwork.create(root: @repo)
    assert @repo.owner.reload.disabled?
  end

  test "Extracting a private fork billing no longer locks it if the owner is over their plan limit" do
    owner = create(:user, plan: "micro")
    repo = create(:private_repository, owner: owner)
    forker = create(:user, plan: "free")
    repo.add_member forker
    fork = create(:fork_repository, forker: forker, fork_repo: repo)

    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { repo.toggle_visibility(actor: owner) }
    refute fork.reload.network.network_owner.disabled?
    refute fork.locked_on_billing?
  end

  test "Detaching a private fork billing no longer locks it if the owner is over their plan limit" do
    owner = create(:user, plan: "micro")
    repo = create(:private_repository, owner: owner)
    forker = create(:user, plan: "free")
    repo.add_member forker
    fork = create(:fork_repository, forker: forker, fork_repo: repo)

    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { fork.detach! }

    refute fork.reload.network.network_owner.disabled?
    refute fork.locked_on_billing?
    fork.unlock_including_descendants!
  end

  test "detaching an org-owned private fork keeps the fork as a dependent of the org" do
    org1 = create(:organization, plan:  "bronze")
    org1.allow_private_repository_forking(actor: org1.admin)

    repo = create(:private_repository, owner: org1, private: true)
    org2 = create(:organization, plan: "bronze")
    org1.add_member(org2.admins.first)

    fork = create(:fork_repository, forker: org2.admins.first, fork_repo: repo, organization: org2)

    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { fork.detach! }
    assert_able org2.admins.first, :admin, fork
  end

  test "parent association tracks across detaches" do
    repo = create(:repository, from_example: :simple)
    fork = create(:fork_repository, forker: create(:user), fork_repo: repo)
    forkfork = create(:fork_repository, forker: create(:user), fork_repo: fork)

    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { repo.detach! }
    assert_nil repo.reload.network.parent
    assert_equal repo.network, fork.reload.network.parent

    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { fork.detach! }
    assert_equal repo.network, fork.reload.network.parent
    assert_equal fork.network, forkfork.reload.network.parent
  end

  test "repositories association" do
    @network.recalculate!
    assert_equal 5, @network.repositories.count
  end

  test "destroying RepositoryNetwork when root repository is destroyed" do
    repo = create(:private_repository, name: "network_test2", owner: @owner)
    network = repo.reload_network

    forks = Array.new(4) do
      user = create(:user, plan: "micro")
      repo.add_member user
      fork = create(:fork_repository, forker: user, fork_repo: repo)
      fork
    end

    forks.each { |repo| repo.destroy }
    refute_nil RepositoryNetwork.find_by(id: network.id)

    repo.destroy
    assert_nil RepositoryNetwork.find_by(id: network.id)
  end

  test "changing the root repository updates the network root" do
    assert_equal @repo, @repo.network.root
    assert_equal @repo, @fork.network.root

    @fork.make_network_root!
    assert @fork.errors.empty?
    assert @fork.network_root?

    @repo.reload
    assert !@repo.network_root?
    assert_equal @fork, @repo.network.root
  end

  test "detaching a repository creates a new network" do
    assert_equal @public_repo, @public_repo.network.root
    assert_equal @public_repo, @public_fork.network.root

    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @public_fork.detach! }
    @public_fork.reload

    refute_nil @public_fork.network
    assert_equal @public_fork, @public_fork.network.root
    assert_equal @public_repo.network_id, @public_fork.network.owner_id
    assert_nil @public_fork.parent_id

    assert_equal @public_repo, @public_repo.reload_network.root

    refute_nil @public_fork_fork.reload_network
    assert_equal @public_repo, @public_fork_fork.network.root
    assert_equal @public_repo.network_id, @public_fork_fork.network_id
  end

  test "detaching touches the repository's updated_at" do
    now = Time.zone.local(2017, 2, 2)
    @fork.update_column :updated_at, now
    later = Time.zone.local(2017, 3, 2)
    Timecop.freeze(later) do
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @fork.detach! }
    end
    assert_equal later, @fork.reload.updated_at
  end

  test "extracting touches the repository's updated_at" do
    now = Time.zone.local(2017, 2, 2)
    @fork.update_column :updated_at, now
    later = Time.zone.local(2017, 3, 2)
    Timecop.freeze(later) do
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
        @fork.extract!
      end
    end
    assert_equal later, @fork.reload.updated_at
  end

  test "detaching updates network counts" do
    parent = create(:public_repository, from_example: :simple)
    first_fork = create(:fork_repository, forker: create(:user), fork_repo: parent)
    second_fork = create(:fork_repository, forker: create(:user), fork_repo: parent)
    third_fork = create(:fork_repository, forker: create(:user), fork_repo: first_fork)
    fourth_fork = create(:fork_repository, forker: create(:user), fork_repo: first_fork)
    assert_equal 4, parent.reload.network_count

    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { first_fork.detach! }

    assert_equal 3, parent.reload.network_count
    assert_equal 3, second_fork.reload.network_count
    assert_equal 3, third_fork.reload.network_count
    assert_equal 3, fourth_fork.reload.network_count

    assert_equal 0, first_fork.reload.network_count
  end

  test "extracting updates network counts" do
    parent = create(:public_repository, from_example: :simple)
    first_fork = create(:fork_repository, forker: create(:user), fork_repo: parent)
    second_fork = create(:fork_repository, forker: create(:user), fork_repo: parent)
    third_fork = create(:fork_repository, forker: create(:user), fork_repo: first_fork)
    fourth_fork = create(:fork_repository, forker: create(:user), fork_repo: first_fork)
    assert_equal 4, parent.reload.network_count

    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { first_fork.extract! }

    assert_equal 1, parent.reload.network_count
    assert_equal 1, second_fork.reload.network_count

    assert_equal 2, first_fork.reload.network_count
    assert_equal 2, third_fork.reload.network_count
    assert_equal 2, fourth_fork.reload.network_count
  end

  test "reattaching updates network counts" do
    parent = create(:public_repository, from_example: :simple)
    first_fork = create(:fork_repository, forker: create(:user), fork_repo: parent)
    second_fork = create(:fork_repository, forker: create(:user), fork_repo: parent)
    third_fork = create(:fork_repository, forker: create(:user), fork_repo: first_fork)
    fourth_fork = create(:fork_repository, forker: create(:user), fork_repo: first_fork)
    assert_equal 4, parent.reload.network_count

    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { first_fork.detach! }

    assert_equal 3, parent.reload.network_count
    assert_equal 3, second_fork.reload.network_count
    assert_equal 3, third_fork.reload.network_count
    assert_equal 3, fourth_fork.reload.network_count
    assert_equal 0, first_fork.reload.network_count

    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { first_fork.reattach! }

    assert_equal 4, parent.reload.network_count
    assert_equal 4, first_fork.reload.network_count
    assert_equal 4, second_fork.reload.network_count
    assert_equal 4, third_fork.reload.network_count
    assert_equal 4, fourth_fork.reload.network_count
  end

  test "reattaching does not orphan child networks" do
    # See https://github.com/github/github/issues/116351

    parent = create(:public_repository, from_example: :simple)
    first_fork = create(:fork_repository, forker: create(:user), fork_repo: parent)
    second_fork = create(:fork_repository, forker: create(:user), fork_repo: parent)

    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { parent.detach! }
    parent.reload
    assert_predicate parent, :network_root?
    first_fork.reload
    second_fork.reload
    assert first_fork.network_root? ^ second_fork.network_root?

    # The first fork is _typically_ elected the new root, but this test shouldn't enforce
    # that contract, so we figure out which sibling fork is the new network's root.
    new_network_root = first_fork.network_root? ? first_fork : second_fork
    new_network_child = first_fork.network_root? ? second_fork : first_fork
    assert_equal new_network_root.network.owner_id, parent.source_id
    assert_equal new_network_child.network.owner_id, parent.source_id

    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { new_network_root.detach! }
    new_network_root.reload
    new_network_child.reload
    assert_predicate first_fork, :network_root?
    assert_predicate second_fork, :network_root?
    assert_equal new_network_root.network.owner_id, parent.source_id
    assert_equal new_network_child.network.owner_id, new_network_root.source_id

    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { new_network_root.network.reattach! }
    new_network_root.reload
    new_network_child.reload
    refute_predicate new_network_root, :network_root?
    assert_equal new_network_root.source_id, parent.source_id
    assert_predicate new_network_child, :network_root?
    assert_equal new_network_child.network.owner_id, parent.source_id
  end

  test "detaching a repository re-indexes its conversations" do
    now = Time.now
    timestamp = Timestamp.from_time(now)
    Timecop.freeze(now) do
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
        @fork.detach!
      end
    end

    %w[issues pull_requests].each do |type|
      job_type = "bulk_#{type}"
      guid = AddToSearchIndexJob.guid(job_type, @fork.id, "purge" => true)
      assert_enqueued_with(job: AddToSearchIndexJob, args: [job_type, @fork.id, { "submitted_at" => timestamp, "purge" => true, "guid" => guid }], queue: "index_low")
    end
  end

  test "extracting a repository re-indexes conversations for itself and its descendants" do
    now = Time.now
    timestamp = Timestamp.from_time(now)
    Timecop.freeze(now) do
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @public_fork.extract! }
    end

    %w[issues pull_requests].each do |type|
      job_type = "bulk_#{type}"
      [@public_fork, @public_fork_fork].each do |repo|
        guid = AddToSearchIndexJob.guid(job_type, repo.id, "purge" => true)
        assert_enqueued_with(job: AddToSearchIndexJob, args: [job_type, repo.id, { "submitted_at" => timestamp, "purge" => true, "guid" => guid }], queue: "index_low")
      end
    end
  end

  test "reattaching a previously-detached network re-indexes conversations" do
    only = [AddToSearchIndexJob, RepositoryOrchestrationJob]
    perform_enqueued_jobs(only: only) do
      @fork.detach!
    end
    @fork.reload

    now = Time.now
    timestamp = Timestamp.from_time(now)
    Timecop.freeze(now) do
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @fork.reattach! }
      assert_enqueued_jobs 3, only: AddToSearchIndexJob, queue: "index_low"
    end

    %w[issues pull_requests].each do |type|
      job_type = "bulk_#{type}"
      guid = AddToSearchIndexJob.guid(job_type, @fork.id, "purge" => true)
      assert_enqueued_with(job: AddToSearchIndexJob, args: [job_type, @fork.id, { "submitted_at" => timestamp, "purge" => true, "guid" => guid }], queue: "index_low")
    end
  end

  test "reattaching a previously-extracted network re-indexes conversations" do
    only = [AddToSearchIndexJob, RepositoryOrchestrationJob]
    perform_enqueued_jobs(only: only) do
      @public_fork.extract!
    end
    @public_fork.reload

    now = Time.now
    timestamp = Timestamp.from_time(now)
    Timecop.freeze(now) do
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @public_fork.reattach! }
      assert_enqueued_jobs 6, only: AddToSearchIndexJob, queue: "index_low"
    end

    forks = [@public_fork, @public_fork_fork]
    %w[issues pull_requests].each do |type|
      job_type  = "bulk_#{type}"
      forks.each do |repo|
        guid = AddToSearchIndexJob.guid(job_type, repo.id, "purge" => true)
        assert_enqueued_with(job: AddToSearchIndexJob, args: [job_type, repo.id, { "submitted_at" => timestamp, "purge" => true, "guid" => guid }], queue: "index_low")
      end
    end
  end

  test "extracting the only repo in a network does nothing" do
    assert_equal @network2, @repo2.network
    assert_equal @repo2, @network2.root
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @repo2.extract! }
    @network2.reload

    assert_equal @network2, @repo2.network
    assert_equal @repo2, @network2.root
  end

  test "extracting the only repo into another single-repo network works" do
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
      @public_fork_fork.detach!
      @public_repo.extract!(network_id: @public_fork_fork.reload.network_id)
    end

    assert_equal @public_fork_fork.network, @public_repo.reload.network
  end

  test "extracting a repository creates a new network and moves it on disk" do
    assert_equal @public_repo, @public_repo.network.root
    assert_equal @public_repo, @public_fork.network.root

    old_paths = DGit.paths_for_repo(@public_fork) + DGit.paths_for_repo(@public_fork_fork)
    old_shard = @public_fork.shard_path
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @public_fork.extract! }

    refute_nil @public_fork.reload.network
    refute_equal @public_repo.network, @public_fork.network
    assert_equal @public_repo.network, @public_fork.network.parent
    assert_equal @public_fork, @public_fork.network.root

    # We need to flush the cache here now that the extract work is done in a background job
    @public_fork.dgit_reload_routes!

    refute_equal old_shard, @public_fork.shard_path

    old_paths.each do |path|
      refute File.exist?(path), "#{path} should not exist on disk"
    end

    @public_fork_fork.reload  # get the new network

    [@public_fork, @public_fork_fork].each do |r|
      DGit.paths_for_repo(r).each do |path|
        assert File.directory?(path), "#{path} should exist on disk"
      end
    end

    assert_equal @public_repo, @public_repo.reload_network.root
  end

  test "extracting a repository and its forks handles broken forks gracefully" do
    assert_equal @public_repo, @public_repo.network.root
    assert_equal @public_repo, @public_fork.network.root

    Repository.any_instance.stubs(:disable_shared_storage).returns(true).then.raises(Exception)

    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @public_fork.extract! }

    refute_equal @public_repo.network, @public_fork.reload.network
    assert_equal @public_fork, @public_fork.network.root
    assert_equal @public_fork.network, @public_fork_fork.reload.network
  end

  context "extracting a private user-owned fork from a user-owned repo" do
    test "removes implicit collaborators from the fork and its user-owned descendants" do
      @user = create(:user, plan: "micro")
      @user_repo = create(:private_repository, owner: @user)
      @user2 = create(:user, plan: "micro")
      @user3 = create(:user, plan: "micro")
      @user_repo.add_member @user2
      @user_repo.add_member @user3
      @user2_fork = create(:fork_repository, forker: @user2, fork_repo: @user_repo)

      assert @user2_fork.pushable_by? @user
      assert @user2_fork.pushable_by? @user3
      assert @user_repo.pushable_by? @user2
      assert @user_repo.pushable_by? @user3

      @user3_fork = create(:fork_repository, forker: @user3, fork_repo: @user2_fork)
      assert @user3_fork.pushable_by? @user
      assert @user3_fork.pushable_by? @user2

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @user2_fork.extract! }

      assert @user_repo.reload.pushable_by? @user2
      assert @user_repo.pushable_by? @user3
      refute @user2_fork.reload.pushable_by? @user
      assert @user2_fork.pushable_by? @user3

      refute @user3_fork.reload.pushable_by? @user
      assert @user3_fork.pushable_by? @user2
    end
  end

  context "extracting a private user-owned fork from an org-owned repo" do
    test "removes the teams from the fork and all user-owned descendants" do
      @org = create(:organization, plan: "bronze")
      @org.allow_private_repository_forking(actor: @org.admins.first)
      @org_repo = create(:private_repository, owner: @org, from_example: :simple)
      @team = create(:team, organization: @org, permission: "push")
      @team.add_repository @org_repo, :push
      @user2 = create(:user, plan: "micro")
      @user3 = create(:user, plan: "micro")
      @other_user = create(:user)
      @team.add_member @user2
      @team.add_member @user3
      @team.add_member @other_user
      @user2_fork = create(:fork_repository, fork_repo: @org_repo, forker: @user2)
      perform_enqueued_jobs(only: RepositoryAddTeamsJob)

      assert @org_repo.pushable_by? @user2
      assert @org_repo.pushable_by? @user3
      assert @user2_fork.pushable_by? @other_user
      assert @user2_fork.pushable_by? @user3

      @user3_fork = create(:fork_repository, fork_repo: @user2_fork, forker: @user3)
      perform_enqueued_jobs(only: RepositoryAddTeamsJob)
      assert @user3_fork.pushable_by? @other_user
      assert @user3_fork.pushable_by? @user2

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @user2_fork.extract! }

      refute @user2_fork.reload.pushable_by? @other_user
      refute @user3_fork.reload.pushable_by? @other_user
    end

    test "doesn't remove the teams from any org-owned descendants" do
      @org = create(:organization, plan: "bronze")
      @org.allow_private_repository_forking(actor: @org.admins.first)
      @org.update_default_repository_permission(:none, actor: @org.admins.first)

      @org_repo = create(:private_repository, owner: @org, from_example: :simple)
      @org2 = create(:organization)
      @org2.allow_private_repository_forking(actor: @org2.admins.first)
      @team = create(:team, organization: @org, permission: "pull")
      @team.add_repository @org_repo, :pull
      @other_team = create(:team, organization: @org2, permission: "pull")
      @user2 = create(:user, plan: "micro")
      @user3 = create(:user, plan: "micro")
      @other_user = create(:user)
      @org_user = create(:user)
      @other_org_user = create(:user)
      @team.add_member @user2
      @team.add_member @user3
      @team.add_member @other_user
      @org2.add_admin(@user3)
      @other_team.add_member @org_user
      @other_team.add_member @other_org_user
      @user2_fork = create(:fork_repository, forker: @user2, fork_repo: @org_repo)
      perform_enqueued_jobs(only: [RepositoryAddTeamsJob])

      @org2_fork = create(:fork_repository, forker: @user3, fork_repo: @user2_fork, organization: @org2)
      @other_team.add_repository @org2_fork, :pull
      @org_user_fork = create(:fork_repository, forker: @org_user, fork_repo: @org2_fork)
      @other_team.add_repository @org_user_fork, :pull
      refute @org2_fork.pullable_by? @other_user
      assert @org2_fork.pullable_by? @org_user


      assert @org_repo.pullable_by? @user2
      assert @org_repo.pullable_by? @user3
      assert @user2_fork.pullable_by? @other_user
      assert @user2_fork.pullable_by? @user3

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @user2_fork.extract! }

      assert @org_repo.reload.pullable_by? @user2
      assert @org_repo.pullable_by? @user3
      refute @user2_fork.reload.pullable_by? @other_user
      refute @user2_fork.pullable_by? @user3
      refute @org2_fork.reload.pullable_by? @other_user
      assert @org2_fork.pullable_by? @org_user
      assert @org_user_fork.reload.pullable_by? @other_org_user
    end

    test "removes admin permissions granted via organization ownership" do
      org = create(:organization, plan: "bronze")
      org.allow_private_repository_forking(actor: org.admins.first)
      org.update_default_repository_permission(:none, actor: org.admins.first)

      org_repo = create(:private_repository, owner: org)
      team = create(:team, organization: org, permission: "push")
      team.add_repository org_repo, :push
      user = create(:user, plan: "micro")
      team.add_member user
      user_fork = create(:fork_repository, forker: user, fork_repo: org_repo)

      assert user_fork.pullable_by?(org.admins.first)
      assert_able org.admins.first, :admin, user_fork

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { user_fork.extract! }
      user_fork.reload
      refute user_fork.in_organization?, "WTF"

      refute user_fork.pullable_by?(org.admins.first)
      refute_able org.admins.first, :admin, user_fork
    end
  end

  test "attempting to extract into the same network fails" do
    assert_raises(Repository::NetworkDependency::ExtractFailure) do
      @fork.extract!(network_id: @network.id)
    end

    assert_equal @network, @fork.network
  end

  test "extracting into an existing network does the right thing" do
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
      @public_fork.detach!
      @public_fork_fork.extract!(network_id: @public_fork.reload.network.id)
    end

    refute_equal @public_repo.network, @public_fork_fork.reload.network
    assert_equal @public_fork.network, @public_fork_fork.network
    assert_equal @public_fork.network.root, @public_fork_fork.parent
  end

  test "extracting into an existing network fails if visibility differs" do
    assert_raises(Repository::NetworkDependency::ExtractFailure) do
      @public_repo.extract!(network_id: @network.id)
    end
  end

  test "networks can be reattached" do
    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @public_fork.extract! }
    new_network = @public_fork.reload.network

    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @public_fork.network.reattach! }
    assert_raises(ActiveRecord::RecordNotFound) { new_network.reload }
    assert_equal @public_repo.network, @public_fork.reload.network
    assert_equal @public_repo.network, @public_fork_fork.reload.network
  end

  test "networks can be reattached from any direction" do
    old_network = @public_repo.network
    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @public_repo.detach! }
    new_network = @public_repo.reload.network

    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @public_fork.network.reattach! }
    assert_raises(ActiveRecord::RecordNotFound) { old_network.reload }
    assert_equal new_network, @public_fork.reload.network
    assert_equal @public_repo, @public_fork.parent
  end

  test "owner with max private repos can have deleted repo become the root" do
    User.any_instance.stubs(:at_private_repo_limit?).returns(true)

    assert_raises do
      @fork.network.make_root!(@fork)
    end

    @fork.remove(User.ghost, synchronous: true)
    @fork.network.make_root!(@fork)

    assert_equal @fork.reload, @fork.network.root
  end

  test "making a fork the new network root adjusts the public network accordingly" do
    assert_equal @public_repo, @public_network.root
    assert_nil @public_repo.parent
    assert_equal @public_fork, @public_fork_fork.parent

    @public_network.make_root!(@public_fork)

    assert_equal @public_fork, @public_network.reload.root
    assert_equal @public_fork, @public_repo.reload.parent
    assert_equal @public_fork, @public_fork_fork.reload.parent
  end

  test "making a fork the new network root adjusts the private network accordingly" do
    assert_equal @repo, @network.root
    assert_nil @repo.parent
    assert_equal @repo.owner, @repo.plan_owner
    assert_equal @repo.owner, @fork.plan_owner

    @network.make_root!(@fork)

    assert_equal @fork, @network.reload.root
    assert_equal @fork, @repo.reload.parent
    assert_equal @fork.owner, @repo.plan_owner
    assert_equal @fork.owner, @fork.plan_owner
  end

  test "making a fork the new network root adjust the network accordingly when network includes forks for forks" do
    user = create(:user).tap { |u| @fork.add_member u }
    forkfork = create(:fork_repository, forker: user, fork_repo: @fork)

    assert_equal @fork, forkfork.parent
    assert_equal @repo.owner, forkfork.plan_owner

    @network.make_root!(@fork)

    assert_equal @fork, forkfork.reload.parent
    assert_equal @fork.owner, forkfork.plan_owner
  end

  test "making a fork the new network root adjusts the organization of all repos in the network accordingly" do
    org = create(:organization, plan: "bronze")
    org.allow_private_repository_forking(actor: org.admins.first)

    user = create(:user, plan: "micro")
    user2 = create(:user)
    repo = create(:private_repository, owner: org)
    team = create(:team, organization: org)

    team.add_member user
    team.add_member user2
    team.add_repository repo, :pull
    fork = create(:fork_repository, forker: user, fork_repo: repo)
    fork2 = create(:fork_repository, forker: user2, fork_repo: repo)

    assert_equal org.id, fork.organization_id
    assert_equal org.id, fork2.organization_id

    network = repo.network
    assert network.make_root!(fork)

    assert_equal fork.id, network.reload.root_id
    assert_nil fork.reload.organization_id
    assert_nil fork2.reload.organization_id

    network.reload.make_root!(repo)

    assert_equal org.id, fork.reload.organization_id
    assert_equal org.id, fork2.reload.organization_id
  end

  test "making a fork the new network root syncs org_owned_private_networks_with_forks" do
    org = create(:organization)
    other_org = create(:organization, admin: org.admins.first)
    org.allow_private_repository_forking(actor: org.admins.first)

    repo = create(:private_repository, owner: org)
    fork = create(:fork_repository, forker: org.admins.first, fork_repo: repo, organization: other_org)

    assert OrgOwnedPrivateNetworkWithForks.where(network_id: repo.network_id, owner_id: repo.owner_id).exists?

    network = repo.network
    assert network.make_root!(fork)

    assert OrgOwnedPrivateNetworkWithForks.where(network_id: fork.network_id, owner_id: fork.owner_id).exists?
  end

  test "instruments extracting a repo" do
    events = subscribe "repo.extract"

    expected_payload = {
      repo: @public_fork.nwo,
      repo_id: @public_fork.id,
      public_repo: @public_fork.public?,
      old_network_id: @public_network.id
    }

    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @public_fork.extract! }

    assert event = events.pop, "a repo.extract event was expected"
    assert_equal expected_payload, event.payload
  end

  test "instruments extracting a repo from staff" do
    events = subscribe "staff.repo_extract"

    expected_payload = {
      repo: @public_fork.nwo,
      repo_id: @public_fork.id,
      public_repo: @public_fork.public?,
      old_network_id: @public_network.id
    }

    Audit.context.push(from: "stafftools")
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @public_fork.extract! }

    assert event = events.pop, "a staff.repo_extract event was expected"
    assert_equal expected_payload, event.payload
  end

  test "instruments detaching a repo" do
    events = subscribe "repo.detach"

    expected_payload = {
      repo: @public_fork.nwo,
      repo_id: @public_fork.id,
      public_repo: @public_fork.public?,
      old_network_id: @public_network.id
    }

    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @public_fork.detach! }

    assert event = events.pop, "a repo.detach event was expected"
    assert_equal expected_payload, event.payload
  end

  test "instruments detaching a repo from staff" do
    events = subscribe "staff.repo_detach"

    expected_payload = {
      repo: @public_fork.nwo,
      repo_id: @public_fork.id,
      public_repo: @public_fork.public?,
      old_network_id: @public_network.id
    }

    Audit.context.push(from: "stafftools")
    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @public_fork.detach! }

    assert event = events.pop, "a staff.repo_detach event was expected"
    assert_equal expected_payload, event.payload
  end

  test "instruments making a repo the network root" do
    events = subscribe "staff.repo_make_root"

    @network.make_root!(@fork)

    expected_payload = {
      repo: @fork.nwo,
      repo_id: @fork.id,
      public_repo: @fork.public?,
      root_repo_was: @repo.nwo,
      root_repo_was_id: @repo.id,
    }

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "changing the root of a public network updates the counts" do
    assert_equal 2, @public_repo.public_fork_count
    assert_equal 1, @public_fork.public_fork_count

    @public_fork.make_network_root!
    @public_fork.reload

    assert_equal 0, @public_repo.reload.public_fork_count
    assert_equal 2, @public_fork.public_fork_count
  end

  test "pick a healthy fork to be the new parent" do
    network = @public_repo.network
    second_fork = create(:fork_repository, forker: create(:user), fork_repo: @public_repo)

    # corrupt the public fork so it's no longer part of the network
    # so it shouldn't get picked to be the new parent, even though it's the oldest
    @public_fork.update_column(:source_id, @public_fork.source_id + 1)

    network.reparent_forks!(@public_repo)
    network.reload
    assert_equal second_fork.id, network.root_id
  end

  test "detaching a root repository adjusts the network root on the old network" do
    @public_fork.make_network_root!

    assert_equal @public_fork, @public_repo.reload.network.root
    assert_equal @public_fork, @public_fork.reload.network.root

    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @public_fork.detach! }

    refute_nil @public_fork.reload.network
    assert @public_fork.network_root?
    assert @public_fork.parent.nil?
    assert_equal @public_fork.network_id, @public_fork.network.id

    refute_nil @public_repo.reload.network
    refute_equal @public_fork, @public_repo.network.root
    assert_equal @public_repo.network_id, @public_repo.network.id
    assert_nil @public_repo.parent
    repos = [@public_repo, @public_fork_fork]
    (@public_repo.network.repositories - repos).each { |f| assert_equal @public_repo, f.parent }
    assert_equal @public_repo.owner, @public_repo.plan_owner
  end

  test "removing a public root repository updates the network root" do
    @public_repo.remove(@public_repo.owner, synchronous: true)
    @public_fork.reload
    @public_fork_fork.reload

    refute_equal @public_repo, @public_fork.network.root
    assert_equal @public_fork.network.root, @public_fork_fork.network.root
  end

  context "#increment_cache_version!" do
    test "increments cache version number" do
      assert_equal 0, @network.cache_version_number

      @network.increment_cache_version!
      assert_equal 1, @network.cache_version_number
    end
  end

  context "#sync_org_owned_private_network_with_forks" do
    test "adds org_owned_private_network_with_forks when untracked root is synced" do
      repo = create(:private_repository, owner: @global_org)
      fork = fast_fork_repo(repo, owner: @admin)

      assert_difference("::OrgOwnedPrivateNetworkWithForks.count", 1) do
        repo.network.sync_org_owned_private_network_with_forks
      end
    end

    test "removes org_owned_private_network_with_forks when tracked root without forks is synced" do
      repo = create(:private_repository, owner: @global_org)
      fork = fast_fork_repo(repo, owner: @admin)

      assert_difference("::OrgOwnedPrivateNetworkWithForks.count", 1) do
        repo.network.sync_org_owned_private_network_with_forks
      end

      fork.remove(@admin)
      fork.destroy

      assert_difference("::OrgOwnedPrivateNetworkWithForks.count", -1) do
        repo.network.sync_org_owned_private_network_with_forks
      end
    end

    test "removes org_owned_private_network_with_forks when tracked root goes public" do
      repo = create(:private_repository, owner: @global_org)
      fork = fast_fork_repo(repo, owner: @admin)

      assert_difference("::OrgOwnedPrivateNetworkWithForks.count", 1) do
        repo.network.sync_org_owned_private_network_with_forks
      end

      repo.update_attribute(:public, true)

      assert_difference("::OrgOwnedPrivateNetworkWithForks.count", -1) do
        repo.network.sync_org_owned_private_network_with_forks
      end
    end

    test "removes org_owned_private_network_with_forks when tracked root is not org owned" do
      repo = create(:private_repository, owner: @global_org, name: "root")
      fork = fast_fork_repo(repo, owner: @admin, name: "fork")

      assert_difference("::OrgOwnedPrivateNetworkWithForks.count", 1) do
        repo.network.sync_org_owned_private_network_with_forks
      end

      repo.update_attribute(:owner_id, @admin.id)

      assert_difference("::OrgOwnedPrivateNetworkWithForks.count", -1) do
        repo.network.sync_org_owned_private_network_with_forks
      end
    end

    test "updates org_owned_private_network_with_forks when tracked owner is changed" do
      repo = create(:private_repository, owner: @global_org)
      other_org = create(:organization, admin: @admin)
      fork = fast_fork_repo(repo, owner: other_org)

      assert_difference("::OrgOwnedPrivateNetworkWithForks.count", 1) do
        repo.network.sync_org_owned_private_network_with_forks
      end

      org_owned_private_root = OrgOwnedPrivateNetworkWithForks.find_by!(network_id: repo.network_id)
      assert_equal repo.owner_id, org_owned_private_root.owner_id

      repo.network.update_attribute(:root_id, fork.id)
      assert_difference("::OrgOwnedPrivateNetworkWithForks.count", 0) do
        repo.network.sync_org_owned_private_network_with_forks
      end

      assert_equal fork.owner_id, org_owned_private_root.reload.owner_id
    end

    test "does nothing when untracked public root is synced" do
      repo = create(:public_repository, owner: @global_org)
      fork = fast_fork_repo(repo, owner: @admin)

      assert_difference("::OrgOwnedPrivateNetworkWithForks.count", 0) do
        repo.network.sync_org_owned_private_network_with_forks
      end
    end

    test "does nothing when untracked private user owned root is synced" do
      repo = create(:private_repository, owner: @owner)
      create(:collaborator, collaborator: @admin, repository: repo, action: :write)
      fork = fast_fork_repo(repo, owner: @admin)

      assert_difference("::OrgOwnedPrivateNetworkWithForks.count", 0) do
        repo.network.sync_org_owned_private_network_with_forks
      end
    end

    test "does nothing when untracked, unforked repo is synced" do
      repo = create(:private_repository, owner: @global_org)

      assert_difference("::OrgOwnedPrivateNetworkWithForks.count", 0) do
        repo.network.sync_org_owned_private_network_with_forks
      end
    end
  end
end
