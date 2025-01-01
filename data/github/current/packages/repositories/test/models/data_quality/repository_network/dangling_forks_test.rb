# typed: true
# frozen_string_literal: true

require "test_helper"

class DataQualityRepositoryNetworkDanglingForksTest < GitHub::TestCase
  include EnvironmentTestHelper

  PackageRepoMock = Struct.new(:packages)
  fixtures do
    perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) do
      @organization = create(:organization)
      @owner = @organization.admins.first
      @organization.allow_private_repository_forking(actor: @owner, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)
    end

    @member = create(:user, login: "member")
    @organization.add_member(@member)

    @parent_repository = create(:private_repository, owner: @organization, name: "parent-repository", from_example: :simple)
    @member_fork = create(:fork_repository, forker: @member, fork_repo: @parent_repository)

    @collab = create(:user, login: "collab")
    @parent_repository.add_member(@collab)
    @collab_fork = create(:fork_repository, forker: @collab, fork_repo: @parent_repository)

    stable_member = create(:user, login: "stable-member") # a member who won't be removed
    @organization.add_member(stable_member)
    @stable_fork = create(:fork_repository, forker: stable_member, fork_repo: @parent_repository) # a fork that won't be removed

    @rando = create(:user, login: "rando")
    @stable_fork.add_member(@rando)
    @rando_nested_fork = create(:fork_repository, forker: @rando, fork_repo: @stable_fork)

    @user_owned_parent_repository = create(:private_repository, owner: @member, name: "user-owned-parent-repository", from_example: :simple)
    @user_owned_parent_repository.add_member(@rando)
    @rando_fork_with_user_owned_parent = create(:fork_repository, forker: @rando, fork_repo: @user_owned_parent_repository)

    METADATA_CLIENT = ::PackageRegistry::Twirp::MetadataClient
  end

  setup do
    self.perform_enqueued_jobs = true # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
    METADATA_CLIENT.any_instance.stubs(:get_packages_by_repo).returns(PackageRepoMock.new(packages: []))
  end

  def destroy_ability_for(actor:, subject:)
    options = {
      actor_id: actor.ability_id,
      actor_type: actor.ability_type,
      subject_id: subject.ability_id,
      subject_type: subject.ability_type,
      priority: Ability.priorities[:direct],
    }

    abilities = Ability.where(options)
    assert_equal 1, abilities.length

    abilities.destroy_all

    abilities = Ability.where(options)
    assert_equal 0, abilities.length
  end

  context "instruments" do
    test "fork removal in audit log" do
      job_events = subscribe("data_quality.archive_dangling_forks")
      archive_events = subscribe("repo.disk_archive")

      destroy_ability_for(actor: @member, subject: @organization)

      min_repo_id = Repository.minimum(:id)
      max_repo_id = Repository.maximum(:id)
      with_local_host_name "github-staff2-cp1-prd.iad.github.net" do
        DataQuality::RepositoryNetwork::DanglingForks.new(clean: true).run
      end

      assert job_event = job_events.pop, "an event was expected"
      assert_equal min_repo_id, job_event.payload[:start_repo_id]
      assert_equal max_repo_id, job_event.payload[:finish_repo_id]
      assert_equal 1, job_event.payload[:archived_forks_count]
      assert_equal 1, job_event.payload[:total_forks_count]
      assert job_event.payload[:clean]
      assert_equal "github-staff2-cp1-prd.iad.github.net", job_event.payload[:host_name]
    end

    test "fork removal in datadog" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      destroy_ability_for(actor: @member, subject: @organization)
      destroy_ability_for(actor: @collab, subject: @parent_repository)

      # This is here to test the removal of private fork-of-fork @rando_nested_fork. The feature
      # flag check is here primarily to remind us to remove it when the feature flag ships.
      destroy_ability_for(actor: @rando, subject: @stable_fork)

      max_repo_id = Repository.maximum(:id)
      with_local_host_name "github-staff2-cp1-prd.iad.github.net" do
        DataQuality::RepositoryNetwork::DanglingForks.new(clean: true).run
      end

      assert_equal 5, GitHub.dogstats.increments("dangling_forks.forks_scanned").length
      assert_equal 3, GitHub.dogstats.increments("dangling_forks.forks_removed").length

      gauges = GitHub.dogstats.gauges("dangling_forks.max_repo_id_scanned")
      assert_equal 1, gauges.length
      actual_gauge_value = gauges.first.args[1]
      assert_equal max_repo_id, actual_gauge_value
    end
  end

  context "when clean is true archives private repository fork" do
    test "ignores soft-deleted forks" do
      destroy_ability_for(actor: @collab, subject: @parent_repository)
      @collab_fork.remove(@collab)
      assert Repositories::Public.find_deleted(@collab_fork.id), "fork should be soft-deleted"

      # should not attempt to remove the already-deleted repo
      Repository.any_instance.expects(:remove).never
      assert_difference("Repository.active.count", 0) do
        DataQuality::RepositoryNetwork::DanglingForks.new(clean: true).run
      end
    end

    test "for collaborator who no longer has access to the parent" do
      assert @parent_repository.readable_by?(@collab)
      destroy_ability_for(actor: @collab, subject: @parent_repository)
      refute @parent_repository.readable_by?(@collab)

      assert_difference("Repository.active.count", -1) do
        DataQuality::RepositoryNetwork::DanglingForks.new(clean: true).run
      end

      assert Repositories::Public.is_deleted?(@collab_fork.id), "should have deleted #{@collab_fork}"
    end

    test "when parent is user-owned" do
      assert @user_owned_parent_repository.readable_by?(@rando)
      destroy_ability_for(actor: @rando, subject: @user_owned_parent_repository)
      refute @user_owned_parent_repository.readable_by?(@rando)

      assert_difference("Repository.active.count", -1) do
        DataQuality::RepositoryNetwork::DanglingForks.new(clean: true).run
      end
      assert Repositories::Public.is_deleted?(@rando_fork_with_user_owned_parent.id), "should have deleted #{@rando_fork_with_user_owned_parent}"
    end

    test "for org member who is no longer a part of the org" do
      assert @parent_repository.readable_by?(@member)
      destroy_ability_for(actor: @member, subject: @organization)
      refute @parent_repository.readable_by?(@member)

      DataQuality::RepositoryNetwork::DanglingForks.new(clean: true).run

      assert Repositories::Public.is_deleted?(@member_fork.id), "should have deleted #{@member_fork}"
    end

    test "for org member who is no longer a member of a team owned repository" do
      @organization.update_default_repository_permission(:none, actor: @owner)
      @organization.reload

      team = create :team, organization: @organization
      team_repository = create(:private_repository, owner: @organization, name: "team-repository", from_example: :simple)
      team.add_repository(team_repository, :admin)

      refute team_repository.readable_by?(@member)

      team.add_member(@member)
      assert team_repository.readable_by?(@member)

      team_fork, status = team_repository.fork(forker: @member)
      assert_equal :created, status

      destroy_ability_for(actor: team, subject: team_repository)

      refute team_repository.readable_by?(@member)
      assert_includes @organization.member_ids, @member.id

      DataQuality::RepositoryNetwork::DanglingForks.new(clean: true).run

      assert Repositories::Public.is_deleted?(team_fork.id), "should have deleted #{team_fork}"
    end

    test "for a fork of an organization forked repository when the fork owner is an admin of the grand parent org" do
      @organization.update_member(@member, action: :admin)
      grand_parent_repo = create(:private_repository, owner: @organization, name: "grandparent", from_example: :simple)

      other_org = create(:organization, login: "other-org", admin: @owner)
      other_org.allow_private_repository_forking(actor: @owner)
      other_org.add_member(@member)

      org_fork, status = grand_parent_repo.fork(forker: @owner, org: other_org)
      assert_equal :created, status

      fork_of_fork, status = org_fork.fork(forker: @member)
      assert_equal :created, status

      destroy_ability_for(actor: @member, subject: other_org)

      DataQuality::RepositoryNetwork::DanglingForks.new(clean: true).run

      assert Repositories::Public.is_active?(fork_of_fork.id), "should not have destroyed #{fork_of_fork}"
    end

    test "for a fork owned by a removed org admin" do
      # https://github.com/github/security/issues/3683
      new_org_admin = create(:user)
      @organization.add_admin(new_org_admin, adder: @owner)
      @organization.allow_private_repository_forking(actor: @owner, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)
      admin_fork, status = @parent_repository.fork(forker: new_org_admin)
      assert admin_fork, "Fork should have succeeded but failed with status '#{status}'"

      destroy_ability_for(actor: new_org_admin, subject: @organization)
      refute @parent_repository.pullable_by?(new_org_admin)
      assert Repositories::Public.find_active(admin_fork.id)

      DataQuality::RepositoryNetwork::DanglingForks.new(clean: true).run

      assert Repositories::Public.is_deleted?(admin_fork.id), "fork should be deleted"
    end
  end

  context "does not remove" do
    test "non-dangling forks" do
      assert_difference("Repository.count", 0) do
        DataQuality::RepositoryNetwork::DanglingForks.new(clean: true).run
      end
      assert Repositories::Public.find_active(@member_fork.id), "should not have destroyed #{@member_fork}"
      assert Repositories::Public.find_active(@stable_fork.id), "should not have destroyed #{@stable_fork}"
      assert Repositories::Public.find_active(@collab_fork.id), "should not have destroyed #{@collab_fork}"
      assert Repositories::Public.find_active(@rando_nested_fork.id), "should not have destroyed #{@rando_nested_fork}"
    end

    test "org-owned private forks" do
      new_org = create(:organization)

      new_org_admin = new_org.admins.first
      @parent_repository.add_member(new_org_admin)
      assert @parent_repository.permit?(new_org_admin, :read)

      oopf, status = @parent_repository.fork(forker: new_org_admin, org: new_org)
      assert oopf
      assert_equal :created, status

      destroy_ability_for(actor: new_org_admin, subject: @parent_repository)
      refute @parent_repository.permit?(new_org_admin, :read)
      refute @parent_repository.permit?(oopf.owner, :read)

      assert_difference("Repository.count", 0) do
        DataQuality::RepositoryNetwork::DanglingForks.new(clean: true).run
      end
      assert Repositories::Public.find_active(oopf.id), "should not have destroyed #{oopf}"
    end
  end

  context "clean is false reports private repository fork " do
    test "for collaborator who no longer has access to the parent" do
      assert @parent_repository.readable_by?(@collab)
      destroy_ability_for(actor: @collab, subject: @parent_repository)
      refute @parent_repository.readable_by?(@collab)

      DataQuality::RepositoryNetwork::DanglingForks.new(clean: false).run

      assert Repositories::Public.find_active(@collab_fork.id), "should not have destroyed #{@collab_fork}"
    end

    test "for org member who is no longer a part of the org" do
      assert @parent_repository.readable_by?(@member)
      destroy_ability_for(actor: @member, subject: @organization)
      refute @parent_repository.readable_by?(@member)

      DataQuality::RepositoryNetwork::DanglingForks.new(clean: false).run

      assert Repositories::Public.find_active(@member_fork.id), "should not have destroyed #{@member_fork}"
    end

    test "for org member who is no longer a member of a team owned repository" do
      @organization.update_default_repository_permission(:none, actor: @owner)
      @organization.reload

      team = create :team, organization: @organization
      team_repository = create(:private_repository, owner: @organization, name: "team-repository", from_example: :simple)
      team.add_repository(team_repository, :admin)

      refute team_repository.readable_by?(@member)

      team.add_member(@member)
      assert team_repository.readable_by?(@member)

      team_fork, status = team_repository.fork(forker: @member)
      assert_equal :created, status

      destroy_ability_for(actor: team, subject: team_repository)

      refute team_repository.readable_by?(@member)
      assert_includes @organization.member_ids, @member.id

      DataQuality::RepositoryNetwork::DanglingForks.new(clean: false).run

      assert Repositories::Public.find_active(team_fork.id), "should not have destroyed #{team_fork}"
    end
  end
end

class DanglingForkAheadOfParentTest < GitHub::TestCase
  include EnvironmentTestHelper

  setup do
    self.perform_enqueued_jobs = true # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
  end

  test "logs comparison failures" do
    # Placing commits into the GitRPC cache (rather than "on disk") causes
    # the GitHub::Comparison#relationship method (used to determine if the
    # fork is ahead of the parent) to raise an exception, which we expect our
    # Fork class to rescue and log.
    enable_cache_storage

    owner = create(:user, login: "repo-owner")
    repo = create(:repository, owner: owner, name: "our-repo", from_example: :simple)

    metadata = { message: "blah", committer: owner }
    repo.heads.find("master").append_commit(metadata, owner) {}

    forker = create(:user, login: "repo-forker")
    the_fork, status = repo.fork(forker: forker)
    assert_equal :created, status
    example_repo :forkable, the_fork

    metadata = { message: "irrelevant", committer: forker }
    the_fork.heads.find("master").append_commit(metadata, forker) {}

    Failbot.expects(:report).with do |boom|
      boom.message == "Comparison failed between"\
      " #{the_fork.id}@#{the_fork.default_oid} and #{repo.id}@#{repo.default_oid}"
    end

    pseudo_fork = DataQuality::RepositoryNetwork::DanglingForks::Fork.new(the_fork, owner, repo)
    pseudo_fork.ahead_of_parent?

    reset_cache
    disable_cache_storage
  end
end
