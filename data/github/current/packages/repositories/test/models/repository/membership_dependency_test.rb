# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryMembershipDependencyTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper

  PackageRepoMock = Struct.new(:packages)
  fixtures do
    @defunkt  = create(:user, login: "defunkt",  plan: "medium")
    @maddox   = create(:user, login: "maddox")
    @mojombo  = create(:user, login: "mojombo2", plan: "medium")
    @pj       = create(:user, login: "pj",       plan: "medium")
    @admin    = create(:user, login: "d12")
    @admin_2  = create(:user, login: "iolsen")
    @member   = create(:user, login: "member")

    @outside_collaborator = create(:user)

    @org = create(:business_plus_org, business: create(:business))
    @org.add_admin(@admin)
    @org.add_admin(@admin_2)
    @org.add_member(@member, action: :read)

    @ambition = create(:private_repository, name: "ambition", owner: @defunkt)
    @facebox  = create(:repository, name: "facebox",  owner: @defunkt)
    @grit     = create(:repository, name: "grit",     owner: @mojombo)
    @internal = create(:internal_repository, owner: @org)
    @org_private_repo = create(:private_repository, owner: @org)
    @internal.allow_private_repository_forking(actor: @admin)
    @internal.add_member(@outside_collaborator)
    @simple   = create(:repository, name: "simple",   owner: @defunkt)

    METADATA_CLIENT = ::PackageRegistry::Twirp::MetadataClient

    @custom_role = create_custom_role(owner: @org, base_role: :maintain)
    @all_repo_role = create(:custom_all_repo_role, owner_id: @org.id, owner_type: "Organization")
  end

  setup do
    GitHub.flipper[:discard_stratocaster_fanout].disable
    METADATA_CLIENT.any_instance.stubs(:get_packages_by_repo).returns(PackageRepoMock.new(packages: []))
  end

  context "add_member" do
    test "creates a stratocaster event when a member is added" do
      GitHub.flipper[:stratocaster_ignore_member_added].disable

      GitHub.stratocaster.clear_timelines("repo:#{@ambition.id}")

      assert_equal 0, GitHub.stratocaster.events("repo:#{@ambition.id}").size
      only = [DeliverHookEventJob, ProcessEventJob, UpdateEventFeedsJob]
      perform_enqueued_jobs(only: only) { @ambition.add_member(@pj, @defunkt) }
      events = GitHub.stratocaster.events("repo:#{@ambition.id}")
      assert_equal 1, events.size
      event = events.first.to_hash.deep_symbolize_keys
      assert_equal "MemberEvent", event[:event_type]
      assert_equal "pj", event[:payload][:member][:login]
      assert_handle_match "defunkt", event[:sender][:login]
      assert_equal :added, event[:payload][:action]
    end

    test "does not create a stratocaster event when a member is added when the repo owner has the stratocaster_ignore_member_added FF enabled" do
      GitHub.flipper[:stratocaster_ignore_member_added].enable(@ambition.owner)
      GitHub.stratocaster.clear_timelines("repo:#{@ambition.id}")

      assert_equal 0, GitHub.stratocaster.events("repo:#{@ambition.id}").size
      only = [DeliverHookEventJob, ProcessEventJob, UpdateEventFeedsJob]
      perform_enqueued_jobs(only: only) { @ambition.add_member(@pj, @defunkt) }
      events = GitHub.stratocaster.events("repo:#{@ambition.id}")
      assert_equal 0, events.size
    end

    test "adds new members as collaborators if the repo is private" do
      assert_difference "@defunkt.reload.collaborators_count" do
        @ambition.add_member(@pj)
      end
    end

    test "does not create OrganizationCollaborator when new member who is not an org member is added when FF is disabled" do
      GitHub.flipper[:collaborator_cache_write].disable
      GitHub.flipper[:collaborator_cache_read].disable
      collab = create(:user)
      assert_no_difference "OrganizationCollaborator.count" do
        @org_private_repo.add_member(collab)
      end
    end

    test "creates OrganizationCollaborator when new member who is not an org member is added" do
      GitHub.flipper[:collaborator_cache_write].enable
      collab = create(:user)
      assert_difference "OrganizationCollaborator.count", +1 do
        @org_private_repo.add_member(collab)
      end
    end

    test "does not create OrganizationCollaborator when new member who is an org member is added" do
      GitHub.flipper[:collaborator_cache_write].enable
      collab = create(:user)
      @org.add_member(collab)
      assert_no_difference "OrganizationCollaborator.count" do
        @org_private_repo.add_member(collab)
      end
    end

    test "can't give a collaborator read access to a user-owned repository" do
      repo         = create(:private_repository, owner: @defunkt)
      collaborator = create(:user, login: "collaborator")
      refute repo.pullable_by?(collaborator)

      refute repo.add_member(collaborator, action: :read)
      refute repo.pullable_by?(collaborator)
    end

    test "can't give a collaborator admin access to a user-owned repository" do
      repo         = create(:private_repository, owner: @defunkt)
      collaborator = create(:user, login: "collaborator")
      refute repo.adminable_by?(collaborator)

      refute repo.add_member(collaborator, action: :admin)
      refute repo.adminable_by?(collaborator)
    end

    test "can give a collaborator read access to an org-owned repository" do
      org          = create(:organization)
      repo         = create(:private_repository, owner: org)
      collaborator = create(:user, login: "collaborator")
      refute repo.pullable_by?(collaborator)

      assert repo.add_member(collaborator, action: :read)
      assert repo.pullable_by?(collaborator)
      refute repo.pushable_by?(collaborator)
    end

    test "can give a collaborator write access to an org-owned repository" do
      org          = create(:organization)
      repo         = create(:private_repository, owner: org)
      collaborator = create(:user, login: "collaborator")
      refute repo.pushable_by?(collaborator)

      assert repo.add_member(collaborator)
      assert repo.pushable_by?(collaborator)
      refute repo.adminable_by?(collaborator)
    end

    test "can give a collaborator admin access to an org-owned repository" do
      org          = create(:organization)
      repo         = create(:private_repository, owner: org)
      collaborator = create(:user, login: "collaborator")
      refute repo.adminable_by?(collaborator)

      assert repo.add_member(collaborator, action: :admin)
      assert repo.adminable_by?(collaborator)
    end

    test "can give a collaborator custom role access to an org-owned repository" do
      refute @org_private_repo.writable_by?(@member)
      assert @org_private_repo.add_member(@member, action: @custom_role.name)
      assert @org_private_repo.writable_by?(@member)
    end

    test "can't grant an all-repo role over a repository" do
      assert_raises do
        @org_private_repo.add_member(@member, action: @all_repo_role.name)
      end
    end

    test "can add a member to a fork of an org-owned private repo" do
      org  = create(:organization, plan: "silver")
      org.allow_private_repository_forking(actor: org.admins.first)

      repo = create(:private_repository, owner: org)
      team = create(:team, organization: org)
      team.add_repository(repo, :pull)
      team.add_member(@pj)

      forked, status = repo.fork(forker: @pj)

      assert_equal :created, status
      assert forked.add_member(create(:user, login: "collaborator"))
      refute forked.errors.any?
    end

    test "doesn't add orgs as collaborators" do
      org = create(:organization, admin: @pj)
      repo = create(:private_repository, owner: org)
      other_org = create(:organization)
      repo.add_member(other_org)

      refute repo.pushable_by?(other_org)
      assert repo.errors[:base].include? "Only users can be collaborators"
    end

    test "doesn't add users who are being transformed into orgs as collaborators" do
      org = create(:organization, admin: @pj)
      repo = create(:private_repository, owner: org)
      transforming_user = create :user
      Organization.start_transform(transforming_user)
      assert Organization.transforming?(transforming_user)
      repo.add_member(transforming_user)

      refute repo.pushable_by?(transforming_user)
      assert repo.errors[:base].include? "Users being transformed into organizations cannot be added as collaborators"
    end

    test "doesn't add bots as collaborators" do
      org = create(:organization, admin: @pj)
      repo = create(:private_repository, owner: org)
      bot = create(:integration).bot
      repo.add_member(bot)

      refute repo.pushable_by?(bot)
      assert repo.errors[:base].include? "Only users can be collaborators"
    end

    test "doesn't add members as collaborators if the repo is public" do
      assert_no_difference "@defunkt.reload.collaborators_count" do
        @simple.add_member(@pj)
      end
    end

    test "doesn't add members as collaborators if no seats available" do
      org          = create(:organization, plan: "business", seats: 5)
      repo         = create(:private_repository, owner: org)
      collaborator = create(:user, login: "collaborator")
      4.times { org.add_member(create(:user)) }

      refute repo.pushable_by?(collaborator)
      refute repo.add_member(collaborator)
      refute repo.pushable_by?(collaborator)
      refute repo.adminable_by?(collaborator)
      assert_equal ["You must purchase at least one more seat to add this user as a collaborator."],
        repo.errors[:seat_limit]
    end

    test "adds members as collaborators on public repos even if no seats available" do
      org = create(:organization, plan: "business", seats: 5)
      4.times { org.add_member(create(:user)) }
      repo = create(:public_repository, owner: org)
      collaborator = create(:user, login: "collaborator")

      assert repo.add_member(collaborator)
      assert_equal 1, org.outside_collaborators.size
    end

    test "can update a collaborator's permissions on a user-owned repo" do
      repo         = create(:private_repository, owner: @defunkt)
      collaborator = create(:user, login: "collaborator")
      repo.add_member(collaborator)
      assert repo.pushable_by?(collaborator)
      refute repo.adminable_by?(collaborator)

      # admin is not valid for user repos
      refute repo.update_member(collaborator, action: :admin)
    end

    test "can update a collaborator's permissions on an org-owned repo" do
      org          = create(:organization)
      repo         = create(:private_repository, owner: org)
      collaborator = create(:user, login: "collaborator")
      repo.add_member(collaborator)
      assert repo.pushable_by?(collaborator)
      refute repo.adminable_by?(collaborator)

      assert repo.update_member(collaborator, action: :admin)
      assert repo.adminable_by?(collaborator)
    end

    test "can update a collaborator's permissions on a user-owned fork of an org-owned repo" do
      org          = create(:organization, plan: "bronze")
      org.allow_private_repository_forking(actor: org.admins.first)

      repo         = create(:private_repository, owner: org)
      fork_owner   = create(:user, login: "fork-owner")
      collaborator = create(:user, login: "collaborator")

      org.add_member(fork_owner)
      repo.add_member(fork_owner)
      fork = create(:fork_repository, forker: fork_owner, fork_repo: repo)

      fork.add_member(collaborator)
      assert fork.pushable_by?(collaborator)
      refute fork.adminable_by?(collaborator)

      assert fork.update_member(collaborator, action: :admin)
      assert fork.adminable_by?(collaborator)
    end

    test "cancels pending invitations from the member when they lose admin access", skip_enterprise: true do
      org = create(:organization)
      repo = create(:private_repository, owner: org)
      admin = create(:user, login: "org-admin")
      repo.add_member(admin, action: :admin)
      invitee = create(:user)

      RepositoryInvitation.invite_to_repo(invitee, admin, repo)
      assert_equal RepositoryInvitation.count, 1
      repo.update_member(admin, action: :read)
      assert_equal RepositoryInvitation.count, 0
    end

    test "update_member instruments the expected payload" do
      org          = create(:organization)
      repo         = create(:private_repository, owner: org)
      collaborator = create(:user, login: "collaborator")
      repo.add_member(collaborator)

      events = subscribe("repo.update_member")
      repo.update_member(collaborator, action: :admin)

      event            = events.pop
      expected_payload = {
        actor: org.login,
        actor_id: org.id,
        user: collaborator.login,
        user_id: collaborator.id,
        org: org.login,
        org_id: org.id,
        repo: repo.name_with_owner,
        repo_id: repo.id,
        public_repo: repo.public?,
        fork_source: repo.name_with_owner,
        fork_source_id: repo.id,
        old_repo_permission: :write,
        new_repo_permission: :admin,
        old_repo_base_role: nil,
        new_repo_base_role: nil,
        old_permissions: { pull: true, push: true, admin: false, triage: true, maintain: false },
        visibility: :private,
      }

      assert_equal "repo.update_member", event.name
      assert_equal expected_payload, event.payload
    end

    test "removes collaborators when removing members" do
      assert @ambition.add_member(@pj)

      assert_difference "@defunkt.reload.collaborators_count", -1 do
        @ambition.remove_member(@pj)
      end
    end

    test "does not allow user to be added as collab to repo owned by blocked user" do
      @pj.ignored.clear
      @pj.block @mojombo
      assert !@grit.add_member(@pj)
    end

    test "does not allow user to be added by blocked user as collab to repo" do
      @pj.ignored.clear
      @pj.block @defunkt
      assert !@grit.add_member(@pj, @defunkt)
    end

    test "does not allow suspended user to be added" do
      suspended = create :suspended_user
      assert !@grit.add_member(suspended)
    end

    test "adds member to business when business set to create user accounts for collaborators", skip_enterprise: true do
      business = create(:business)
      organization = create(:organization, business: business)
      repository = create(:private_repository, owner: organization)

      repository.add_member(@outside_collaborator)

      bua = business.business_user_account_for(@outside_collaborator)
      refute_nil bua
      assert_equal [:outside_collaborator], bua.business_roles
    end

    test "adds member to business when collaborator is added to repository via invitation", skip_enterprise: true do
      if GitHub.repo_invites_enabled?
        business = create(:business)
        organization = create(:organization, business: business)
        repository = create(:private_repository, owner: organization)

        invitation = create(:repository_invitation, repository: repository, invitee: @outside_collaborator)
        invitation.accept!

        bua = business.business_user_account_for(@outside_collaborator)
        refute_nil bua
        assert_equal [:outside_collaborator], bua.business_roles
      end
    end
  end

  context "add_member_without_validation_or_notifications" do
    test "adds the user as a member" do
      refute_includes @ambition.members, @pj

      @ambition.add_member_without_validation_or_notifications(@pj, action: :write)

      assert_includes @ambition.members, @pj
    end

    test "doesn't subscribe the member to the repo" do
      only = [DeliverHookEventJob, ProcessEventJob, UpdateEventFeedsJob]
      perform_enqueued_jobs(only: only) { @ambition.add_member_without_validation_or_notifications(@pj, action: :write) }

      refute_includes @ambition.watchers, @pj
    end

    test "doesn't send an email" do
      ActionMailer::Base.deliveries.clear
      only = [DeliverHookEventJob, ProcessEventJob, UpdateEventFeedsJob]
      perform_enqueued_jobs(only: only) { @ambition.add_member_without_validation_or_notifications(@pj, action: :write) }

      assert_equal 0, ActionMailer::Base.deliveries.size
    end
  end

  context "remove_member" do
    if GitHub.repo_invites_enabled?
      test "cancels pending invitations from the member when removing member from an org-owned repo" do
        invitee = create(:user)
        member = create(:user)
        @internal.add_member(member, action: :admin)
        RepositoryInvitation.invite_to_repo(invitee, member, @internal)
        assert_equal RepositoryInvitation.count, 1
        only = [RemoveUserFromRepoCleanupJob]
        perform_enqueued_jobs(only: only) do
          @internal.remove_member(member)
        end
        assert_equal RepositoryInvitation.count, 0
      end
    end

    test "does not try to remove org members" do
      assert_no_enqueued_jobs(only: RemoveUserFromRepoCleanupJob) do
        refute @grit.remove_member(@org)
      end
    end

    test "returns false if user isn't a member" do
      random_user = create(:user)

      refute @grit.remove_member(random_user)
    end

    test "removes member's access and enqueues background jobs to do the rest of the cleanup" do
      removal_result = @internal.remove_member(@outside_collaborator, @admin)

      assert removal_result
      refute @internal.member?(@outside_collaborator)

      assert_enqueued_jobs 1, only: RemoveUserFromRepoCleanupJob, queue: :remove_user_repo_cleanup
      assert_enqueued_with job: RemoveUserFromRepoCleanupJob,
                           args: [actor_id: @admin.id, member_id: @outside_collaborator.id, repo_id: @internal.id]

      assert_enqueued_jobs 2, only: Packages::SyncPackagePermsOnRepoChangeJob, queue: :sync_package_perms_on_repo_change
      assert_enqueued_with job: Packages::SyncPackagePermsOnRepoChangeJob, args: [repository: @internal]

      if @internal.licensing_enabled?
        assert_enqueued_jobs 1, only: Licensing::SnapshotLicensesJob, queue: :licensing
        assert_enqueued_with job: Licensing::SnapshotLicensesJob, args: [@org.business]
      end
    end

    unless GitHub.enterprise?
      test "remove access from memexes if removed from only repo" do
        memex_project = create(:memex_project, :with_reader, reader: @outside_collaborator, owner: @org)

        only = [RemoveOrgMemberProjectsNextAccessJob]
        perform_enqueued_jobs(only: only) do
          @internal.remove_member(@outside_collaborator)
        end

        granted_actors = UserRole.where(target_type: "MemexProject", target_id: memex_project.id, role: Role.project_reader_role).map(&:actor)
        refute_includes granted_actors, @outside_collaborator
      end
    end

    test "don't remove access from memexes if removed but still access to other repo" do
      extra_repo = create(:repository, owner: @org)
      extra_repo.add_member(@outside_collaborator)

      memex_project = create(:memex_project, :with_reader, reader: @outside_collaborator, owner: @org)

      only = [RemoveOrgMemberProjectsNextAccessJob]
      perform_enqueued_jobs(only: only) do
        @internal.remove_member(@outside_collaborator)
      end

      granted_actors = UserRole.where(target_type: "MemexProject", target_id: memex_project.id, role: Role.project_reader_role).map(&:actor)
      assert_includes granted_actors, @outside_collaborator
    end

    test "don't remove access from memexes if removed from only repo and is member of organization" do
      @org.add_member(@outside_collaborator)

      memex_project = create(:memex_project, :with_reader, reader: @outside_collaborator, owner: @org)

      only = [RemoveOrgMemberProjectsNextAccessJob, RemoveUserFromRepoCleanupJob]
      perform_enqueued_jobs(only: only) do
        @internal.remove_member(@outside_collaborator)
      end

      granted_actors = UserRole.where(target_type: "MemexProject", target_id: memex_project.id, role: Role.project_reader_role).map(&:actor)
      assert_includes granted_actors, @outside_collaborator
    end

    test "forces users to unstar when removed as members of a private repo" do
      @ambition.add_member(@pj)
      @pj.star(@ambition)

      assert @ambition.starred_by?(@pj)
      only = [RemoveUserFromRepoCleanupJob]
      perform_enqueued_jobs(only: only) do
        @ambition.remove_member(@pj)
      end
      refute @ambition.reload.starred_by?(@pj)
    end

    test "unassigns issue when assignee is removed as a member and has no access from other sources" do
      @ambition.add_member(@pj)
      @issue = create :issue, repository: @ambition, user: @defunkt, assignee: @pj

      only = [RemoveUserFromRepoCleanupJob]
      perform_enqueued_jobs(only: only) do
        @ambition.remove_member(@pj)
      end

      refute_equal @pj, @issue.reload.assignee
    end

    test "preserves assignment when assignee is removed as a member and has access from other sources" do
      org      = create(:organization)
      repo     = create(:private_repository, owner: org)
      team     = create(:team, organization: org)
      assignee = create(:user, login: "collaborator")

      # Give the user access to the repository through two sources: as a team
      # member and as a direct collaborator
      org.add_member(assignee)
      team.add_repository(repo, :pull)
      team.add_member(assignee)
      repo.add_member(assignee)

      issue = create(:issue, repository: repo, assignee: assignee)

      repo.remove_member(assignee)
      issue.reload

      assert_equal assignee, issue.assignee
    end

    test "unwatches repo when collaborator is removed and has no access from other sources" do
      org     = create(:organization)
      repo    = create(:private_repository, owner: org)
      watcher = create(:user, login: "watcher")
      GitHub.newsies.get_and_update_settings(watcher) do |settings|
        settings.auto_subscribe = true
      end

      repo.add_member(watcher)

      assert_includes repo.watchers, watcher

      only = [DeleteDependentAbilitiesJob, DeliverHookEventJob, Newsies::DeleteAllForUserAndListsJob, TradeControls::OrganizationComplianceCheckJob, RemoveUserFromRepoCleanupJob]
      perform_enqueued_jobs(only: only) { repo.remove_member(watcher) }
      repo.reload

      refute_includes repo.watchers, watcher
    end

    test "removes user subscription if the repository is private" do
      @ambition.add_member(@pj)
      @pj.watch_repo(@ambition)

      assert_predicate GitHub.newsies.subscription_status(@pj, @ambition), :valid?

      only = [DeleteDependentAbilitiesJob, DeliverHookEventJob, Newsies::DeleteAllForUserAndListsJob, RemoveUserFromRepoCleanupJob]
      perform_enqueued_jobs(only: only) do
        @ambition.remove_member(@pj)
      end

      refute_predicate GitHub.newsies.subscription_status(@pj, @ambition), :valid?
    end

    test "removes user subscription if the remover is the individual being removed" do
      @ambition.add_member(@pj)
      @pj.watch_repo(@ambition)

      assert_predicate GitHub.newsies.subscription_status(@pj, @ambition), :valid?

      only = [DeleteDependentAbilitiesJob, DeliverHookEventJob, Newsies::DeleteAllForUserAndListsJob, RemoveUserFromRepoCleanupJob]
      perform_enqueued_jobs(only: only) do
        @ambition.remove_member(@pj, @pj)
      end

      refute_predicate GitHub.newsies.subscription_status(@pj, @ambition.reload), :valid?
    end

    test "keeps watching repo when collaborator is removed and has access from other sources" do
      org     = create(:organization)
      repo    = create(:private_repository, owner: org)
      team    = create(:team, organization: org)
      watcher = create(:user, login: "watcher")
      GitHub.newsies.get_and_update_settings(watcher) do |settings|
        settings.auto_subscribe = true
      end

      # Give the user access to the repository through two sources: as a team
      # member and as a direct collaborator
      org.add_member(watcher)
      team.add_repository(repo, :pull)
      team.add_member(watcher)
      repo.add_member(watcher)

      repo.remove_member(watcher)
      repo.reload

      assert_includes repo.watchers, watcher
    end

    test "doesn't force user to unstar when removing themselves from a repo" do
      @facebox.add_member(@pj)
      @pj.star(@facebox)

      assert @facebox.starred_by?(@pj)
      @facebox.remove_member(@pj, @pj)
      assert @facebox.starred_by?(@pj)
    end

    test "preserves fork when removing member from public user-owned repository" do
      @simple.add_member(@mojombo)
      create(:fork_repository, forker: @mojombo, fork_repo: @simple)

      refute_nil @simple.find_fork_for_user(@mojombo)

      only = [RemoveUserFromRepoCleanupJob]
      perform_enqueued_jobs(only: only) do
        @simple.remove_member(@mojombo)
      end

      refute_nil @simple.find_fork_for_user(@mojombo)
    end

    test "removes fork when removing member from private user-owned repository" do
      @ambition.add_member(@mojombo)
      create(:fork_repository, forker: @mojombo, fork_repo: @ambition)

      refute_nil @ambition.find_fork_for_user(@mojombo)

      only = [RemoveUserFromRepoCleanupJob]
      perform_enqueued_jobs(only: only) do
        @ambition.remove_member(@mojombo)
      end

      assert_nil @ambition.find_fork_for_user(@mojombo)
    end

    test "removes forks of fork when removing member from private user-owned repository" do
      @ambition.add_member(@mojombo)
      mojombo_fork = create(:fork_repository, forker: @mojombo, fork_repo: @ambition)

      mojombo_fork.add_member(@maddox)
      maddox_fork = create(:fork_repository, forker: @maddox, fork_repo: mojombo_fork)

      maddox_fork.add_member(@pj)
      pj_fork = create(:fork_repository, forker: @pj, fork_repo: maddox_fork)

      only = [RemoveUserFromRepoCleanupJob]
      perform_enqueued_jobs(only: only) do
        @ambition.remove_member(@mojombo)
      end

      assert_predicate mojombo_fork.reload, :deleted?
      assert_predicate maddox_fork.reload, :deleted?
      assert_predicate pj_fork.reload, :deleted?
    end

    test "removes fork when removing member from private org-owned repository" do
      org = create(:organization, plan: "bronze")
      org.allow_private_repository_forking(actor: org.admins.first)

      org_repo = create(:private_repository, owner: org)

      org_repo.add_member(@mojombo)
      create(:fork_repository, forker: @mojombo, fork_repo: org_repo)

      refute_nil org_repo.find_fork_for_user(@mojombo)

      only = [RemoveUserFromRepoCleanupJob]
      perform_enqueued_jobs(only: only) do
        org_repo.remove_member(@mojombo)
      end

      assert_nil org_repo.find_fork_for_user(@mojombo)
    end

    test "preserves fork when removing member from private org-owned repository and the member also has access through a team" do
      org = create(:organization, plan: "bronze")
      org.allow_private_repository_forking(actor: org.admins.first)
      org.add_member(@mojombo)

      org_repo = create(:private_repository, owner: org)
      team     = create(:team, organization: org)
      team.add_repository(org_repo, :pull)
      team.add_member(@mojombo)

      org_repo.add_member(@mojombo)
      create(:fork_repository, forker: @mojombo, fork_repo: org_repo)

      refute_nil org_repo.find_fork_for_user(@mojombo)

      org_repo.remove_member(@mojombo)

      refute_nil org_repo.find_fork_for_user(@mojombo)
    end

    test "sends an email when removing a private fork for abilities users" do
      @ambition.add_member(@mojombo)
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        @ambition.fork(forker: @mojombo)
      end
      ActionMailer::Base.deliveries.clear
      forked_repo, _status = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @ambition.fork(forker: @mojombo) }
      job_args = [{
        repo_nwo: forked_repo.nwo,
        parent_nwo: forked_repo.parent.nwo,
        repo_owner: forked_repo.owner
      }]
      assert_performed_email(mailer: "RepositoryMailer", action: "private_fork_deleted", args: job_args) do
        @ambition.remove_member(@mojombo)
        assert_equal 1, ActionMailer::Base.deliveries.size
        mail = ActionMailer::Base.deliveries[0]
        assert_equal [@mojombo.email], mail.to
      end
    end

    test "leaves public forks alone when removing members" do
      assert @facebox.public?
      @facebox.add_member(@mojombo)
      fork = create(:fork_repository, forker: @mojombo, fork_repo: @facebox)
      only = [RemoveUserFromRepoCleanupJob]
      perform_enqueued_jobs(only: only) do
        @facebox.remove_member(@mojombo)
      end
      assert_equal fork, @facebox.find_fork_for_user(@mojombo)
    end

    context "removing outside collaborator from an internal root" do
      test "removes the user from the repo" do
        assert_equal Repository::INTERNAL_VISIBILITY, @internal.visibility
        assert @internal.member?(@outside_collaborator)

        only = [RemoveUserFromRepoCleanupJob]
        perform_enqueued_jobs(only: only) do
          @internal.remove_member(@outside_collaborator)
        end

        refute @internal.member?(@outside_collaborator)
      end

      test "removes user from other forks they had access to" do
        User.any_instance.stubs(:can_fork?).returns(true)
        Repository.any_instance.stubs(:forking_disabled?).returns(false)

        fork = create(:fork_repository, forker: @admin, fork_repo: @internal)
        fork.add_member(@outside_collaborator)

        assert fork.member?(@outside_collaborator)

        only = [RemoveUserFromRepoCleanupJob]
        perform_enqueued_jobs(only: only) do
          @internal.remove_member(@outside_collaborator)
        end

        refute @internal.member?(@outside_collaborator)
        refute fork.member?(@outside_collaborator)
      end

      test "removes user from forks of forks they had access to" do
        User.any_instance.stubs(:can_fork?).returns(true)
        Repository.any_instance.stubs(:forking_disabled?).returns(false)

        fork = create(:fork_repository, forker: @admin, fork_repo: @internal)
        fork_of_fork = create(:private_repository, owner: @admin_2, name: @admin_2.name, parent: fork)

        fork_of_fork.add_member(@outside_collaborator)
        assert fork_of_fork.member?(@outside_collaborator)

        only = [RemoveUserFromRepoCleanupJob]
        perform_enqueued_jobs(only: only) do
          @internal.remove_member(@outside_collaborator)
        end

        refute @internal.member?(@outside_collaborator)
        refute fork.member?(@outside_collaborator)
        refute fork_of_fork.member?(@outside_collaborator)
      end
    end

    test "removing business member collaborator from an internal root does not remove them from other forks" do
      User.any_instance.stubs(:can_fork?).returns(true)
      Repository.any_instance.stubs(:forking_disabled?).returns(false)

      # This person already has internal rights, but add them as an explicit collaborator
      @internal.add_member(@member)

      fork = create(:fork_repository, forker: @admin, fork_repo: @internal)
      fork.add_member(@member)

      assert fork.member?(@member)

      @internal.remove_member(@member)

      refute @internal.member?(@member)
      assert fork.member?(@member)
    end

    context "removing outside collaborator from an internal fork" do
      test "removes them from the fork" do
        User.any_instance.stubs(:can_fork?).returns(true)
        Repository.any_instance.stubs(:forking_disabled?).returns(false)

        @internal.add_member(@outside_collaborator)

        fork = create(:fork_repository, forker: @admin, fork_repo: @internal)
        fork.add_member(@outside_collaborator)

        assert fork.member?(@outside_collaborator)

        fork.remove_member(@outside_collaborator)

        refute fork.member?(@outside_collaborator)
      end

      test "does not remove them from other forks" do
        User.any_instance.stubs(:can_fork?).returns(true)
        Repository.any_instance.stubs(:forking_disabled?).returns(false)

        @internal.add_member(@outside_collaborator)

        fork_1 = create(:fork_repository, forker: @admin, fork_repo: @internal)
        fork_2 = create(:fork_repository, forker: @member, fork_repo: @internal)

        fork_1.add_member(@outside_collaborator)
        fork_2.add_member(@outside_collaborator)

        assert fork_1.member?(@outside_collaborator)
        assert fork_2.member?(@outside_collaborator)

        fork_1.remove_member(@outside_collaborator)

        refute fork_1.member?(@outside_collaborator)
        assert fork_2.member?(@outside_collaborator)
      end
    end

    test "removing business member from an internal fork does not remove them from other forks" do
      User.any_instance.stubs(:can_fork?).returns(true)
      Repository.any_instance.stubs(:forking_disabled?).returns(false)

      fork_1 = create(:fork_repository, forker: @admin, fork_repo: @internal)
      fork_2 = create(:fork_repository, forker: @admin_2, fork_repo: @internal)

      fork_1.add_member(@member)
      fork_2.add_member(@member)

      assert fork_1.member?(@member)
      assert fork_2.member?(@member)

      fork_1.remove_member(@member)

      refute fork_1.member?(@member)
      assert fork_2.member?(@member)
    end
  end

  test "knows all its members" do
    @grit.add_member @defunkt
    assert @grit.all_members.include?(@mojombo)
    assert @grit.all_members.include?(@defunkt)
  end

  context "mentionable_users_for" do
    test "includes org members without team/collaborator access and direct collaborators when there's a default repository permission" do
      org = create(:organization)
      org.update_default_repository_permission(:read, actor: org.admins.first)

      repo   = create(:private_repository, owner: org)
      member = create(:user, login: "org-member")
      org.add_member(member)

      outside_collaborator = create(:user, login: "outside-collaborator")
      repo.add_member(outside_collaborator, action: :read)

      mentionable_users = repo.mentionable_users_for(member)
      assert_includes mentionable_users, member
      assert_includes mentionable_users, outside_collaborator
    end
  end

  context "mentionable_users" do
    test "includes collaborators and owner" do
      @grit.add_member @defunkt
      assert @grit.mentionable_users.include?(@mojombo)
      assert @grit.mentionable_users.include?(@defunkt)
    end

    test "includes contributors" do
      refute @grit.mentionable_users.include?(@pj)

      CommitContribution.create \
        repository: @grit,
        user: @pj,
        commit_count: 1,
        committed_date: Date.today - 2

      assert @grit.mentionable_users.include?(@pj)
    end

    test "includes child team members" do
      org = create(:organization)
      org.update_default_repository_permission(:none, actor: org.admins.first)

      parent_team = create(:team, organization: org, privacy: :closed)
      child_team = create(:team, organization: org, privacy: :closed, parent_team_id: parent_team.id)

      repo = create(:repository, owner: org)
      parent_team.add_repository(repo, :pull)

      user = create(:user)

      refute repo.mentionable_users.include?(user), "expected user to not be mentionable"
      child_team.add_member(user)
      assert repo.mentionable_users.include?(user), "expected user to be mentionable"
    end

    test "does not include suspended collaborators" do
      suspended = create :suspended_user
      refute @grit.mentionable_users.include?(suspended)

      @grit.add_member(@pj)
      assert @grit.mentionable_users.include?(@pj)

      @pj.suspend("test for the mentionable list")
      refute @grit.mentionable_users.include?(@pj)
    end

    test "does not include suspended contributors" do
      CommitContribution.create \
        repository: @grit,
        user: @defunkt,
        commit_count: 1,
        committed_date: Date.today - 2

      assert @grit.mentionable_users.include?(@defunkt)

      @defunkt.suspend("test for the mentionable list")
      refute @grit.mentionable_users.include?(@defunkt)
    end

    test "is capped, giving precedence to collaborators" do
      @grit.add_member @defunkt

      [[@maddox, Date.today - 1],
        [@pj, Date.today - 5],
        [@pj, Date.today - 4],
        [@pj, Date.today - 3],
        [@pj, Date.today - 2],
      ].each do |user, date|
        CommitContribution.create \
          repository: @grit,
          user: user,
          commit_count: 1,
          committed_date: date
      end

      mentionable_users = Repository.stub_const(:MENTIONABLES_LIMIT, 4) do
        @grit.mentionable_users
      end

      assert_includes mentionable_users, @mojombo
      assert_includes mentionable_users, @defunkt
      assert_includes mentionable_users, @pj
      assert_includes mentionable_users, @maddox
    end

    test "does not include contributions from ghost" do
      User.create_ghost
      CommitContribution.create \
        repository: @grit,
        user: User.ghost,
        commit_count: 1

      refute @grit.mentionable_users.include?(User.ghost)
    end
  end

  context "#all_user_ids" do
    test "returns repo owner" do
      repo = create :repository, owner: @maddox

      assert_includes repo.all_user_ids, @maddox.id
      assert_includes repo.all_user_ids(include_child_teams: false), @maddox.id
    end

    test "returns repo collaborator" do
      org = create :organization, admin: @maddox
      repo = create :repository, owner: org
      repo.add_member @mojombo

      assert_includes repo.all_user_ids, @mojombo.id
      assert_includes repo.all_user_ids(include_child_teams: false), @mojombo.id

      only = [DeleteDependentAbilitiesJob, RemoveForksForInaccessibleRepositoriesJob, SyncOrganizationDefaultRepositoryPermissionJob]
      perform_enqueued_jobs(only: only) { org.update_default_repository_permission(:none, actor: org.admins.first) }
      repo.reload

      assert_includes repo.all_user_ids, @mojombo.id
      assert_includes repo.all_user_ids(include_child_teams: false), @mojombo.id
    end

    test "returns org team member" do
      org = create :organization, admin: @maddox
      team = create(:team, organization: org)
      team.add_member(@mojombo)

      repo = create :repository, owner: org
      team.add_repository(repo, :admin)

      assert_includes repo.all_user_ids(viewer: @maddox), @mojombo.id
      assert_includes repo.all_user_ids(viewer: @maddox, include_child_teams: false), @mojombo.id

      only = [DeleteDependentAbilitiesJob, RemoveForksForInaccessibleRepositoriesJob, SyncOrganizationDefaultRepositoryPermissionJob]
      perform_enqueued_jobs(only: only) { org.update_default_repository_permission(:none, actor: org.admins.first) }
      repo.reload

      assert_includes repo.all_user_ids(viewer: @maddox), @mojombo.id
      assert_includes repo.all_user_ids(viewer: @maddox, include_child_teams: false), @mojombo.id
    end

    test "returns org child team member" do
      org = create :organization, admin: @maddox
      team = create(:team, organization: org, privacy: :closed)
      child_team = create(:team, organization: org, privacy: :closed, parent_team_id: team.id)

      child_team.add_member(@mojombo)

      repo = create :repository, owner: org
      team.add_repository(repo, :admin)

      assert_includes repo.all_user_ids(viewer: @maddox), @mojombo.id
      assert_includes repo.all_user_ids(viewer: @maddox, include_child_teams: false), @mojombo.id

      only = [DeleteDependentAbilitiesJob, RemoveForksForInaccessibleRepositoriesJob, SyncOrganizationDefaultRepositoryPermissionJob]
      perform_enqueued_jobs(only: only) { org.update_default_repository_permission(:none, actor: org.admins.first) }
      repo.reload

      assert_includes repo.all_user_ids(viewer: @maddox), @mojombo.id
      refute_includes repo.all_user_ids(viewer: @maddox, include_child_teams: false), @mojombo.id
    end

    test "returns org admins" do
      org = create :organization, admin: @maddox

      repo = create :repository, owner: org

      assert_includes repo.all_user_ids(viewer: @maddox), @maddox.id
      assert_includes repo.all_user_ids(viewer: @maddox, include_child_teams: false), @maddox.id

      only = [DeleteDependentAbilitiesJob, RemoveForksForInaccessibleRepositoriesJob, SyncOrganizationDefaultRepositoryPermissionJob]
      perform_enqueued_jobs(only: only) { org.update_default_repository_permission(:none, actor: org.admins.first) }
      repo.reload

      assert_includes repo.all_user_ids(viewer: @maddox), @maddox.id
      assert_includes repo.all_user_ids(viewer: @maddox, include_child_teams: false), @maddox.id
    end

    test "returns org members with there is an org default repository permission" do
      org = create :organization, admin: @maddox
      repo = create :repository, owner: org
      org.add_member @mojombo

      assert_includes repo.all_user_ids(viewer: @mojombo), @mojombo.id
      assert_includes repo.all_user_ids(viewer: @mojombo, include_child_teams: false), @mojombo.id

      only = [DeleteDependentAbilitiesJob, RemoveForksForInaccessibleRepositoriesJob, SyncOrganizationDefaultRepositoryPermissionJob]
      perform_enqueued_jobs(only: only) { org.update_default_repository_permission(:none, actor: org.admins.first) }
      repo.reload

      refute_includes repo.all_user_ids(viewer: @mojombo), @mojombo.id
      refute_includes repo.all_user_ids(viewer: @mojombo, include_child_teams: false), @mojombo.id
    end
  end

  context "#all_member_ids" do
    test "includes owner ID when owner is not an organization" do
      repo = create(:repository, owner: @maddox)

      assert_includes repo.all_member_and_owner_ids, @maddox.id
    end

    test "excludes owner ID when owner is blank" do
      repo = build(:repository, owner: nil)

      assert_empty repo.all_member_ids
    end

    test "excludes owner ID when owner is an organization" do
      org = create(:organization)
      repo = create(:repository, owner: org)

      refute_includes repo.all_member_ids, org.id
    end

    test "includes member IDs" do
      repo = create(:repository, owner: @maddox)
      repo.add_member(@mojombo)

      assert_includes repo.all_member_ids, @mojombo.id
    end
  end

  context "#all_member_and_owner_ids" do
    test "doesn't break without an owner" do
      repo = build(:repository)
      repo.owner = nil

      assert_empty repo.all_member_and_owner_ids
    end

    test "returns repo owner" do
      repo = create :repository, owner: @maddox

      assert_includes repo.all_member_and_owner_ids, @maddox.id
      assert_includes repo.all_member_and_owner_ids(include_child_teams: false), @maddox.id
    end

    test "returns repo collaborator" do
      repo = create :repository, owner: @maddox
      repo.add_member @mojombo

      assert_includes repo.all_member_and_owner_ids, @mojombo.id
      assert_includes repo.all_member_and_owner_ids(include_child_teams: false), @mojombo.id
    end

    test "returns org team member" do
      org = create :organization, admin: @maddox
      team = create(:team, organization: org)
      team.add_member(@mojombo)

      repo = create :repository, owner: org
      team.add_repository(repo, :admin)

      assert_includes repo.all_member_and_owner_ids, @mojombo.id
      assert_includes repo.all_member_and_owner_ids(include_child_teams: false), @mojombo.id
    end

    test "returns org child team member" do
      org = create :organization, admin: @maddox
      team = create(:team, organization: org, privacy: :closed)
      child_team = create(:team, organization: org, privacy: :closed, parent_team_id: team.id)

      child_team.add_member(@mojombo)

      repo = create :repository, owner: org
      team.add_repository(repo, :admin)

      assert_includes repo.all_member_and_owner_ids, @mojombo.id
      refute_includes repo.all_member_and_owner_ids(include_child_teams: false), @mojombo.id
    end

    test "returns all org admins when hide_private_org_owners is false (by default)" do
      org = create :organization, admin: @maddox

      repo = create :repository, owner: org

      assert_includes repo.all_member_and_owner_ids, @maddox.id
      assert_includes repo.all_member_and_owner_ids(include_child_teams: false), @maddox.id
    end

    test "returns all org admins when hide_private_org_owners is true but viewer is an org member" do
      org = create :organization, admin: @maddox
      org.add_member @mojombo

      repo = create :repository, owner: org

      assert_includes repo.all_member_and_owner_ids(hide_private_org_owners: true, viewer: @mojombo), @maddox.id
      assert_includes repo.all_member_and_owner_ids(include_child_teams: false), @maddox.id
    end

    test "does not return private org owners when hide_private_org_owners is true and no viewer is provided" do
      org = create :organization, admin: @maddox
      repo = create :repository, owner: org

      refute_includes repo.all_member_and_owner_ids(hide_private_org_owners: true), @maddox.id
    end

    test "knows all its members and owners" do
      org = create :organization, admin: @mojombo
      team = create :team, organization: org, permission: "pull"
      team.add_member @defunkt
      repo = create :repository, owner: org
      team.add_repository repo, :pull

      assert repo.all_members_and_owners.include?(@mojombo)
      assert repo.all_members_and_owners.include?(@defunkt)
      refute repo.all_members_and_owners.include?(org)
    end

    test "includes all repo roles grantees" do
      org = create :organization, admin: @mojombo
      org.add_member @pj
      team = create :team, organization: org, permission: "pull"
      team.add_member @defunkt
      repo = create :repository, owner: org

      assert_same_elements repo.all_members_and_owners, [@mojombo]

      # Grant all repo roles and check again
      result = org.grant_org_role(assignee: @pj, role: OrganizationRole.all_repo_write_role)
      assert result.success?
      result = org.grant_org_role(assignee: team, role: OrganizationRole.all_repo_read_role)
      assert result.success?

      assert_same_elements repo.all_members_and_owners, [@mojombo, @pj, @defunkt]
    end
  end

  context "all_repo_roles" do
    test "returns all repo roles with minimum action" do
      org = create :business_plus_organization, business: @business, admin: @mojombo
      team_owning_the_repo = create :team, organization: org, permission: "pull"
      repo = create :repository, owner: org
      team_owning_the_repo.add_repository repo, :pull

      # set default permissions to none.
      only = [DeleteDependentAbilitiesJob, RemoveForksForInaccessibleRepositoriesJob, SyncOrganizationDefaultRepositoryPermissionJob]
      perform_enqueued_jobs(only: only) { org.update_default_repository_permission(:none, actor: org.admins.first) }

      # there should only be one person in the org. the admin.
      member_ids = repo.direct_or_team_member_ids(viewer: @mojombo)
      assert_same_elements [@mojombo.id], member_ids

      # creating a team with another user and granting an all repo read role to the team.
      team_all_repo_role_to_the_repo = create :team, organization: org, permission: "pull"
      team_all_repo_role_to_the_repo.add_member @pj
      result = org.grant_org_role(assignee: team_all_repo_role_to_the_repo, role: OrganizationRole.all_repo_read_role)
      assert result.success?

      # assigning the write all repo role to a random user
      random_user = create(:user, login: "randomuser")
      org.add_member(random_user)
      result = org.grant_org_role(assignee: random_user, role: OrganizationRole.all_repo_write_role)
      assert result.success?

      # ask for min_action being nil (should return all, including randomuser)
      member_ids = repo.direct_or_team_member_ids(viewer: @mojombo)
      assert_same_elements [@mojombo.id, random_user.id, @pj.id], member_ids

      # ask for min_action being read
      member_ids = repo.direct_or_team_member_ids(viewer: @mojombo, min_action: :read)
      assert_same_elements [@mojombo.id, random_user.id, @pj.id], member_ids

      # ask for min_action being write
      member_ids = repo.direct_or_team_member_ids(viewer: @mojombo, min_action: :write)
      assert_same_elements [@mojombo.id, random_user.id], member_ids

      # ask for min_action being admin
      member_ids = repo.direct_or_team_member_ids(viewer: @mojombo, min_action: :admin)
      assert_same_elements [@mojombo.id], member_ids
    end

    test "returns all repo roles with minimum action and visibility" do
      org = create :business_plus_organization, business: @business, admin: @mojombo
      team_owning_the_repo = create :team, organization: org, permission: "pull"
      repo = create :repository, owner: org
      team_owning_the_repo.add_repository repo, :pull

      # set default permissions to none.
      only = [DeleteDependentAbilitiesJob, RemoveForksForInaccessibleRepositoriesJob, SyncOrganizationDefaultRepositoryPermissionJob]
      perform_enqueued_jobs(only: only) { org.update_default_repository_permission(:none, actor: org.admins.first) }

      # there should only be one person in the org. the admin.
      member_ids = repo.direct_or_team_member_ids(viewer: @mojombo)
      assert_same_elements [@mojombo.id], member_ids

      # creating a secret team, a secret user in the team and adding an all repo role to the secret team:
      secret_team = create(:secret_team, organization: org, name: "#{org.display_login}-secret-team")
      secret_user = create(:user, login: "secretuser")
      secret_team.add_member secret_user
      result = org.grant_org_role(assignee: secret_team, role: OrganizationRole.all_repo_write_role)
      assert result.success?

      # the admin can see secret teams, so it sees two users
      member_ids = repo.direct_or_team_member_ids(viewer: @mojombo)
      assert_same_elements [secret_user.id, @mojombo.id], member_ids

      # adding a non admin member to the team owning the repo directly
      random_user = create(:user, login: "randomuser")
      team_owning_the_repo.add_member(random_user)

      # the random user cannot see the secret team. it just sees the admin and himself
      member_ids = repo.direct_or_team_member_ids(viewer: random_user)
      assert_same_elements [random_user.id, @mojombo.id], member_ids

      # the admin user can see the secret team. it sees everyone including the secret team member
      member_ids = repo.direct_or_team_member_ids(viewer: @mojombo)
      assert_same_elements [random_user.id, secret_user.id, @mojombo.id], member_ids
    end

    test "direct_or_team_member_ids checks permission cache only once" do
      org = create :business_plus_organization, business: @business, admin: @mojombo
      team_owning_the_repo = create :team, organization: org, permission: "pull"
      repo = create :repository, owner: org

      PermissionCache.enable do
        repo.expects(:all_repo_role_grants).once.returns({})

        # the same call should be only invoked once.
        member_ids = repo.direct_or_team_member_ids(viewer: @mojombo, min_action: :write)
        member_ids = repo.direct_or_team_member_ids(viewer: @mojombo, min_action: :write)
      end
    end

    test "direct_or_team_member_ids checks permission cache multiple times" do
      org = create :business_plus_organization, business: @business, admin: @mojombo
      team_owning_the_repo = create :team, organization: org, permission: "pull"
      repo = create :repository, owner: org

      PermissionCache.enable do
        repo.expects(:all_repo_role_grants).twice.returns({})

        # the same call should only invoked twice because calls are different.
        member_ids = repo.direct_or_team_member_ids(viewer: @mojombo, min_action: :read)
        member_ids = repo.direct_or_team_member_ids(viewer: @mojombo, min_action: :write)
      end
    end
  end

  context "#direct_member_ids" do
    test "filters on min action" do
      repo = create :repository, owner: @org
      read_user = create :user
      triage_user = create :user
      write_user = create :user
      maintain_user = create :user
      admin_user = create :user
      [read_user, triage_user, write_user, maintain_user, admin_user].each do |user|
        @org.add_member(user)
      end
      repo.add_member(read_user, action: :read)
      repo.add_member(triage_user, action: :triage)
      repo.add_member(write_user, action: :write)
      repo.add_member(maintain_user, action: :maintain)
      repo.add_member(admin_user, action: :admin)

      read_member_ids = repo.direct_member_ids(min_action: :read)
      assert_same_elements [read_user.id, triage_user.id, write_user.id, maintain_user.id, admin_user.id], read_member_ids

      write_member_ids = repo.direct_member_ids(min_action: :write)
      assert_same_elements [write_user.id, maintain_user.id, admin_user.id], write_member_ids

      admin_member_ids = repo.direct_member_ids(min_action: :admin)
      assert_same_elements [admin_user.id], admin_member_ids
    end

    test "raises error for triage and maintain" do
      assert_raises(ArgumentError) do
        @simple.direct_member_ids(min_action: :triage)
      end
      assert_raises(ArgumentError) do
        @simple.direct_member_ids(min_action: :maintain)
      end
    end
  end

  test "can add a member" do
    # pj doesn't auto-subscribe
    GitHub.newsies.get_and_update_settings(@pj) do |settings|
      settings.auto_subscribe = false
    end

    refute_includes @grit.members, @pj
    refute @grit.stars.pluck(:user_id).include?(@pj.id)
    @grit.add_member(@pj, @mojombo)
    assert_includes @grit.reload.members, @pj
    refute @grit.stars.pluck(:user_id).include?(@pj.id)
    refute_includes @grit.watchers, @pj
  end

  test "can add a member who auto-subscribes" do
    # pj does auto-subscribe
    GitHub.newsies.get_and_update_settings(@pj) do |settings|
      settings.auto_subscribe = true
    end

    refute_includes @grit.members, @pj
    refute_includes @grit.watchers, @pj
    @grit.add_member(@pj, @mojombo)
    assert_includes @grit.reload.members, @pj
    assert_includes @grit.watchers, @pj
    refute @grit.stars.pluck(:user_id).include?(@pj.id)
  end

  test "can remove a member" do
    repo = @ambition
    repo.add_member @mojombo
    assert_includes repo.reload.members, @mojombo
    repo.reload.remove_member(@mojombo)
    refute_includes repo.reload.members, @mojombo
  end

  test "can copy permissions" do
    refute_includes @simple.members, @pj
    @grit.add_member @pj
    assert_includes @grit.members, @pj

    @simple.copy_permissions_of(@grit, @defunkt)
    assert_includes @simple.members, @pj
  end

  test "members are always unique" do
    assert_equal 0, @grit.members.size
    @grit.add_member(@pj, @mojombo)
    assert_equal 1, @grit.members.size
    @grit.add_member(@pj, @mojombo)
    assert_equal 1, @grit.members.size
  end

  test "doesn't copy self permissions" do
    assert_nil @grit.copy_permissions_of(@grit, @defunkt)
  end

  context ".batch_enqueue_update_member" do
    test "enqueues 2 jobs to update the 2 users based on the batch size of 1" do
      org = create(:business_plus_organization, login: "ghec")
      repo = create(:repository, owner: org)
      members = [create(:user), create(:user)]
      members.each do |member|
        org.add_member(member)
        repo.add_member(member, action: :write)
      end
      user_roles = Ability.where(subject_type: "Repository", actor_type: "User", action: :write, subject_id: repo.id)

      BatchUpdateMemberRepoPermissionsJob.expects(:perform_later).twice

      only = [BatchUpdateMemberRepoPermissionsJob]
      perform_enqueued_jobs(only: only) do
        Repository.batch_enqueue_update_member(user_roles: user_roles, action: :maintain, batch_size: 1, organization: org, actor: org.admin)
      end
    end
  end

  context "#repository_action_from_role_name!" do
    test "returns a symbol for admin role" do
      assert_equal :admin, @internal.repository_action_from_role_name!("admin")
    end

    test "return :read/:write for push/pull" do
      assert_equal :read, @internal.repository_action_from_role_name!("pull")
      assert_equal :write, @internal.repository_action_from_role_name!("push")
    end

    test "returns symbol for maintain and triage if plan supports it" do
      assert @internal.fine_grained_permissions_supported?
      assert_equal :triage, @internal.repository_action_from_role_name!("triage")
      assert_equal :maintain, @internal.repository_action_from_role_name!("maintain")
    end

    test "raises FGPsNotSupportedError exception for triage and maintain if plan doesn't support them" do
      refute @facebox.fine_grained_permissions_supported?
      assert_raises Role::FGPsNotSupportedError do
        @facebox.repository_action_from_role_name!("triage")
      end

      assert_raises Role::FGPsNotSupportedError do
        @facebox.repository_action_from_role_name!("maintain")
      end
    end

    test "returns the name of a custom role if custom roles are available" do
      assert_equal @custom_role.name, @internal.repository_action_from_role_name!(@custom_role.name)
    end

    test "raises InvalidCustomRoleError exception if custom role cannot be found" do
      assert_raises Role::InvalidCustomRoleError do
        @internal.repository_action_from_role_name!("not-a-role-name")
      end
    end

    test "raises InvalidPermissionError exception when targeting a user-owned repo" do
      assert_raises Role::InvalidPermissionError do
        @facebox.repository_action_from_role_name!(@custom_role.name)
      end
    end

    test "raises InvalidCustomRoleError exception if targeting a custom role that belongs to another org" do
      org2 = create(:business_plus_org, admin: @admin)
      repo2 = create(:repository, owner: org2)
      assert_raises Role::InvalidCustomRoleError  do
        repo2.repository_action_from_role_name!(@custom_role.name)
      end
    end
  end
end

class EmuRepositoryMembershipDependencyTest < GitHub::TestCase
  include GitHub::LoggerHelper

  fixtures do
    @non_emu      = create(:user)

    @owner        = create(:emu, :owner)
    @business     = @owner.enterprise_managed_business

    @admin_member = create(:emu, business: @business, login: "admin-member")
    @member       = create(:emu, business: @business)
    @member2      = create(:emu, business: @business)
    @member3      = create(:emu, business: @business)
    @non_org_emu  = create(:emu, business: @business)
    @non_member   = create(:emu, business: @business)
    @ent2_member  = create(:emu)

    @org          = create(:business_plus_organization, business: @business, admin: @owner)
    @org.add_member(@member, action: :admin)
    @org.add_member(@member2, action: :write)
    @org.add_member(@member3, action: :write)

    @org_repo     = create(:repository, owner: @org)
    @repo         = create(:repository, owner: @member)
    @repo.add_member(@member2)

    @org2         = create(:business_plus_organization, business: @business, admin: @owner)
    @org2_member  = create(:emu, business: @business)
    @org2.add_member(@org2_member, action: :admin)

    @org.reload
    @org_repo.reload
  end

  context "#can_add_user?" do
    test "admin can add an organization member to organization repo" do
      assert @org_repo.can_add_user?(@member3, @owner)
      assert @org_repo.can_add_user?(@member3, @member)
    end

    test "member cannot add another organization member to organization repo" do
      refute @org_repo.can_add_user?(@member3, @member2)
    end

    test "non emu cannot be added to organization repo" do
      refute @org_repo.can_add_user?(@non_emu, @owner)
    end

    context "non organization member added to organization repo" do
      test "when repository_collaborators_for_emu disabled" do
        GitHub.flipper[:repository_collaborators_for_emu].disable(@business)
        refute @org_repo.can_add_user?(@non_member, @owner)
      end

      test "repo admin when repository_collaborators_for_emu enabled" do
        GitHub.flipper[:repository_collaborators_for_emu].enable(@business)
        assert @org_repo.can_add_user?(@non_member, @member)
      end

      test "when repository_collaborators_for_emu enabled" do
        GitHub.flipper[:repository_collaborators_for_emu].enable(@business)
        assert @org_repo.can_add_user?(@non_member, @owner)
      end
    end

    context "different organization member added to organization repo" do
      test "when repository_collaborators_for_emu disabled" do
        GitHub.flipper[:repository_collaborators_for_emu].disable(@business)
        refute @org_repo.can_add_user?(@org2_member, @owner)
      end

      test "repo admin when repository_collaborators_for_emu disabled" do
        GitHub.flipper[:repository_collaborators_for_emu].disable(@business)
        refute @org_repo.can_add_user?(@org2_member, @member)
      end

      test "when repository_collaborators_for_emu enabled" do
        GitHub.flipper[:repository_collaborators_for_emu].enable(@business)
        assert @org_repo.can_add_user?(@org2_member, @owner)
      end

      test "repo admin when repository_collaborators_for_emu enabled" do
        GitHub.flipper[:repository_collaborators_for_emu].enable(@business)
        assert @org_repo.can_add_user?(@org2_member, @member)
      end
    end

    test "different business member cannot be added to organization repo" do
      refute @org_repo.can_add_user?(@ent2_member, @owner)
    end

    test "owner can add collaborators to user repo" do
      assert @repo.can_add_user?(@member3, @member)
      assert @repo.can_add_user?(@org2_member, @member)
      assert @repo.can_add_user?(@non_member, @member)
    end

    test "non emu cannot be added to user repo" do
      refute @repo.can_add_user?(@non_emu, @member)
    end

    test "different business member cannot be added to user repo" do
      refute @repo.can_add_user?(@ent2_member, @member)
    end
  end

  test "logs EMU repository collaborators addition" do
    GitHub.flipper[:repository_collaborators_for_emu].enable(@business)
    expected_log = {
      "Body": "EMU repository collaborator added",
      "code.function": "log_emu_repository_collaborator_added",
      "gh.repo.id": @org_repo.id,
      "gh.user.id": @org2_member.id,
      "gh.business.id": @business.id
    }

    assert_logged(**expected_log) do
      @org_repo.add_member_without_validation_or_notifications(@org2_member, action: :write)
      assert_includes @org_repo.members, @org2_member
    end
  end
end unless GitHub.single_business_environment?
