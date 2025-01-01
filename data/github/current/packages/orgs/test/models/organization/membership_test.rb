# typed: true
# frozen_string_literal: true

require "test_helper"

module MembershipTestHelper
  def create_direct_member_of(org, visibility: :private)
    T.bind(self, GitHub::TestCase)
    user = create(:user)
    org.add_member(user)
    org.publicize_member(user) if visibility == :public

    user
  end

  def add_members_to_org(org, users, visibility: :private)
    T.bind(self, GitHub::TestCase)
    users.map do |user|
      org.add_member(user)
      org.publicize_member(user) if visibility == :public
    end
  end

  def create_member_of(team, visibility: :private)
    T.bind(self, GitHub::TestCase)
    user = create(:user)
    team.add_member(user)
    team.organization.publicize_member(user) if visibility == :public

    user
  end

  def create_comprehensive_org_users
    T.bind(self, GitHub::TestCase)
    @team = create(:team, organization: @org)

    # Make a public team member, a public direct member, and a public owner
    @public_direct_member = T.unsafe(self).create_direct_member_of(@org, visibility: :public)
    @public_team_member   = T.unsafe(self).create_member_of(@team, visibility: :public)
    @org.publicize_member(@owner)

    # Make a private team member and a private direct member
    @concealed_direct_member = T.unsafe(self).create_direct_member_of(@org, visibility: :private)
    @concealed_team_member   = T.unsafe(self).create_member_of(@team, visibility: :private)
  end

  def assert_restorable_memberships_are_saved(memberships, member)
    T.bind(self, GitHub::TestCase)
    restorable_memberships = Restorable::Membership.all.map do |m|
      [m.restorable_id, m.subject_type, m.subject_id, m.action]
    end

    restorable_id = Restorable::OrganizationUser.most_recent(@org, member).first!.restorable_id

    memberships.each do |m|
      membership = [
        restorable_id,
        m.subject_type,
        m.subject_id,
        m.action,
      ]
      assert_includes restorable_memberships, membership
    end
  end

  def assert_restorable_watched_repositories_are_saved(repos, member, subscriptions)
    T.bind(self, GitHub::TestCase)
    restorable_watched_repos = Restorable::WatchedRepository.all.map do |r|
      [r.restorable_id, r.repository_id, r.ignored]
    end

    repos = WatchedRepositories::SubscriptionDetails
      .decorate_collection(repos, subscriptions: subscriptions)

    restorable_id = Restorable::OrganizationUser.most_recent(@org, member).first!.restorable_id
    repos.each do |r|
      repo = [restorable_id, r.id, r.ignored]
      assert_includes restorable_watched_repos, repo
    end
  end

  def assert_restorable_repository_stars_are_saved(repos, member)
    T.bind(self, GitHub::TestCase)
    restorable_repo_stars = Restorable::RepositoryStar.all.map do |r|
      [r.restorable_id, r.repository_id]
    end

    restorable_id = Restorable::OrganizationUser.most_recent(@org, member).first!.restorable_id
    repos.each do |r|
      repo = [restorable_id, r.id]
      assert_includes restorable_repo_stars, repo
    end
  end

  def assert_restorable_assigned_issues_are_saved(issues, member)
    T.bind(self, GitHub::TestCase)
    restorable_assigned_issues = Restorable::IssueAssignment.all.map do |i|
      [i.restorable_id, i.issue_id]
    end

    restorable_id = Restorable::OrganizationUser.most_recent(@org, member).first!.restorable_id
    issues.each do |i|
      issue = [restorable_id, i.id]
      assert_includes restorable_assigned_issues, issue
    end
  end

  def assert_restorable_repositories_are_saved(repos, member)
    T.bind(self, GitHub::TestCase)
    restorable_repos = Restorable::Repository.all.map do |r|
      [r.restorable_id, r.archived_repository_id]
    end

    restorable_id = Restorable::OrganizationUser.most_recent(@org, member).first!.restorable_id
    repos.each do |r|
      repo = [restorable_id, r.id]
      assert_includes restorable_repos, repo
    end
  end

  def assert_restorable_custom_email_routings_are_saved(org_id_and_email_hash, member)
    T.bind(self, GitHub::TestCase)
    restorable_custom_email_routings = Restorable::CustomEmailRouting.all.map do |cer|
      [cer.restorable_id, cer.organization_id, cer.email]
    end

    restorable_id = Restorable::OrganizationUser.most_recent(@org, member).first!.restorable_id
    org_id_and_email_hash.each do |org_id, email|
      custom_email_routing = [restorable_id, org_id, email]
      assert_includes restorable_custom_email_routings, custom_email_routing
    end
  end

  def assert_org_user_is_restorable
    T.bind(self, GitHub::TestCase)
    organization_user = Restorable::OrganizationUser.most_recent(@org, @user).first!
    assert_equal true, organization_user.restorable?
  end
end

class OrganizationMembershipTest < GitHub::TestCase
  include MembershipTestHelper
  include ApiProgrammaticGrantHelpers

  PackagesMock = Struct.new(:packages)
  SubscriptionMock = Struct.new(:list_id, :ignored?)
  fixtures do
    @owner = create(:user, login: "org-admin")
    @org = create(:organization, login: "org", admin: @owner)
    @org.allow_private_repository_forking(actor: @owner)

    METADATA_CLIENT = ::PackageRegistry::Twirp::MetadataClient
  end

  setup do
    ActionMailer::Base.deliveries.clear
    METADATA_CLIENT.any_instance.stubs(:get_packages_by_repo).returns(PackagesMock.new(packages: []))
    self.perform_enqueued_jobs = [
      RemoveOrgMemberJob,
      RevokeOrgMembershipAbilitiesJob,
    ]
  end

  context "last_admin?" do
    test "returns false when org admin" do
      assert @org.adminable_by?(@owner), "org owner should be able to admin org"
      refute @org.can_leave?(@owner), "should not be able to leave org"
      assert @org.last_admin?(@owner), "can't remove owner from org"
    end

    test "returns true when last admin" do
      assert @org.adminable_by?(@owner), "should be an admin"
      assert_equal [@owner], @org.admins
      assert @org.last_admin?(@owner), "owner should be last admin"
    end
  end

  context "add_admin" do
    test "makes the user an org owner" do
      new_admin = create(:user, login: "new-admin")
      refute @org.adminable_by?(new_admin)

      @org.add_admin(new_admin)

      assert @org.adminable_by?(new_admin)
    end
  end

  context "add_member" do
    test "grants a direct Ability" do
      user = create(:user)

      @org.add_member user, action: :write
      ab = user.ability @org

      assert_equal user, ab.actor
      assert_equal @org, ab.subject
      assert ab.write?
      assert ab.direct?
    end

    test "instruments the correct org.add_member event" do
      user = create(:user)
      events = subscribe "org.add_member"

      @org.add_member user, action: :write

      expected_payload = {
        org: @org.login,
        org_id: @org.id,
        user: user.login,
        user_id: user.id,
        permission: :write,
      }

      assert event = events.pop, "expected an event"
      assert_equal expected_payload, event.payload
    end

    test "skips instrumentation when specified" do
      user = create(:user)
      events = subscribe "org.add_member"

      @org.add_member(user, perform_instrumentation: false)

      assert_nil events.pop
    end

    test "does nothing if the user is already a member" do
      user = create(:user)
      @org.add_member user

      assert_able user, :read, @org

      @org.add_member user, action: :write
      refute_able user, :write, @org
    end

    test "sends an admin added email if the action is admin" do
      user = create(:user)
      assert_difference("ActionMailer::Base.deliveries.size", 1) do
        perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
          @org.add_member user, action: :admin
        end
      end
    end

    test "doesn't sends an admin added email if the action is not admin" do
      user = create(:user)
      assert_no_difference "ActionMailer::Base.deliveries.size" do
        @org.add_member user, action: :read
      end
    end

    test "outside collaborator maintains access to memex projects when added to org", skip_enterprise: true do
      # Create an outside collaborator
      outside_collaborator = create(:user)
      repo = create(:repository, owner: @org)
      team = create(:team, organization: @org)
      team.add_repository repo, :pull
      @org.add_member(outside_collaborator)
      team.add_member(outside_collaborator)
      @org.convert_to_outside_collaborator!(outside_collaborator)
      refute @org.direct_member?(outside_collaborator)

      # Give the outside collaborator read-access to memex project 1
      memex_project_1 = create(:memex_project, :with_reader, reader: outside_collaborator, owner: @org)

      # Give the outside collaborator admin-access to memex project 2
      memex_project_2 = create(:memex_project, :with_admin, admin: outside_collaborator, owner: @org)

      # Add the outside collaborator back to the org.
      @org.add_member(outside_collaborator)
      assert @org.direct_member?(outside_collaborator)

      # Asssert that the outside collaborator has read access to the memex project 1
      granted_actors = UserRole.where(target_type: "MemexProject", target_id: memex_project_1.id, role: Role.project_reader_role).map(&:actor)
      assert_includes granted_actors, outside_collaborator

      # Asssert that the outside collaborator has admin access to the memex project 2
      granted_actors = UserRole.where(target_type: "MemexProject", target_id: memex_project_2.id, role: Role.project_admin_role).map(&:actor)
      assert_includes granted_actors, outside_collaborator
    end

    test "adds member even if user does not meet 2fa requirement" do
      user = create(:user)
      @org.enable_two_factor_requirement(actor: @owner)
      @org.add_member(user)

      assert_includes @org.members, user
    end

    test "adds member if user meets 2fa requirement" do
      user = create(:user)
      make_two_factor_credential(user)
      @org.enable_two_factor_requirement(actor: @owner)
      @org.add_member(user)

      assert_includes @org.members, user
    end

    test "does not add member if the organization SAML SSO requirement is not met" do
      user = create(:user)
      @org.update(plan: "business_plus")
      create(:organization_saml_provider, :enforced, organization: @org)

      @org.add_member(user)

      refute_includes @org.members, user
    end

    if GitHub.external_identity_session_enforcement_enabled?
      test "does not add member if the organization's Business SAML SSO requirement is not met" do
        user = create(:user)
        @org.update(plan: "business_plus")
        business = create(:business_saml_provider).business
        business.add_organization(@org)
        @org.reload

        @org.add_member(user)

        refute_includes @org.members, user
      end
    end
  end

  context "remove_member" do
    test "revokes the user's direct Ability on the organization" do
      user = create_direct_member_of(@org)
      create(:team, organization: @org).add_member(user)

      assert @org.direct_member?(user)

      @org.remove_member(user)

      refute @org.direct_member?(user)
    end

    test "instruments the correct org.remove_member event" do
      user = create_direct_member_of(@org)
      events = subscribe "org.remove_member"

      actor = create(:user)
      GitHub.context.push(actor: actor)

      @org.remove_member user

      expected_payload = {
        org: @org.login,
        org_id: @org.id,
        user: user.login,
        user_id: user.id,
        reason: nil,
        membership_types: ["direct_member"],
        actor: actor.login,
        actor_id: actor.id,
      }

      assert event = events.pop, "expected an event"
      assert_equal expected_payload, event.payload
    end

    test "instruments when remove_member_with_instrumentation is called" do
      user = create_direct_member_of(@org)
      events = subscribe "org.remove_member"
      reason = Organization::RemovedMemberNotification::USER_ACCOUNT_DELETED

      @org.remove_member_with_instrumentation(user, reason: reason)

      expected_payload = {
        org: @org.login,
        org_id: @org.id,
        user: user.login,
        user_id: user.id,
        reason: reason,
        membership_types: ["unaffiliated"],
        actor: nil,
        spammy: false,
      }

      assert event = events.pop, "expected an event"
      assert_equal expected_payload, event.payload
    end

    test "instruments when remove_member_with_instrumentation is called with actor" do
      user = create_direct_member_of(@org)
      events = subscribe "org.remove_member"
      reason = Organization::RemovedMemberNotification::USER_ACCOUNT_DELETED

      actor = create(:user)

      @org.remove_member_with_instrumentation(user, actor: actor, reason: reason)

      expected_payload = {
        org: @org.login,
        org_id: @org.id,
        user: user.login,
        user_id: user.id,
        reason: reason,
        membership_types: ["unaffiliated"],
        actor: actor.login,
        actor_id: actor.id,
        spammy: false,
      }

      assert event = events.pop, "expected an event"
      assert_equal expected_payload, event.payload
    end

    test "does not instrument remove_member_without_callbacks_and_notifications" do
      user = create_direct_member_of(@org)
      events = subscribe "org.remove_member"

      @org.remove_member_without_callbacks_and_notifications(user)

      refute event = events.pop, "did not expect an event"
    end

    test "revokes a user's direct access to the organization's repositories" do
      user = create_direct_member_of(@org)
      repo = create(:repository, owner: @org)
      repo2 = create(:repository, owner: @org)
      owner = create(:user)
      user_repo = create(:repository, :minimal, owner: owner)
      repo.add_member user
      repo2.add_member user
      user_repo.add_member user

      assert_same_elements [repo, repo2, user_repo], user.member_repositories

      @org.remove_member user

      assert_equal [user_repo], user.reload.member_repositories
    end

    test "removes a user's forks when they had previously had access through the org's default repository permission" do
      @org.update_default_repository_permission(:read, actor: @owner)
      user = create_direct_member_of(@org)
      repo = create(:private_repository, owner: @org, from_example: :simple)
      fork = create(:fork_repository, forker: user, fork_repo: repo)

      assert_equal fork, Repositories::Public.find_active(fork.id)

      only = [RemoveOrgMemberJob, RemoveOrgMemberForksJob, RevokeOrgMembershipAbilitiesJob, BulkRemoveOrgMemberForksJob]
      perform_enqueued_jobs(only: only) { @org.remove_member(user) }

      assert_nil Repositories::Public.find_active(fork.id)
    end

    test "can keep a user's direct repo access" do
      user = create_direct_member_of(@org)
      create(:team, organization: @org).add_member(user)

      repo = create(:repository, owner: @org)
      repo.add_member(user)

      assert @org.direct_member?(user)
      assert repo.pushable_by?(user)

      @org.remove_member(user, remove_direct_repo_access: false)

      refute @org.direct_member?(user)
      assert repo.pushable_by?(user)
    end

    test "revokes a user's direct access to the organization's projects" do
      org_member = create_direct_member_of(@org)
      project = create(:project, owner: @org)
      project.update_user_permission(org_member, :read)

      assert_includes project.direct_collaborators, org_member

      @org.remove_member(org_member)
      project.reload

      refute_includes project.direct_collaborators, org_member
    end

    test "revokes user's direct access to the organization's memex projects", skip_enterprise: true do
      org_member = create_direct_member_of(@org)
      memex_project = create(:memex_project, :with_reader, reader: org_member, owner: @org)

      perform_enqueued_jobs(only: [RemoveOrgMemberJob, RemoveOrgMemberProjectsNextAccessJob]) do
        @org.remove_member(org_member)
      end

      granted_actors = UserRole.where(target_type: "MemexProject", target_id: memex_project.id, role: Role.project_reader_role).map(&:actor)
      refute_includes granted_actors, org_member
    end

    test "revokes user's direct access to the organization's memex projects, when repos direct access was revoked (not an outside collaborator)", skip_enterprise: true do
      org_member = create_direct_member_of(@org)
      memex_project = create(:memex_project, :with_reader, reader: org_member, owner: @org)
      repo = create(:repository, owner: @org)
      repo.add_member(org_member)

      perform_enqueued_jobs(only: [RemoveOrgMemberJob, RemoveOrgMemberProjectsNextAccessJob]) do
        @org.remove_member(org_member)
      end

      granted_actors = UserRole.where(target_type: "MemexProject", target_id: memex_project.id, role: Role.project_reader_role).map(&:actor)
      refute_includes granted_actors, org_member
    end

    test "retains user's direct access to the organization's memex projects when user retains access to some repos (outside collaborator)", skip_enterprise: true do
      org_member = create_direct_member_of(@org)
      memex_project = create(:memex_project, :with_reader, reader: org_member, owner: @org)
      repo = create(:repository, owner: @org)
      repo.add_member(org_member)

      perform_enqueued_jobs(only: [RemoveOrgMemberJob, RemoveOrgMemberProjectsNextAccessJob]) do
        @org.remove_member(org_member, remove_direct_repo_access: false)
      end

      granted_actors = UserRole.where(target_type: "MemexProject", target_id: memex_project.id, role: Role.project_reader_role).map(&:actor)
      assert_includes granted_actors, org_member
    end

    test "revokes a user's direct access to the organization's memex projects, even when asked to retain direct access to repos, but user didn't have any direct access (not an outside collaborator)", skip_enterprise: true do
      org_member = create_direct_member_of(@org)
      memex_project = create(:memex_project, :with_reader, reader: org_member, owner: @org)

      perform_enqueued_jobs(only: [RemoveOrgMemberJob, RemoveOrgMemberProjectsNextAccessJob]) do
        @org.remove_member(org_member, remove_direct_repo_access: false)
      end

      granted_actors = UserRole.where(target_type: "MemexProject", target_id: memex_project.id, role: Role.project_reader_role).map(&:actor)
      refute_includes granted_actors, org_member
    end

    test "can't remove the organization's last owner" do
      assert_raises Organization::NoAdminsError do
        @org.remove_member(@owner)
      end

      assert @org.adminable_by?(@owner)
    end

    test "revokes the user's billing manager role" do
      disable_feature_flag(:remove_org_member_repo_stars_job_use_bulk_ci_only) # This feature prevents creation of restorables
      billing_manager = create(:user)
      @org.add_member(billing_manager)
      @org.billing.add_manager(billing_manager, actor: @owner)

      assert @org.billing_manager?(billing_manager)
      assert @org.direct_or_team_member?(billing_manager)

      @org.remove_member(billing_manager)
      refute @org.billing_manager?(billing_manager)
      refute @org.direct_member?(billing_manager)
    end

    test "sends a removal email to the user" do
      disable_feature_flag(:remove_org_member_repo_stars_job_use_bulk_ci_only) # This feature prevents creation of restorables
      perform_enqueued_jobs(only: [RemoveOrgMemberJob, ApplicationDeliveryJob]) do
        user = create_direct_member_of(@org)
        assert_difference "ActionMailer::Base.deliveries.size" do
          @org.remove_member user
        end
      end
    end

    test "doesn't send a removal email to the user if they are suspended" do
      user = create_direct_member_of(@org)
      user.suspend "because"
      assert_no_difference "ActionMailer::Base.deliveries.size" do
        @org.remove_member user
      end
    end
  end

  context "update_member" do
    test "updates the action of a direct member" do
      org_admin = create(:user)
      @org.add_admin(org_admin)

      pre_update_ab = Authorization.service.most_capable_ability_between(actor: org_admin, subject: @org)
      refute_nil pre_update_ab
      assert pre_update_ab.admin?

      @org.update_member(org_admin, action: :read)
      post_update_ab = Authorization.service.most_capable_ability_between(actor: org_admin, subject: @org)
      assert post_update_ab.read?
    end

    test "instruments the correct org.update_member event" do
      org_admin = create(:user)
      @org.add_admin(org_admin)
      old_action = Authorization.service.most_capable_ability_between(actor: org_admin, subject: @org).action.to_sym
      events = subscribe "org.update_member"

      assert_equal :admin, old_action
      @org.update_member(org_admin, action: :read)

      expected_payload = {
        org: @org.login,
        org_id: @org.id,
        user: org_admin.login,
        user_id: org_admin.id,
        permission: :read,
        old_permission: old_action,
      }

      assert event = events.pop, "expected an event"
      assert_equal expected_payload, event.payload
    end

    test "errors when trying to update the last owner to a member" do
      assert_equal [@owner], @org.admins

      assert_raises Organization::NoAdminsError do
        @org.update_member(@owner, action: :read)
      end
    end

    test "doesn't error when you try to update the only owner to an owner" do
      assert_equal [@owner], @org.admins

      @org.update_member(@owner, action: :admin)
    end

    test "sends an email when updating a member to owner" do
      user = create(:user)
      @org.add_member user, action: :read
      assert_difference("ActionMailer::Base.deliveries.size", 1) do
        perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
          @org.update_member user, action: :admin
        end
      end
    end

    test "doesn't send an email when 'updating' an owner to still be an owner" do
      user = create(:user)
      @org.add_admin user

      assert_no_difference("ActionMailer::Base.deliveries.size") do
        @org.update_member user, action: :admin
      end
    end

    test "when demoting an org owner, removes forks of repositories the user no longer has access to" do
      @org.update_default_repository_permission(:none, actor: @owner)

      user = create(:user)
      @org.add_member(user, action: :admin)
      push_repo = create(:private_repository, owner: @org, name: "push-repo", from_example: :simple)
      fork_of_push_repo = create(:fork_repository, forker: user, fork_repo: push_repo)
      assert push_repo.pullable_by?(user)

      only = [RemoveForksForInaccessibleRepositoriesJob]
      perform_enqueued_jobs(only: only) { @org.update_member(user, action: :read) }

      refute push_repo.pullable_by?(user)
      assert_nil Repositories::Public.find_active(fork_of_push_repo.id)
    end

    test "when demoting an org owner, does not remove forks for repositories the user still has access to" do
      user = create(:user)
      @org.add_member(user, action: :admin)
      push_repo = create(:private_repository, owner: @org, name: "push-repo", from_example: :simple)
      fork_of_push_repo = create(:fork_repository, forker: user, fork_repo: push_repo)
      assert push_repo.pullable_by?(user)

      @org.update_member(user, action: :read)

      # User still has access to the push_repo via the default repo permission setting
      assert push_repo.pullable_by?(user)
      assert Repositories::Public.find_active(fork_of_push_repo.id)
    end

    test "when demoting an org admin enqueues a job to revoke programmatic access grants", skip_if_feature_enabled: :skip_org_pat_grant_removal_when_demoting_admin do
      admin = create(:user)
      @org.add_member(admin, action: :admin)
      pat = make_user_programmatic_access_with_grant(requester: admin, target: @org)

      @org.add_member(admin)
      assert_performed_with(
        job: RevokeOrgMemberProgrammaticAccessGrantsJob,
        args: [@org, admin],
        queue: "programmatic_access_grants",
      ) do
        @org.update_member(admin, action: :read)
      end

      assert_predicate pat.organization_programmatic_access_grants, :empty?
    end

    test "does not revoke programmatic access grants unless admin is being demoted", skip_if_feature_enabled: :skip_org_pat_grant_removal_when_demoting_admin do
      user = create(:user)
      @org.add_member(user, action: :read)
      pat = make_user_programmatic_access_with_grant(requester: user, target: @org)

      @org.add_member(user)

      assert_no_enqueued_jobs(only: RevokeOrgMemberProgrammaticAccessGrantsJob) do
        @org.update_member(user, action: :admin)
      end

      assert_predicate pat.organization_programmatic_access_grants, :present?
    end

    test "does not revoke programmatic access grants if there is no change in action" do
      user = create(:user)
      @org.add_member(user, action: :admin)
      pat = make_user_programmatic_access_with_grant(requester: user, target: @org)

      @org.add_member(user)
      assert_no_enqueued_jobs(only: RevokeOrgMemberProgrammaticAccessGrantsJob) do
        @org.update_member(user, action: :admin)
      end

      assert_predicate pat.organization_programmatic_access_grants, :present?
    end
  end

  context "convert_to_outside_collaborator!" do
    test "removes the specified member from all teams and keeps their repository access" do
      org_member = create(:user, login: "org-member")
      @org.add_member(org_member)

      team = create(:team, organization: @org)
      team.add_member(org_member)

      pull_repo = create(:private_repository, :minimal, owner: @org, name: "pull-repo")
      team.add_repository(pull_repo, :pull)

      push_repo = create(:private_repository, owner: @org, name: "push-repo", from_example: :simple)
      team.add_repository(push_repo, :push)
      fork_of_push_repo = create(:fork_repository, forker: org_member, fork_repo: push_repo)

      admin_repo = create(:private_repository, :minimal, owner: @org, name: "admin-repo")
      team.add_repository(admin_repo, :admin)

      collab_repo = create(:private_repository, :minimal, owner: @org, name: "collab-repo")
      collab_repo.add_member(org_member)

      assert @org.direct_or_team_member?(org_member)
      assert pull_repo.pullable_by?(org_member)
      assert push_repo.pushable_by?(org_member)
      assert fork_of_push_repo.pushable_by?(org_member)
      assert admin_repo.adminable_by?(org_member)
      assert collab_repo.pushable_by?(org_member)

      perform_enqueued_jobs(only: [RevokeOrgMembershipAbilitiesJob, RemoveOrgMemberJob]) do
        @org.convert_to_outside_collaborator!(org_member)
      end

      refute @org.direct_or_team_member?(org_member)
      assert pull_repo.pullable_by?(org_member)
      assert push_repo.pushable_by?(org_member)
      assert fork_of_push_repo.pushable_by?(org_member)
      assert admin_repo.adminable_by?(org_member)
      assert collab_repo.pushable_by?(org_member)
    end

    test "keeps permissions for org repo forks" do
      org_member = create(:user, login: "org-member")
      @org.add_member(org_member)

      team = create(:team, organization: @org)
      team.add_member(org_member)

      repo = create(:private_repository, owner: @org, from_example: :simple)
      team.add_repository(repo, :pull)

      fork = create(:fork_repository, forker: org_member, fork_repo: repo)
      fork.teams.each { |t| t.remove_repository(fork) }

      assert repo.pullable_by?(org_member)
      assert fork.adminable_by?(org_member)

      @org.convert_to_outside_collaborator!(org_member)

      assert repo.pullable_by?(org_member)
      assert fork.adminable_by?(org_member)
    end

    test "doesn't add the person to private forks made by other users" do
      jobs = [
        RepositoryAddTeamsJob,
        RemoveOrgMemberJob,
        RevokeOrgMembershipAbilitiesJob,
      ]
      perform_enqueued_jobs(only: jobs) do
        org_member_1 = create(:user)
        org_member_2 = create(:user)
        @org.add_member(org_member_1)
        @org.add_member(org_member_2)

        team = create(:team, organization: @org)
        team.add_member(org_member_1)
        team.add_member(org_member_2)

        private_repo = create(:private_repository, owner: @org, name: "private-repo", from_example: :simple)
        team.add_repository(private_repo, :push)

        org_member_1_fork = create(:fork_repository, forker: org_member_1, fork_repo: private_repo)
        org_member_2_fork = create(:fork_repository, forker: org_member_2, fork_repo: private_repo)

        assert org_member_1_fork.adminable_by?(org_member_1)
        assert org_member_2_fork.pushable_by?(org_member_1)

        @org.convert_to_outside_collaborator!(org_member_1)

        assert org_member_1_fork.adminable_by?(org_member_1)
        refute org_member_2_fork.pullable_by?(org_member_1)
      end
    end

    test "doesn't delete the person's private forks" do
      org_member = create(:user, login: "org-member")
      @org.add_member(org_member)

      team = create(:team, organization: @org)
      team.add_member(org_member)

      private_repo = create(:private_repository, owner: @org, name: "private-repo", from_example: :simple)
      team.add_repository(private_repo, :pull)

      create(:fork_repository, forker: org_member, fork_repo: private_repo)

      assert org_member.repositories.find_by_name("private-repo").pushable_by?(org_member)

      @org.convert_to_outside_collaborator!(org_member)

      assert org_member.repositories.find_by_name("private-repo").pushable_by?(org_member)
    end

    test "doesn't add the person to all of the organization's repositories when there's a default repository permission" do
      direct_member = create(:user, login: "direct-member")
      @org.add_member(direct_member)

      team      = create(:team, organization: @org)
      team_repo = create(:private_repository, :minimal, owner: @org, name: "team-repo")
      team.add_member(direct_member)
      team.add_repository(team_repo, :pull)

      collab_repo = create(:private_repository, :minimal, owner: @org, name: "collab-repo")
      collab_repo.add_member(direct_member, action: :read)

      default_permission_repo = create(:private_repository, :minimal, owner: @org, name: "default-permission-repo")

      perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) { @org.update_default_repository_permission(:write, actor: @owner) }

      assert team_repo.pushable_by?(direct_member)
      assert collab_repo.pushable_by?(direct_member)
      assert default_permission_repo.pushable_by?(direct_member)

      perform_enqueued_jobs(only: [RevokeOrgMembershipAbilitiesJob, RemoveOrgMemberJob]) do
        @org.convert_to_outside_collaborator!(direct_member)
      end

      assert team_repo.pullable_by?(direct_member)
      assert collab_repo.pullable_by?(direct_member)
      refute default_permission_repo.pullable_by?(direct_member)
    end

    test "doesn't lower the person's existing collaborator access if they have a lower team permission too" do
      direct_member = create(:user, login: "direct-member")
      @org.add_member(direct_member)

      repo = create(:repository, owner: @org)
      repo.add_member(direct_member, action: :write)

      team = create(:team, organization: @org)
      team.add_member(direct_member)
      team.add_repository(repo, :pull)

      assert repo.pushable_by?(direct_member)

      @org.convert_to_outside_collaborator!(direct_member)

      assert repo.pushable_by?(direct_member)
    end

    test "replicates the higher team permission when there are multiple team permissions and the higher one was added first" do
      direct_member = create(:user, login: "direct-member")
      @org.add_member(direct_member)

      repo = create(:private_repository, owner: @org)

      higher_team = create(:team, organization: @org, name: "higher-team")
      higher_team.add_member(direct_member)
      higher_team.add_repository(repo, :admin)

      lower_team = create(:team, organization: @org, name: "lower-team")
      lower_team.add_member(direct_member)
      lower_team.add_repository(repo, :push)

      assert repo.adminable_by?(direct_member)

      @org.convert_to_outside_collaborator!(direct_member)

      assert repo.adminable_by?(direct_member)
    end

    test "replicates the higher team permission when there are multiple team permissions and the higher one was added last" do
      direct_member = create(:user, login: "direct-member")
      @org.add_member(direct_member)

      repo = create(:private_repository, owner: @org)

      lower_team = create(:team, organization: @org, name: "lower-team")
      lower_team.add_member(direct_member)
      lower_team.add_repository(repo, :push)

      higher_team = create(:team, organization: @org, name: "higher-team")
      higher_team.add_member(direct_member)
      higher_team.add_repository(repo, :admin)

      assert repo.adminable_by?(direct_member)

      @org.convert_to_outside_collaborator!(direct_member)

      assert repo.adminable_by?(direct_member)
    end

    test "works for an org member" do
      direct_member = create(:user, login: "direct-member")
      @org.add_member(direct_member)

      team = create(:team, organization: @org)
      team.add_member(direct_member)

      pull_repo = create(:private_repository, :minimal, owner: @org, name: "pull-repo")
      team.add_repository(pull_repo, :pull)

      assert @org.direct_or_team_member?(direct_member)
      assert pull_repo.pullable_by?(direct_member)


      perform_enqueued_jobs(only: [RevokeOrgMembershipAbilitiesJob, RemoveOrgMemberJob]) do
        @org.convert_to_outside_collaborator!(direct_member)
      end

      refute @org.direct_or_team_member?(direct_member)
      assert pull_repo.pullable_by?(direct_member)
    end

    test "works for an org member who isn't on any teams" do
      direct_member = create(:user, login: "direct-member")
      @org.add_member(direct_member)

      pull_repo = create(:private_repository, :minimal, owner: @org, name: "pull-repo")
      pull_repo.add_member(direct_member, action: :read)

      assert @org.direct_or_team_member?(direct_member)
      assert pull_repo.pullable_by?(direct_member)

      perform_enqueued_jobs(only: [RevokeOrgMembershipAbilitiesJob, RemoveOrgMemberJob]) do
        @org.convert_to_outside_collaborator!(direct_member)
      end

      refute @org.direct_or_team_member?(direct_member)
      assert pull_repo.pullable_by?(direct_member)
    end

    test "errors for an unaffiliated user" do
      unaffiliated = create(:user, login: "unaffiliated")

      assert_raises Organization::CannotConvertNonMemberToCollaboratorError do
        @org.convert_to_outside_collaborator!(unaffiliated)
      end
    end

    test "errors for a member without 2FA, if 2FA required" do
      member = create(:user, login: "member")
      @org.add_member(member)
      @org.enable_two_factor_required(actor: @owner)

      assert_raises Organization::CannotConvertMemberToCollaboratorWithout2faError do
        @org.convert_to_outside_collaborator!(member)
      end
    end

    test "saves restorable record of user's memberships" do
      direct_member = create(:user, login: "direct-member")
      @org.add_member(direct_member)

      team = create(:team, organization: @org)
      team.add_member(direct_member)

      pull_repo = create(:private_repository, :minimal, owner: @org, name: "pull-repo")
      team.add_repository(pull_repo, :pull)

      memberships = @org.user_direct_abilities_for_organization_teams_and_repositories(direct_member)

      assert_difference("Restorable::OrganizationUser.count", 1) do
        @org.convert_to_outside_collaborator!(direct_member)
      end

      assert_restorable_memberships_are_saved(memberships, direct_member)
    end

    test "does not create a restorable record when save_settings is false" do
      direct_member = create(:user, login: "direct-member")
      @org.add_member(direct_member)

      team = create(:team, organization: @org)
      team.add_member(direct_member)

      pull_repo = create(:private_repository, :minimal, owner: @org, name: "pull-repo")
      team.add_repository(pull_repo, :pull)

      assert_difference("Restorable::OrganizationUser.count", 0) do
        @org.convert_to_outside_collaborator!(direct_member, save_settings: false)
      end
    end

    test "works for a member of a nested team with inherited repo permissions" do
      member = create(:user)

      parent_team = create(:team, organization: @org, privacy: :closed)
      child_team = create(:team, organization: @org, privacy: :closed, parent_team_id: parent_team.id)
      child_team.add_member(member)
      pull_repo = create(:private_repository, :minimal, owner: @org, name: "pull-repo")
      parent_team.add_repository(pull_repo, :pull)

      non_parent_team = create(:team, organization: @org, privacy: :closed) # non-parent team
      non_pull_repo = create(:private_repository, :minimal, owner: @org, name: "non-pull-repo")
      non_parent_team.add_repository(non_pull_repo, :pull)

      assert pull_repo.pullable_by?(member)

      perform_enqueued_jobs(only: [RevokeOrgMembershipAbilitiesJob, RemoveOrgMemberJob]) do
        @org.convert_to_outside_collaborator!(member)
      end

      refute @org.direct_or_team_member?(member)
      refute non_pull_repo.pullable_by?(member)
      assert pull_repo.pullable_by?(member), "repo should be pullable by user"
    end

    unless GitHub.single_business_environment?
      test "updates license usage for business" do
        member = create(:user)
        @org.add_member(member)
        business = create(:business, organizations: [@org])
        # Will be updated once after the member removal and then again at the end of the job
        assert_enqueued_with job: BusinessUpdateLicenseUsageJob do
          @org.convert_to_outside_collaborator!(member)
        end
      end
    end

    test "works for members of an EMU enterprise", skip_enterprise: true do
      enterprise = create(:business, :enterprise_managed)
      owner = create(:emu, business: enterprise)
      enterprise.add_owner(owner, actor: nil)
      managed_user = create(:emu, business: enterprise)
      org = create :organization, business: enterprise, admin: owner
      org.add_member(managed_user)

      team = create(:team, organization: org)
      team.add_member(managed_user)

      pull_repo = create(:private_repository, :minimal, owner: org, name: "pull-repo")
      team.add_repository(pull_repo, :pull)

      push_repo = create(:private_repository, owner: org, name: "push-repo", from_example: :simple)
      team.add_repository(push_repo, :push)

      admin_repo = create(:private_repository, :minimal, owner: org, name: "admin-repo")
      team.add_repository(admin_repo, :admin)

      collab_repo = create(:private_repository, :minimal, owner: org, name: "collab-repo")
      collab_repo.add_member(managed_user)

      assert org.direct_or_team_member?(managed_user)
      assert pull_repo.pullable_by?(managed_user)
      assert push_repo.pushable_by?(managed_user)
      assert admin_repo.adminable_by?(managed_user)
      assert collab_repo.pushable_by?(managed_user)

      perform_enqueued_jobs(only: [RevokeOrgMembershipAbilitiesJob, RemoveOrgMemberJob]) do
        org.convert_to_outside_collaborator!(managed_user)
      end

      refute org.direct_or_team_member?(managed_user)
      assert pull_repo.pullable_by?(managed_user)
      assert push_repo.pushable_by?(managed_user)
      assert admin_repo.adminable_by?(managed_user)
      assert collab_repo.pushable_by?(managed_user)
    end

    test "retains access to the organization's memex projects", skip_enterprise: true do
      org_member = create_direct_member_of(@org)
      memex_project = create(:memex_project, :with_reader, reader: org_member, owner: @org)
      repo = create(:repository, owner: @org)
      repo.add_member(org_member)

      perform_enqueued_jobs(only: [RemoveOrgMemberJob, RemoveOrgMemberProjectsNextAccessJob]) do
        @org.convert_to_outside_collaborator!(org_member)
      end

      granted_actors = UserRole.where(target_type: "MemexProject", target_id: memex_project.id, role: Role.project_reader_role).map(&:actor)
      assert_includes granted_actors, org_member
    end

    test "loses access to the organization's memex projects, when user doesn't have any repo direct access", skip_enterprise: true do
      org_member = create_direct_member_of(@org)
      memex_project = create(:memex_project, :with_reader, reader: org_member, owner: @org)

      perform_enqueued_jobs(only: [RemoveOrgMemberJob, RemoveOrgMemberProjectsNextAccessJob]) do
        @org.convert_to_outside_collaborator!(org_member)
      end

      granted_actors = UserRole.where(target_type: "MemexProject", target_id: memex_project.id, role: Role.project_reader_role).map(&:actor)
      refute_includes granted_actors, org_member
    end

    test "revokes programmatic access grants for a member when converting to outside collaborator" do
      admin = create(:user)
      @org.add_member(admin, action: :admin)
      pat = make_user_programmatic_access_with_grant(requester: admin, target: @org)

      @org.add_member(admin)
      assert_performed_with(
        job: RevokeOrgMemberProgrammaticAccessGrantsJob,
        args: [@org, admin],
        queue: "programmatic_access_grants",
      ) do
        @org.convert_to_outside_collaborator!(admin)
      end

      assert_predicate pat.organization_programmatic_access_grants, :empty?
    end

    test "revokes organization roles" do
      # OrganizationRoles are only allowed on Business plus orgs
      org = create(:business_plus_organization)
      custom_org_role = custom_org_role = OrganizationRole.create!(name: "custom_org_role", owner: org, owner_type: "Organization")

      user = create(:user)
      org.add_member(user)

      result = Permissions::Granters::RoleGranter.new(actor: user, target: org, role: custom_org_role).grant!
      assert_equal true, result.success?
      user_role = UserRole.find_by(role_id: custom_org_role.id, actor_id: user.id)
      refute_nil user_role

      perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
        org.convert_to_outside_collaborator!(user)
      end

      assert_nil UserRole.find_by(role_id: custom_org_role.id, actor_id: user.id)
    end
  end

  context "people" do
    context "with direct org membership" do
      test "returns all org and team members" do
        create_comprehensive_org_users

        assert_same_elements [@concealed_direct_member, @concealed_team_member, @owner, @public_direct_member, @public_team_member], @org.people
      end
    end
  end

  context "Organization.conceal_members" do
    test "conceals members in the organizations" do
      all = create(:organization)
      red = create(:organization)
      green = create(:organization)
      control = create(:organization)

      a = create_direct_member_of(all, visibility: :public)
      r = create_direct_member_of(red, visibility: :public)
      g = create_direct_member_of(green, visibility: :public)
      add_members_to_org(all, [r, g], visibility: :public)
      add_members_to_org(control, [a, r, g], visibility: :public)

      assert all.public_member?(a)
      assert all.public_member?(r)
      assert all.public_member?(g)
      assert red.public_member?(r)
      assert green.public_member?(g)
      assert control.public_member?(a)
      assert control.public_member?(r)
      assert control.public_member?(g)

      Organization.conceal_members(user_ids: [a, r].map(&:id), org_ids: [all, red].map(&:id))

      refute all.public_member?(a)
      refute all.public_member?(r)
      assert all.public_member?(g)
      refute red.public_member?(r)
      assert green.public_member?(g)
      assert control.public_member?(a)
      assert control.public_member?(r)
      assert control.public_member?(g)
    end

    test "eventually conceals even when batched" do
      Organization.stub_const(:CONCEAL_MEMBER_BATCH_SIZE_USERS, 2) do
        Organization.stub_const(:CONCEAL_MEMBER_BATCH_SIZE_ORGS, 2) do
          users = create_list(:user, 3)
          orgs = create_list(:organization, 3) do |org|
            add_members_to_org(org, users, visibility: :public)
            users.each { |user| assert org.public_member?(user) }
          end

          Organization.conceal_members(user_ids: users.map(&:id), org_ids: orgs.map(&:id))

          orgs.each do |org|
            users.each { |user| refute org.public_member?(user) }
          end
        end
      end
    end
  end

  context "direct_or_team_member?" do
    test "is true for org members" do
      user = create_direct_member_of(@org)
      assert @org.direct_or_team_member?(user)
    end

    test "is true for owners" do
      user = @org.admins.first
      assert @org.direct_or_team_member?(user)
    end

    test "is false for randos" do
      user = create(:user)
      refute @org.direct_or_team_member?(user)
    end

    test "is false for another organization" do
      refute @org.direct_or_team_member?(create(:organization))
    end

    test "is false for a nil user" do
      refute @org.direct_or_team_member?(nil)
    end
  end

  context "role_of" do
    test "is :admin for an org owner" do
      admin = @org.admins.first
      assert_predicate @org.role_of(admin), :admin?
    end

    test "is :direct_member for a non-owner org member" do
      direct_member = create(:user, login: "direct-member")
      @org.add_member(direct_member)

      assert_predicate @org.role_of(direct_member), :direct_member?
    end

    test "is :unaffiliated for an unaffiliated user" do
      assert_equal :unaffiliated, @org.role_of(create(:user, login: "unaffiliated")).type
    end

    test "is nil when nil is passed" do
      assert_nil @org.role_of(nil).type
    end
  end

  context "user_direct_abilities_for_organization_teams_and_repositories" do
    test "returns direct memberships in the organization" do
      user = create(:user)
      org = create(:organization, admin: user)
      team = create(:team, organization: org)
      team.add_member(user)

      direct_member_abilities = org.user_direct_abilities_for_organization_teams_and_repositories(user)
      assert_equal 2, direct_member_abilities.size
      org_member_ability = direct_member_abilities.find { |ability| ability.subject_type == "Organization" }
      assert org_member_ability.admin?
      team_member_ability = direct_member_abilities.find { |ability| ability.subject_type == "Team" }
      assert team_member_ability.read?
    end

    test "does not return indirect abilities" do
      user = create(:user)
      org = create(:organization, admin: user)
      repo = create(:repository, owner: org)

      direct_member_abilities = org.user_direct_abilities_for_organization_teams_and_repositories(user)
      assert_equal 1, direct_member_abilities.size
      assert_equal "direct", direct_member_abilities.first.priority
    end
  end

  context "user_all_repo_role_access" do
    test "returns all repo role access for a user enterprise_teams_org_roles_supported enabled" do
      business = create(:business)
      enable_feature_flag(:enterprise_teams_crud, business)
      enable_feature_flag(:enterprise_teams_org_assignment, business)
      enable_feature_flag(:enterprise_teams_org_roles, business)
      all_repo_write_role = OrganizationRole.all_repo_write_role
      all_repo_read_role = OrganizationRole.all_repo_read_role
      org = create(:organization, business: business)
      member = create(:user, login: "org-member1")
      org.add_member(member)

      team1 = create(:team, organization: org)
      team2 = create(:team, organization: org)
      biz_team = create(:business_team, business: business, organization_selection_type: :all)
      team1.add_member(member)
      team2.add_member(member)
      biz_team.add_member(member, caller_type: :business_team)
      org.grant_org_role(assignee: team1, role: all_repo_write_role)
      org.grant_org_role(assignee: team2, role: all_repo_read_role)
      org.grant_org_role(assignee: biz_team, role: all_repo_write_role)

      all_repo_access = org.user_all_repo_role_access(member)

      expected_payload = {
        "Team" => [team1.id, team2.id],
        "BusinessTeam" => [biz_team.id],
      }
      expected_count = 2
      assert_equal expected_count, all_repo_access.size
      assert_same_elements expected_payload["Team"], all_repo_access["Team"]
      assert_same_elements expected_payload["BusinessTeam"], all_repo_access["BusinessTeam"]
    end

    test "returns all repo role access for a user enterprise_teams_org_roles_supported disabled" do
      business = create(:business)
      enable_feature_flag(:enterprise_teams_crud, business)
      business.stubs(:enterprise_teams_org_roles_supported?).returns(false) # disables all erp enterprise_teams_org_roles FFs
      all_repo_write_role = OrganizationRole.all_repo_write_role
      all_repo_read_role = OrganizationRole.all_repo_read_role
      org = create(:organization, business: business)
      member = create(:user, login: "org-member1")
      org.add_member(member)

      team1 = create(:team, organization: org)
      team2 = create(:team, organization: org)
      biz_team = create(:business_team, business: business, organization_selection_type: :all)
      team1.add_member(member)
      team2.add_member(member)
      biz_team.add_member(member)
      org.grant_org_role(assignee: team1, role: all_repo_write_role)
      org.grant_org_role(assignee: team2, role: all_repo_read_role)
      org.grant_org_role(assignee: biz_team, role: all_repo_write_role)

      all_repo_access = org.user_all_repo_role_access(member)

      expected_payload = {
        "Team" => [team1.id, team2.id],
      }
      expected_count = 1
      assert_equal expected_count, all_repo_access.size
      assert_same_elements expected_payload["Team"], all_repo_access["Team"]
    end

    test "returns no all repo role access for a user" do
      all_repo_write_role = OrganizationRole.all_repo_write_role
      all_repo_read_role = OrganizationRole.all_repo_read_role
      org_admin = create(:user, login: "org-admin1")
      member = create(:user, login: "org-member1")
      @org.add_member(member)

      team1 = create(:team, organization: @org)
      team2 = create(:team, organization: @org)
      team1.add_member(member)
      team2.add_member(member)
      @org.grant_org_role(assignee: team1, role: all_repo_write_role)
      @org.grant_org_role(assignee: team2, role: all_repo_read_role)

      all_repo_access = @org.user_all_repo_role_access(org_admin)

      assert_equal 0, all_repo_access.size
    end
  end

  context "highest_all_repo_access_by_actor_type" do
    test "returns highest all repo access by actor type" do
      user = create(:user)
      org = create(:organization, admin: user)
      team = create(:team, organization: org)
      team2 = create(:team, organization: org)

      assert_predicate org.grant_org_role(assignee: user, role: OrganizationRole.all_repo_read_role), :success?
      assert_predicate org.grant_org_role(assignee: user, role: OrganizationRole.all_repo_admin_role), :success?

      assert_predicate org.grant_org_role(assignee: team, role: OrganizationRole.all_repo_read_role), :success?
      assert_predicate org.grant_org_role(assignee: team, role: OrganizationRole.all_repo_write_role), :success?

      assert_predicate org.grant_org_role(assignee: team2, role: OrganizationRole.all_repo_admin_role), :success?

      organization_access = org.highest_all_repo_access_by_actor_type

      organization_access["User"].sort_by! { |entry| entry[:user][:id] }
      organization_access["Team"].sort_by! { |entry| entry[:team][:id] }

      # One for the Users and one for the Team actors.
      assert_equal 2, organization_access.size

      assert_equal 1, organization_access["User"].size
      assert_equal user.id, organization_access["User"][0][:user].id
      assert_same_elements \
        [OrganizationRole.all_repo_read_role.id, OrganizationRole.all_repo_admin_role.id],
        organization_access["User"][0][:role_ids]
      assert_equal :admin, organization_access["User"][0][:access_level]

      assert_equal 2, organization_access["Team"].size
      assert_equal team.id, organization_access["Team"][0][:team].id
      assert_equal :write, organization_access["Team"][0][:access_level]
      assert_same_elements \
        [OrganizationRole.all_repo_read_role.id, OrganizationRole.all_repo_write_role.id],
        organization_access["Team"][0][:role_ids]

      assert_equal team2.id, organization_access["Team"][1][:team].id
      assert_equal :admin, organization_access["Team"][1][:access_level]
      assert_same_elements \
        [OrganizationRole.all_repo_admin_role.id],
        organization_access["Team"][1][:role_ids]
    end

    test "returns highest all repo access by actor type when enterprise_teams_crud ff is on" do
      business = create(:business)
      enable_feature_flag(:enterprise_teams_crud, business)
      enable_feature_flag(:enterprise_teams_org_assignment, business)
      enable_feature_flag(:enterprise_teams_org_roles, business)
      user = create(:user)
      org = create(:organization, admin: user, business: business)
      team = create(:team, organization: org)
      business_team = create(:business_team, business: business, organization_selection_type: :all)

      assert_predicate org.grant_org_role(assignee: user, role: OrganizationRole.all_repo_read_role), :success?
      assert_predicate org.grant_org_role(assignee: user, role: OrganizationRole.all_repo_admin_role), :success?

      assert_predicate org.grant_org_role(assignee: team, role: OrganizationRole.all_repo_read_role), :success?
      assert_predicate org.grant_org_role(assignee: team, role: OrganizationRole.all_repo_write_role), :success?

      assert_predicate org.grant_org_role(assignee: business_team, role: OrganizationRole.all_repo_admin_role), :success?

      organization_access = org.highest_all_repo_access_by_actor_type

      organization_access["User"].sort_by! { |entry| entry[:user][:id] }
      organization_access["Team"].sort_by! { |entry| entry[:team][:id] }

      # One for the Users and one for the Team actors.
      assert_equal 2, organization_access.size

      assert_equal 1, organization_access["User"].size
      assert_equal user.id, organization_access["User"][0][:user].id
      assert_same_elements \
        [OrganizationRole.all_repo_read_role.id, OrganizationRole.all_repo_admin_role.id],
        organization_access["User"][0][:role_ids]
      assert_equal :admin, organization_access["User"][0][:access_level]

      assert_equal 2, organization_access["Team"].size
      assert_equal team.id, organization_access["Team"][0][:team].id
      assert_equal :write, organization_access["Team"][0][:access_level]
      assert_same_elements \
        [OrganizationRole.all_repo_read_role.id, OrganizationRole.all_repo_write_role.id],
        organization_access["Team"][0][:role_ids]

      assert_equal business_team.id, organization_access["Team"][1][:team].id
      assert_equal :admin, organization_access["Team"][1][:access_level]
      assert_same_elements \
        [OrganizationRole.all_repo_admin_role.id],
        organization_access["Team"][1][:role_ids]
    end
  end

  context "member_ids" do
    test "returns all expected member_ids with slice limiting" do
      private_repo = create(:repository, owner: @org)
      private_team = create(:team, organization: @org)
      private_team.add_repository(private_repo, :push)

      @org.update_default_repository_permission(:read, actor: @owner)

      user1 = create(:user)
      @org.add_member(user1)
      private_team.add_member(user1)

      user2 = create(:user)
      @org.add_member(user2)
      private_team.add_member(user2)

      user3 = create(:user)
      @org.add_member(user3)
      private_team.add_member(user3)

      members = @org.member_ids
      members_with_slice = @org.member_ids(actor_ids: [user1.id, user2.id, user3.id], slice: 2)

      members_with_slice.each do |slice_member|
        assert_includes members, slice_member
      end

      assert_same_elements [user1.id, user2.id, user3.id], members_with_slice
    end

    test "includes indirect abilities", skip_if_feature_disabled: :enterprise_teams_org_authorization do
      disable_feature_flag(:enterprise_teams_enabled_for_organizations)
      enable_feature_flag(:enterprise_teams_org_assignment)
      enable_feature_flag(:enterprise_teams_crud)

      business = create(:business)
      business.add_organization(@org)

      private_team = create(:team, organization: @org)

      # membership through all org BusinessTeam
      user1 = create(:user)
      create(:business_user_account, user: user1, business: business)
      business_team_all_orgs = create(:business_team, business: business, organization_selection_type: :all)
      business_team_all_orgs.add_member(user1, caller_type: :business_team)

      # membership through specific org BusinessTeam
      user2 = create(:user)
      create(:business_user_account, user: user2, business: business)
      business_team_select_orgs = create(:business_team, business: business, organization_selection_type: :selected)
      business_team_select_orgs.add_member(user2, caller_type: :business_team)
      business_team_biz_org_assignment = BusinessTeamOrgAssignment.create!(business_team: business_team_select_orgs, organization: @org)

      # membership through all typical org team
      user3 = create(:user)
      @org.add_member(user3)
      private_team.add_member(user3)

      # No membership for other businesses BusinessTeam
      user4 = create(:user)
      different_org = create(:organization)
      different_business = create(:business)
      different_business.add_organization(different_org)
      create(:business_user_account, user: user4, business: different_business)
      business_team_select_orgs_different_business = create(:business_team, business: different_business, organization_selection_type: :all)
      business_team_select_orgs_different_business.add_member(user4, caller_type: :business_team)

      members = @org.member_ids(include_indirect_abilities: true)
      members_with_slice = @org.member_ids(actor_ids: [user1.id, user2.id, user3.id], slice: 2, include_indirect_abilities: true)

      members_with_slice.each do |slice_member|
        assert_includes members, slice_member
      end

      assert_same_elements [user1.id, user2.id, user3.id], members_with_slice
    end

    test "excludes indirect abilities when action is requested", skip_if_feature_disabled: :enterprise_teams_org_authorization do
      disable_feature_flag(:enterprise_teams_enabled_for_organizations)
      enable_feature_flag(:enterprise_teams_org_assignment)
      enable_feature_flag(:enterprise_teams_crud)

      business = create(:business)
      business.add_organization(@org)

      private_team = create(:team, organization: @org)

      # membership through BusinessTeam
      user1 = create(:user)
      create(:business_user_account, user: user1, business: business)
      business_team_all_orgs = create(:business_team, business: business, organization_selection_type: :all)
      business_team_all_orgs.add_member(user1, caller_type: :business_team)

      # membership through all typical org team
      user2 = create(:user)
      @org.add_member(user2)
      private_team.add_member(user2)

      assert_same_elements [@owner.id], @org.member_ids(action: :admin, include_indirect_abilities: true)
    end

    test "excludes indirect abilities when requested", skip_if_feature_disabled: :enterprise_teams_org_authorization do
      disable_feature_flag(:enterprise_teams_enabled_for_organizations)
      enable_feature_flag(:enterprise_teams_org_assignment)
      enable_feature_flag(:enterprise_teams_crud)

      business = create(:business)
      business.add_organization(@org)

      private_team = create(:team, organization: @org)

      # membership through BusinessTeam
      user1 = create(:user)
      create(:business_user_account, user: user1, business: business)
      business_team_all_orgs = create(:business_team, business: business, organization_selection_type: :all)
      business_team_all_orgs.add_member(user1, caller_type: :business_team)

      # membership through all typical org team
      user2 = create(:user)
      @org.add_member(user2)
      private_team.add_member(user2)
      assert_same_elements [@owner.id, user1.id, user2.id], @org.member_ids(include_indirect_abilities: true)
      assert_same_elements [@owner.id, user2.id], @org.member_ids(include_indirect_abilities: false)
    end
  end

  context "members_count" do
    test "returns all expected members_count" do
      private_team = create(:team, organization: @org)

      user1 = create(:user)
      @org.add_member(user1)
      private_team.add_member(user1)

      assert_equal [user1, @owner].size, @org.members_count
      assert_same_elements [user1.id, @owner.id], @org.member_ids
    end

    test "includes indirect abilities", skip_if_feature_disabled: :enterprise_teams_org_authorization do
      disable_feature_flag(:enterprise_teams_enabled_for_organizations)
      enable_feature_flag(:enterprise_teams_org_assignment)
      enable_feature_flag(:enterprise_teams_crud)

      business = create(:business)
      business.add_organization(@org)

      private_team = create(:team, organization: @org)

      # membership through all org BusinessTeam
      user1 = create(:user)
      create(:business_user_account, user: user1, business: business)
      business_team_all_orgs = create(:business_team, business: business, organization_selection_type: :all)
      business_team_all_orgs.add_member(user1, caller_type: :business_team)

      assert_equal [user1, @owner].size, @org.members_count(include_indirect_abilities: true)
      assert_same_elements [user1.id, @owner.id], @org.member_ids(include_indirect_abilities: true)
    end

    test "excludes indirect abilities when feature is disabled", skip_if_feature_enabled: :enterprise_teams_org_authorization do
      business = create(:business)
      business.add_organization(@org)

      private_repo = create(:repository, owner: @org)
      private_team = create(:team, organization: @org)

      # membership through BusinessTeam
      user1 = create(:user)
      create(:business_user_account, user: user1, business: business)
      business_team_all_orgs = create(:business_team, business: business, organization_selection_type: :all)
      business_team_all_orgs.add_member(user1, caller_type: :business_team)

      assert_equal [@owner].size, @org.members_count(include_indirect_abilities: true)
      assert_same_elements [@owner.id], @org.member_ids(include_indirect_abilities: true)
      assert_same_elements [@owner.id], @org.member_ids(include_indirect_abilities: false)
    end
  end

  context "#member?" do
    test "returns true for org members" do
      user = create(:user)
      @org.add_member(user)
      assert @org.member?(user), "expected user to be a member"
    end

    test "returns false for non-org members" do
      user = create(:user)
      refute @org.member?(user), "expected user to not be a member"
    end

    test "returns false for indirect members if FF disabled", skip_if_feature_enabled: :enterprise_teams_org_authorization do
      user = create(:user)
      business = create(:business)
      business.add_organization(@org)
      create(:business_user_account, user: user, business: business)
      business_team_all_orgs = create(:business_team, business: business, organization_selection_type: :all)
      business_team_all_orgs.add_member(user, caller_type: :business_team)

      refute @org.member?(user, include_indirect_abilities: true), "expected user to not be a member"
    end

    test "returns true for indirect members if include_indirect_abilities: true", skip_if_feature_disabled: :enterprise_teams_org_authorization do
      disable_feature_flag(:enterprise_teams_enabled_for_organizations)
      enable_feature_flag(:enterprise_teams_org_assignment)
      enable_feature_flag(:enterprise_teams_crud)

      user = create(:user)
      business = create(:business)
      business.add_organization(@org)
      create(:business_user_account, user: user, business: business)
      business_team_all_orgs = create(:business_team, business: business, organization_selection_type: :all)
      business_team_all_orgs.add_member(user, caller_type: :business_team)

      assert @org.member?(user, include_indirect_abilities: true), "expected user to be a member"
    end

    test "returns false for indirect members if include_indirect_abilities: false", skip_if_feature_disabled: :enterprise_teams_org_authorization do
      disable_feature_flag(:enterprise_teams_enabled_for_organizations)
      enable_feature_flag(:enterprise_teams_org_assignment)
      enable_feature_flag(:enterprise_teams_crud)

      user = create(:user)
      business = create(:business)
      business.add_organization(@org)
      create(:business_user_account, user: user, business: business)
      business_team_all_orgs = create(:business_team, business: business, organization_selection_type: :all)
      business_team_all_orgs.add_member(user, caller_type: :business_team)

      refute @org.member?(user, include_indirect_abilities: false), "expected user to not be a member"
    end
  end

  context "#restore_membership" do
    test "does not enqueue job to restore membership when restorable org user is nil" do
      assert_no_enqueued_jobs only: RestoreOrganizationUserJob do
        @org.restore_membership(nil, actor: @owner)
      end
    end

    test "does not enqueue job to restore membership when restorable org user is Restorable::NullOrganizationUser" do
      assert_no_enqueued_jobs only: RestoreOrganizationUserJob do
        @org.restore_membership(Restorable::NullOrganizationUser.new, actor: @owner)
      end
    end

    test "enqueues job to restore membership when restorable org user is valid" do
      restorable_organization_user = create :restorable_organization_user, :complete
      org = restorable_organization_user.organization
      user = restorable_organization_user.user
      restorable = restorable_organization_user.restorable
      restorable.memberships.create(
        subject_type: "Organization",
        subject_id: org.id,
        action: :read,
      )

      assert_enqueued_with args: [
        {
          restorable_organization_user_id: restorable_organization_user.id,
          actor_id: org.admins.first.id,
        }
      ], job: RestoreOrganizationUserJob do
        org.restore_membership(restorable_organization_user, actor: org.admins.first)
      end
    end
  end
end

class VisibleUsersForTest < GitHub::TestCase
  fixtures do
    GitHub.stubs(:bypass_org_invites_enabled?).returns(false)

    @public_org_admin = create(:user, login: "public-org-admin")
    @org              = create(:organization, login: "org", admin: @public_org_admin)
    @org.publicize_member(@public_org_admin)

    @concealed_org_admin = create(:user, login: "concealed-org-admin")
    @org.add_admin(@concealed_org_admin)

    @public_direct_member = create(:user, login: "public-direct-member")
    @org.add_member(@public_direct_member)
    @org.publicize_member(@public_direct_member)

    @concealed_direct_member = create(:user, login: "concealed-direct-member")
    @org.add_member(@concealed_direct_member)
  end

  test "returns false when asking for existance of a non-member" do
    non_member = create(:user)
    refute_includes @org.visible_users_for(nil), non_member
    refute @org.visible_users_for(nil).exists?(non_member.id), "#{non_member} user should not exist in visible_users_for scope"
  end

  test "returns public members for a nil user" do
    assert_same_elements [@public_org_admin, @public_direct_member], @org.visible_users_for(nil)
    assert_same_elements [@public_org_admin], @org.visible_users_for(nil, type: :admin)
    assert_same_elements [@public_org_admin, @public_direct_member], @org.visible_users_for(nil, type: :direct_member)
    assert_same_elements [@public_direct_member], @org.visible_users_for(nil, type: :member_without_admin)
  end

  test "returns public members for an unsaved user" do
    unsaved_user = User.new

    assert_same_elements [@public_org_admin, @public_direct_member], @org.visible_users_for(unsaved_user)
    assert_same_elements [@public_org_admin], @org.visible_users_for(unsaved_user, type: :admin)
    assert_same_elements [@public_org_admin, @public_direct_member], @org.visible_users_for(unsaved_user, type: :direct_member)
    assert_same_elements [@public_direct_member], @org.visible_users_for(unsaved_user, type: :member_without_admin)
  end

  test "returns public members for a user with no org association" do
    stranger = create(:user, login: "stranger")

    assert_same_elements [@public_org_admin, @public_direct_member], @org.visible_users_for(stranger)
    assert_same_elements [@public_org_admin], @org.visible_users_for(stranger, type: :admin)
    assert_same_elements [@public_org_admin, @public_direct_member], @org.visible_users_for(stranger, type: :direct_member)
    assert_same_elements [@public_direct_member], @org.visible_users_for(nil, type: :member_without_admin)
  end

  test "returns all members for an org admin" do
    assert_same_elements [@concealed_org_admin, @concealed_direct_member, @public_org_admin, @public_direct_member], @org.visible_users_for(@public_org_admin)
    assert_same_elements [@concealed_org_admin, @public_org_admin], @org.visible_users_for(@public_org_admin, type: :admin)
    assert_same_elements [@concealed_org_admin, @public_org_admin, @concealed_direct_member, @public_direct_member], @org.visible_users_for(@public_org_admin, type: :direct_member)
    assert_same_elements [@concealed_direct_member, @public_direct_member], @org.visible_users_for(@public_org_admin, type: :member_without_admin)
  end

  test "returns all members for a direct org member" do
    assert_same_elements [@concealed_org_admin, @concealed_direct_member, @public_org_admin, @public_direct_member], @org.visible_users_for(@public_direct_member)
    assert_same_elements [@concealed_org_admin, @public_org_admin], @org.visible_users_for(@public_direct_member, type: :admin)
    assert_same_elements [@concealed_org_admin, @public_org_admin, @concealed_direct_member, @public_direct_member], @org.visible_users_for(@public_direct_member, type: :direct_member)
    assert_same_elements [@concealed_direct_member, @public_direct_member], @org.visible_users_for(@public_direct_member, type: :member_without_admin)
  end

  test "return all members for viewer with read:org scope" do
    user = create :user
    @org.add_member(user)
    pat = create(:personal_token_oauth_access, user: user, scopes: %w[read:org])
    user.scopes = ["read:org"]
    user.oauth_access = pat
    assert_same_elements [@concealed_org_admin, @concealed_direct_member, @public_org_admin, @public_direct_member, user], @org.visible_users_for(user)
  end

  test "return all members for viewer with repo scope" do
    user = create :user
    @org.add_member(user)
    pat = create(:personal_token_oauth_access, user: user, scopes: %w[repo])
    user.scopes = ["repo"]
    user.oauth_access = pat
    assert_same_elements [@concealed_org_admin, @concealed_direct_member, @public_org_admin, @public_direct_member, user], @org.visible_users_for(user)
  end

  test "returns public members for viewer without scope" do
    user = create :user
    @org.add_member(user)
    pat = create(:personal_token_oauth_access, user: user, scopes: %w[])
    user.scopes = []
    user.oauth_access = pat
    assert_same_elements [@public_org_admin, @public_direct_member], @org.visible_users_for(user)
  end

  test "returns all members for a Bot whose installation has permission on 'members'" do
    @installation_with_members_read = make_integration_installation(
      target: @org,
      permissions: { "members" => :read })

    assert_same_elements [@concealed_org_admin, @concealed_direct_member, @public_org_admin, @public_direct_member], @org.visible_users_for(@installation_with_members_read.bot)
    assert_same_elements [@concealed_org_admin, @public_org_admin], @org.visible_users_for(@installation_with_members_read.bot, type: :admin)
    assert_same_elements [@concealed_org_admin, @public_org_admin, @concealed_direct_member, @public_direct_member], @org.visible_users_for(@installation_with_members_read.bot, type: :direct_member)
    assert_same_elements [@concealed_direct_member, @public_direct_member], @org.visible_users_for(@installation_with_members_read.bot, type: :member_without_admin)
  end

  if GitHub.oauth_application_policies_enabled?
    test "returns all members for an org admin via an OAuth app" do
      # Same user as `@public_org_admin`, but using OAuth
      org_admin_via_oauth = User.with_oauth_hashed_token(make_oauth(@public_org_admin, %w(admin:org)).hashed_token)

      assert_same_elements [@concealed_org_admin, @concealed_direct_member, @public_org_admin, @public_direct_member], @org.visible_users_for(org_admin_via_oauth)
      assert_same_elements [@concealed_org_admin, @public_org_admin], @org.visible_users_for(org_admin_via_oauth, type: :admin)
      assert_same_elements [@concealed_org_admin, @public_org_admin, @concealed_direct_member, @public_direct_member], @org.visible_users_for(org_admin_via_oauth, type: :direct_member)
      assert_same_elements [@concealed_direct_member, @public_direct_member], @org.visible_users_for(org_admin_via_oauth, type: :member_without_admin)
    end

    test "returns public members for an org admin via an unapproved OAuth app" do
      # Same user as `@public_org_admin`, but using OAuth
      org_admin_via_oauth = User.with_oauth_hashed_token(make_oauth(@public_org_admin, %w(admin:org)).hashed_token)

      # Require approval before accessing via OAuth apps
      @org.enable_oauth_application_restrictions

      assert_same_elements [@public_org_admin, @public_direct_member], @org.visible_users_for(org_admin_via_oauth)
      assert_same_elements [@public_org_admin], @org.visible_users_for(org_admin_via_oauth, type: :admin)
      assert_same_elements [@public_org_admin, @public_direct_member], @org.visible_users_for(org_admin_via_oauth, type: :direct_member)
      assert_same_elements [@public_direct_member], @org.visible_users_for(org_admin_via_oauth, type: :member_without_admin)
    end
  end
end

class VisibleUserIdsForTest < GitHub::TestCase
  fixtures do
    GitHub.stubs(:bypass_org_invites_enabled?).returns(false)

    @public_org_admin = create(:user, login: "public-org-admin")
    @org              = create(:organization, login: "org", admin: @public_org_admin)
    @org.publicize_member(@public_org_admin)

    @concealed_org_admin = create(:user, login: "concealed-org-admin")
    @org.add_admin(@concealed_org_admin)

    @public_direct_member = create(:user, login: "public-direct-member")
    @org.add_member(@public_direct_member)
    @org.publicize_member(@public_direct_member)

    @concealed_direct_member = create(:user, login: "concealed-direct-member")
    @org.add_member(@concealed_direct_member)
  end

  test "returns false when asking for existance of a non-member" do
    non_member = create(:user)
    refute_includes @org.visible_user_ids_for(nil), non_member.id
  end

  test "returns public members for a nil user" do
    assert_same_elements [@public_org_admin.id, @public_direct_member.id], @org.visible_user_ids_for(nil)
    assert_same_elements [@public_org_admin.id], @org.visible_user_ids_for(nil, type: :admin)
    assert_same_elements [@public_org_admin.id, @public_direct_member.id], @org.visible_user_ids_for(nil, type: :direct_member)
    assert_same_elements [@public_direct_member.id], @org.visible_user_ids_for(nil, type: :member_without_admin)
  end

  test "returns public members for an unsaved user" do
    unsaved_user = User.new

    assert_same_elements [@public_org_admin.id, @public_direct_member.id], @org.visible_user_ids_for(unsaved_user)
    assert_same_elements [@public_org_admin.id], @org.visible_user_ids_for(unsaved_user, type: :admin)
    assert_same_elements [@public_org_admin.id, @public_direct_member.id], @org.visible_user_ids_for(unsaved_user, type: :direct_member)
    assert_same_elements [@public_direct_member.id], @org.visible_user_ids_for(unsaved_user, type: :member_without_admin)
  end

  test "returns public members for a user with no org association" do
    stranger = create(:user, login: "stranger")

    assert_same_elements [@public_org_admin.id, @public_direct_member.id], @org.visible_user_ids_for(stranger)
    assert_same_elements [@public_org_admin.id], @org.visible_user_ids_for(stranger, type: :admin)
    assert_same_elements [@public_org_admin.id, @public_direct_member.id], @org.visible_user_ids_for(stranger, type: :direct_member)
    assert_same_elements [@public_direct_member.id], @org.visible_user_ids_for(nil, type: :member_without_admin)
  end

  test "returns all members for an org admin" do
    assert_same_elements [@concealed_org_admin.id, @concealed_direct_member.id, @public_org_admin.id, @public_direct_member.id], @org.visible_user_ids_for(@public_org_admin)
    assert_same_elements [@concealed_org_admin.id, @public_org_admin.id], @org.visible_user_ids_for(@public_org_admin, type: :admin)
    assert_same_elements [@concealed_org_admin.id, @public_org_admin.id, @concealed_direct_member.id, @public_direct_member.id], @org.visible_user_ids_for(@public_org_admin, type: :direct_member)
    assert_same_elements [@concealed_direct_member.id, @public_direct_member.id], @org.visible_user_ids_for(@public_org_admin, type: :member_without_admin)
  end

  test "returns all members for a direct org member" do
    assert_same_elements [@concealed_org_admin.id, @concealed_direct_member.id, @public_org_admin.id, @public_direct_member.id], @org.visible_user_ids_for(@public_direct_member)
    assert_same_elements [@concealed_org_admin.id, @public_org_admin.id], @org.visible_user_ids_for(@public_direct_member, type: :admin)
    assert_same_elements [@concealed_org_admin.id, @public_org_admin.id, @concealed_direct_member.id, @public_direct_member.id], @org.visible_user_ids_for(@public_direct_member, type: :direct_member)
    assert_same_elements [@concealed_direct_member.id, @public_direct_member.id], @org.visible_user_ids_for(@public_direct_member, type: :member_without_admin)
  end

  test "return all members for viewer with read:org scope" do
    user = create :user
    @org.add_member(user)
    pat = create(:personal_token_oauth_access, user: user, scopes: %w[read:org])
    user.scopes = ["read:org"]
    user.oauth_access = pat
    assert_same_elements [@concealed_org_admin.id, @concealed_direct_member.id, @public_org_admin.id, @public_direct_member.id, user.id], @org.visible_user_ids_for(user)
  end

  test "return all members for viewer with repo scope" do
    user = create :user
    @org.add_member(user)
    pat = create(:personal_token_oauth_access, user: user, scopes: %w[repo])
    user.scopes = ["repo"]
    user.oauth_access = pat
    assert_same_elements [@concealed_org_admin.id, @concealed_direct_member.id, @public_org_admin.id, @public_direct_member.id, user.id], @org.visible_user_ids_for(user)
  end

  test "returns public members for viewer without scope" do
    user = create :user
    @org.add_member(user)
    pat = create(:personal_token_oauth_access, user: user, scopes: %w[])
    user.scopes = []
    user.oauth_access = pat
    assert_same_elements [@public_org_admin.id, @public_direct_member.id], @org.visible_user_ids_for(user)
  end

  test "returns all members for a Bot whose installation has permission on 'members'" do
    @installation_with_members_read = make_integration_installation(
      target: @org,
      permissions: { "members" => :read })

    assert_same_elements [@concealed_org_admin.id, @concealed_direct_member.id, @public_org_admin.id, @public_direct_member.id], @org.visible_user_ids_for(@installation_with_members_read.bot)
    assert_same_elements [@concealed_org_admin.id, @public_org_admin.id], @org.visible_user_ids_for(@installation_with_members_read.bot, type: :admin)
    assert_same_elements [@concealed_org_admin.id, @public_org_admin.id, @concealed_direct_member.id, @public_direct_member.id], @org.visible_user_ids_for(@installation_with_members_read.bot, type: :direct_member)
    assert_same_elements [@concealed_direct_member.id, @public_direct_member.id], @org.visible_user_ids_for(@installation_with_members_read.bot, type: :member_without_admin)
  end

  if GitHub.oauth_application_policies_enabled?
    test "returns all members for an org admin via an OAuth app" do
      # Same user as `@public_org_admin`, but using OAuth
      org_admin_via_oauth = User.with_oauth_hashed_token(make_oauth(@public_org_admin, %w(admin:org)).hashed_token)

      assert_same_elements [@concealed_org_admin.id, @concealed_direct_member.id, @public_org_admin.id, @public_direct_member.id], @org.visible_user_ids_for(org_admin_via_oauth)
      assert_same_elements [@concealed_org_admin.id, @public_org_admin.id], @org.visible_user_ids_for(org_admin_via_oauth, type: :admin)
      assert_same_elements [@concealed_org_admin.id, @public_org_admin.id, @concealed_direct_member.id, @public_direct_member.id], @org.visible_user_ids_for(org_admin_via_oauth, type: :direct_member)
      assert_same_elements [@concealed_direct_member.id, @public_direct_member.id], @org.visible_user_ids_for(org_admin_via_oauth, type: :member_without_admin)
    end

    test "returns public members for an org admin via an unapproved OAuth app" do
      # Same user as `@public_org_admin`, but using OAuth
      org_admin_via_oauth = User.with_oauth_hashed_token(make_oauth(@public_org_admin, %w(admin:org)).hashed_token)

      # Require approval before accessing via OAuth apps
      @org.enable_oauth_application_restrictions

      assert_same_elements [@public_org_admin.id, @public_direct_member.id], @org.visible_user_ids_for(org_admin_via_oauth)
      assert_same_elements [@public_org_admin.id], @org.visible_user_ids_for(org_admin_via_oauth, type: :admin)
      assert_same_elements [@public_org_admin.id, @public_direct_member.id], @org.visible_user_ids_for(org_admin_via_oauth, type: :direct_member)
      assert_same_elements [@public_direct_member.id], @org.visible_user_ids_for(org_admin_via_oauth, type: :member_without_admin)
    end

    test "returns guest collaborators for an emu org", skip_enterprise: true do
      guest_collaborator = create(:emu, :guest_collaborator)
      emu_business = guest_collaborator.enterprise_managed_business
      emu_user = create(:emu, business: emu_business)
      emu_org = create :organization, business: emu_business
      emu_org.add_member(guest_collaborator)
      emu_org.add_member(emu_user)

      assert_same_elements [guest_collaborator.id], emu_org.visible_user_ids_for(emu_user, type: :guest_collaborator)
      assert_same_elements [guest_collaborator.id, emu_user.id], emu_org.visible_user_ids_for(emu_user)
    end unless GitHub.single_business_environment?
  end
end

class LegacyAdminMembersTest < GitHub::TestCase
  test "includes org members who are on a legacy admin team" do
    org               = create(:organization)
    legacy_admin_team = create(:team, organization: org, permission: "admin")
    member            = create(:user, login: "org-member")

    org.add_member(member)
    legacy_admin_team.add_member(member)

    assert_same_elements [member], org.legacy_admin_members
  end

  test "excludes org members who aren't on any legacy admin teams" do
    org               = create(:organization)
    legacy_admin_team = create(:team, organization: org, permission: "admin")
    member            = create(:user, login: "org-member")

    org.add_member(member)

    assert_empty org.legacy_admin_members
  end

  test "excludes org owners who are on a legacy admin team" do
    org               = create(:organization)
    legacy_admin_team = create(:team, organization: org, permission: "admin")
    owner             = create(:user, login: "org-owner")

    org.add_admin(owner)

    assert_empty org.legacy_admin_members
  end
end

class RemoveMemberWithUserWithATeamWithAssociatedRepositoriesTest < GitHub::TestCase
  include MembershipTestHelper

  PackagesMock = Struct.new(:packages)
  SubscriptionMock = Struct.new(:list_id, :ignored?)
  setup do
    METADATA_CLIENT.any_instance.stubs(:get_packages_by_repo).returns(PackagesMock.new(packages: []))
  end

  fixtures do
    @org = create(:organization)
    @org.allow_private_repository_forking(actor: @org.admins.first)
    @org.update_default_repository_permission(:none, actor: @org.admins.first)
    @user = create(:user)
    GitHub.newsies.get_and_update_settings(@user) do |settings|
      settings.auto_subscribe = true
    end

    unused_public_repo = create(:repository, owner: @org)
    @repo1 = create(:private_repository, owner: @org)
    @repo2 = create(:private_repository, owner: @org)
    @repo3 = create(:private_repository, owner: @org)
    @repo4 = create(:private_repository, owner: @org)
    @team = create(:team, organization: @org, permission: "pull")
    @team.add_repository @repo1, :pull
    @team.add_repository @repo2, :push
    @team.add_repository @repo3, :admin
    @team.add_repository @repo4, :admin

    @org.add_member(@user)

    perform_enqueued_jobs(only: [Newsies::AutoSubscribeUserToRepositoriesJob]) do
      @team.add_member(@user)
    end

    # Watched Repositories
    @user.watch_repo(@repo1)
    @user.ignore_repo(@repo3)

    # Stars
    @user.star(@repo1)
    @user.star(@repo2)

    # Issue Assignements
    @issue = create(:issue, repository: @repo4, assignee: @user)

    # Forks
    @fork1 = create(:fork_repository, forker: @user, fork_repo: @repo1)

    # Custom Email Routing
    @email = "customemail@org.com"

    METADATA_CLIENT = ::PackageRegistry::Twirp::MetadataClient
  end

  setup do
    self.perform_enqueued_jobs = [
      RemoveOrgMemberJob,
      RevokeOrgMembershipAbilitiesJob,
      RemoveOrgMemberForksJob,
      RemoveOrgMemberWatchedRepositoriesJob,
      RemoveOrgMemberRepositoryStarsJob,
      RemoveOrgMemberIssueAssignmentsJob,
      RemoveOrgMemberVulnerabilityManagementJob,
      RemoveOrgMemberPackageAccessJob,
      BulkRemoveOrgMemberRepositoryStarsJob,
      BulkRemoveOrgMemberWatchedRepositoriesJob,
      BulkRemoveOrgMemberForksJob,
      Newsies::DeleteAllForUserAndListsJob
    ]
  end

  context "saves all restorables" do
    test "creates restorables for memberships" do
      disable_feature_flag(:remove_org_member_repo_stars_job_use_bulk_ci_only) # This feature prevents creation of restorables
      memberships = @org.user_direct_abilities_for_organization_teams_and_repositories(@user)
      assert_difference "Restorable::Membership.count", 2 do
        @org.remove_member(@user)
      end
      assert_restorable_memberships_are_saved(memberships, @user)
      assert_org_user_is_restorable
    end

    test "creates restorables for watched repositories" do
      disable_feature_flag(:remove_org_member_repo_stars_job_use_bulk_ci_only) # This feature prevents creation of restorables
      repo_subscriptions = [@repo1, @repo2, @repo3, @repo4]
      subscriptions = [
        SubscriptionMock.new(list_id: @repo1.id, ignored?: false),
        SubscriptionMock.new(list_id: @repo2.id, ignored?: false),
        SubscriptionMock.new(list_id: @repo3.id, ignored?: true),
        SubscriptionMock.new(list_id: @repo4.id, ignored?: false),
      ]
      assert_difference "Restorable::WatchedRepository.count", 4 do
        @org.remove_member(@user)
      end
      assert_restorable_watched_repositories_are_saved(repo_subscriptions, @user, subscriptions)
      assert_org_user_is_restorable
    end

    test "creates restorables for repositories stars" do
      disable_feature_flag(:remove_org_member_repo_stars_job_use_bulk_ci_only) # This feature prevents creation of restorables
      repo_stars = [@repo1, @repo2]
      assert_difference "Restorable::RepositoryStar.count", 2 do
        @org.remove_member(@user)
      end
      assert_restorable_repository_stars_are_saved(repo_stars, @user)
      assert_org_user_is_restorable
    end

    test "creates restorables for issue assignments" do
      disable_feature_flag(:remove_org_member_repo_stars_job_use_bulk_ci_only) # This feature prevents creation of restorables
      assigned_issues = [@issue]
      assert_difference "Restorable::IssueAssignment.count", 1 do
        @org.remove_member(@user)
      end
      assert_restorable_assigned_issues_are_saved(assigned_issues, @user)
      assert_org_user_is_restorable
    end

    test "creates restorables for member forks" do
      disable_feature_flag(:remove_org_member_repo_stars_job_use_bulk_ci_only) # This feature prevents creation of restorables
      forks = [@fork1]
      assert_difference "Restorable::Repository.count", 1 do
        @org.remove_member(@user)
      end
      assert_equal 1, Restorable::Repository.count
      assert_restorable_repositories_are_saved(forks, @user)
      assert_org_user_is_restorable
    end

    test "creates restorables for custom email routings" do
      disable_feature_flag(:remove_org_member_repo_stars_job_use_bulk_ci_only) # This feature prevents creation of restorables
      @user.add_email(@email).verify!
      GitHub.newsies.get_and_update_settings(@user) do |settings|
        settings.email(@org, @email)
      end

      assert_difference "Restorable::CustomEmailRouting.count", 1 do
        @org.convert_to_outside_collaborator!(@user)
      end
      org_id_and_email_hash = { @org.id => @email }
      assert_restorable_custom_email_routings_are_saved(org_id_and_email_hash, @user)
      assert_org_user_is_restorable
    end

    test "doesn't create restorables for custom email routings if there is no custom email" do
      assert_difference "Restorable::CustomEmailRouting.count", 0 do
        @org.convert_to_outside_collaborator!(@user)
      end
    end
  end

  context "removes all member data" do
    test "removes memberships" do
      assert @org.direct_member?(@user), "expected user to be a member"
      assert @team.member?(@user), "expected user to be a member"
      @org.remove_member(@user)
      refute @org.direct_member?(@user), "expected user to not be a member"
      refute @team.member?(@user), "expected user to not be a member"
    end

    test "removes watched repositories" do
      assert @user.watching_repo?(@repo1), "expected user to be watching repo"
      assert GitHub.newsies.subscription_status(@user, @repo3).is_ignored, "expected user to be ignoring the repo"
      @org.remove_member(@user)
      refute @user.watching_repo?(@repo1), "expected user to not be watching repo"
      refute GitHub.newsies.subscription_status(@user, @repo3).is_ignored, "expected user to not be ignoring the repo"
    end

    test "removes repository stars" do
      assert_includes @user.starred_repositories.to_a, @repo1
      assert_includes @user.starred_repositories.to_a, @repo2
      @org.remove_member(@user)
      refute_includes @user.reload.starred_repositories.to_a, @repo1
      refute_includes @user.starred_repositories.to_a, @repo2
    end

    test "removes issue assignments" do
      assert_includes @issue.assignees, @user
      @org.remove_member(@user)
      refute_includes @issue.assignees, @user
    end

    test "removes member forks" do
      assert @fork1.present?, "expected there to be a user fork"
      @org.remove_member(@user)
      refute Repositories::Public.find_active(@fork1.id), "expected fork to not be pullable by user"
    end

    test "removes custom email routing" do
      @user.add_email(@email).verify!
      GitHub.newsies.get_and_update_settings(@user) do |settings|
        settings.email(@org, @email)
      end

      @org.convert_to_outside_collaborator!(@user)

      settings = GitHub.newsies.settings(@user)
      email_setting = settings.email(@org).address

      refute_equal @email, email_setting
    end
  end
end

class RemoveMemberWithATeamWithNoAssociatedRepositoriesTest < GitHub::TestCase
  include MembershipTestHelper

  PackagesMock = Struct.new(:packages)
  SubscriptionMock = Struct.new(:list_id, :ignored?)
  fixtures do
    @org = create(:organization)
    @org.allow_private_repository_forking(actor: @org.admins.first)
    @user = create(:user)

    unused_public_repo = create(:repository, owner: @org)
    @repo1 = create(:private_repository, owner: @org)
    @repo2 = create(:private_repository, owner: @org)
    @repo3 = create(:private_repository, owner: @org)
    @repo4 = create(:private_repository, owner: @org)
    @team = create(:team, organization: @org, permission: "pull")

    @org.add_member(@user)
    @team.add_member(@user)

    # Watched Repositories
    @user.watch_repo(@repo1)
    @user.ignore_repo(@repo3)

    # Stars
    @user.star(@repo1)
    @user.star(@repo2)

    # Issue Assignements
    @issue = create(:issue, repository: @repo4, assignee: @user)

    # Forks
    @fork1 = create(:fork_repository, forker: @user, fork_repo: @repo1)

    # Custom Email Routing
    @email = "customemail@org.com"
  end

  setup do
    self.perform_enqueued_jobs = [
      RemoveOrgMemberJob,
      RevokeOrgMembershipAbilitiesJob,
      RemoveOrgMemberForksJob,
      RemoveOrgMemberWatchedRepositoriesJob,
      RemoveOrgMemberRepositoryStarsJob,
      RemoveOrgMemberIssueAssignmentsJob,
      RemoveOrgMemberVulnerabilityManagementJob,
      RemoveOrgMemberPackageAccessJob,
      BulkRemoveOrgMemberForksJob,
      BulkRemoveOrgMemberRepositoryStarsJob,
      BulkRemoveOrgMemberWatchedRepositoriesJob,
      Newsies::DeleteAllForUserAndListsJob
    ]
  end

  context "saves all restorables" do
    test "creates restorables for memberships" do
      disable_feature_flag(:remove_org_member_repo_stars_job_use_bulk_ci_only) # This feature prevents creation of restorables
      memberships = @org.user_direct_abilities_for_organization_teams_and_repositories(@user)
      assert_difference "Restorable::Membership.count", 2 do
        @org.remove_member(@user)
      end
      assert_restorable_memberships_are_saved(memberships, @user)
      assert_org_user_is_restorable
    end

    test "creates restorables for watched repositories" do
      disable_feature_flag(:remove_org_member_repo_stars_job_use_bulk_ci_only) # This feature prevents creation of restorables
      repo_subscriptions = [@repo1, @repo3]
      subscriptions = [
        SubscriptionMock.new(list_id: @repo1.id, ignored?: false),
        SubscriptionMock.new(list_id: @repo3.id, ignored?: true),
      ]
      assert_difference "Restorable::WatchedRepository.count", 2 do
        @org.remove_member(@user)
      end
      assert_restorable_watched_repositories_are_saved(repo_subscriptions, @user, subscriptions)
      assert_org_user_is_restorable
    end

    test "creates restorables for repositories stars" do
      disable_feature_flag(:remove_org_member_repo_stars_job_use_bulk_ci_only) # This feature prevents creation of restorables
      repo_stars = [@repo1, @repo2]
      assert_difference "Restorable::RepositoryStar.count", 2 do
        @org.remove_member(@user)
      end
      assert_restorable_repository_stars_are_saved(repo_stars, @user)
      assert_org_user_is_restorable
    end

    test "creates restorables for issue assignments" do
      disable_feature_flag(:remove_org_member_repo_stars_job_use_bulk_ci_only) # This feature prevents creation of restorables
      assigned_issues = [@issue]
      assert_difference "Restorable::IssueAssignment.count", 1 do
        @org.remove_member(@user)
      end
      assert_restorable_assigned_issues_are_saved(assigned_issues, @user)
      assert_org_user_is_restorable
    end

    test "creates restorables for member forks" do
      disable_feature_flag(:remove_org_member_repo_stars_job_use_bulk_ci_only) # This feature prevents creation of restorables
      forks = [@fork1]
      assert_difference "Restorable::Repository.count", 1 do
        @org.remove_member(@user)
      end
      assert_equal 1, Restorable::Repository.count
      assert_restorable_repositories_are_saved(forks, @user)
      assert_org_user_is_restorable
    end

    test "creates restorables for custom email routings" do
      disable_feature_flag(:remove_org_member_repo_stars_job_use_bulk_ci_only) # This feature prevents creation of restorables
      @user.add_email(@email).verify!
      GitHub.newsies.get_and_update_settings(@user) do |settings|
        settings.email(@org, @email)
      end

      assert_difference "Restorable::CustomEmailRouting.count", 1 do
        @org.remove_member(@user)
      end
      org_id_and_email_hash = { @org.id => @email }
      assert_restorable_custom_email_routings_are_saved(org_id_and_email_hash, @user)
      assert_org_user_is_restorable
    end

    test "doesn't create restorables for custom email routings if there is no custom email" do
      assert_difference "Restorable::CustomEmailRouting.count", 0 do
        @org.convert_to_outside_collaborator!(@user)
      end
    end
  end

  context "removes all member data" do
    test "removes memberships" do
      assert @org.direct_member?(@user), "expected user to be a member"
      assert @team.member?(@user), "expected user to be a member"
      @org.remove_member(@user)
      refute @org.direct_member?(@user), "expected user to not be a member"
      refute @team.member?(@user), "expected user to not be a member"
    end

    test "removes watched repositories" do
      assert @user.watching_repo?(@repo1), "expected user to be watching repo"
      assert GitHub.newsies.subscription_status(@user, @repo3).is_ignored, "expected user to be ignoring the repo"
      @org.remove_member(@user)
      refute @user.watching_repo?(@repo1), "expected user to not be watching repo"
      refute GitHub.newsies.subscription_status(@user, @repo3).is_ignored, "expected user to not be ignoring the repo"
    end

    test "removes repository stars" do
      assert_includes @user.starred_repositories.to_a, @repo1
      assert_includes @user.starred_repositories.to_a, @repo2
      @org.remove_member(@user)
      refute_includes @user.reload.starred_repositories.to_a, @repo1
      refute_includes @user.starred_repositories.to_a, @repo2
    end

    test "removes issue assignments" do
      assert_includes @issue.assignees, @user
      @org.remove_member(@user)
      refute_includes @issue.assignees, @user
    end

    test "removes member forks" do
      assert @fork1.present?, "expected there to be a user fork"
      @org.remove_member(@user)
      refute Repositories::Public.find_active(@fork1.id), "expected fork to not be pullable by user"
    end

    test "removes custom email routing" do
      @user.add_email(@email).verify!
      GitHub.newsies.get_and_update_settings(@user) do |settings|
        settings.email(@org, @email)
      end

      @org.remove_member(@user)

      settings = GitHub.newsies.settings(@user)
      email_setting = settings.email(@org).address

      refute_equal @email, email_setting
    end
  end
end

class ConvertToOutsideCollaboratorTest < GitHub::TestCase
  include MembershipTestHelper

  PackagesMock = Struct.new(:packages)
  SubscriptionMock = Struct.new(:list_id, :ignored?)
  setup do
    METADATA_CLIENT.any_instance.stubs(:get_packages_by_repo).returns(PackagesMock.new(packages: []))
    self.perform_enqueued_jobs = [
      RemoveOrgMemberJob,
      RevokeOrgMembershipAbilitiesJob,
      RemoveOrgMemberForksJob,
      RemoveOrgMemberWatchedRepositoriesJob,
      RemoveOrgMemberRepositoryStarsJob,
      RemoveOrgMemberIssueAssignmentsJob,
      RemoveOrgMemberVulnerabilityManagementJob,
      RemoveOrgMemberPackageAccessJob,
      BulkRemoveOrgMemberForksJob,
      BulkRemoveOrgMemberRepositoryStarsJob,
      BulkRemoveOrgMemberWatchedRepositoriesJob,
      Newsies::DeleteAllForUserAndListsJob
    ]
  end

  fixtures do
    @org = create(:organization)
    @org.allow_private_repository_forking(actor: @org.admins.first)
    @user = create(:user)

    unused_public_repo = create(:repository, owner: @org)
    @repo1 = create(:private_repository, owner: @org)
    @repo2 = create(:private_repository, owner: @org)
    @repo3 = create(:private_repository, owner: @org)
    @repo4 = create(:private_repository, owner: @org)
    @team = create(:team, organization: @org, permission: "pull")
    @team.add_repository @repo1, :pull

    @org.add_member(@user)
    @team.add_member(@user)

    # Watched Repositories
    @user.watch_repo(@repo1)
    @user.ignore_repo(@repo3)

    # Stars
    @user.star(@repo1)
    @user.star(@repo2)

    # Issue Assignements
    @issue1 = create(:issue, repository: @repo4, assignee: @user)
    @issue2 = create(:issue, repository: @repo1, assignee: @user)

    # Forks
    @fork1 = create(:fork_repository, forker: @user, fork_repo: @repo2)
    @fork2 = create(:fork_repository, forker: @user, fork_repo: @repo1)

    # Custom Email Routing
    @email = "customemail@org.com"

    METADATA_CLIENT = ::PackageRegistry::Twirp::MetadataClient
  end

  test "marks restorables records as restorable" do
    disable_feature_flag(:remove_org_member_repo_stars_job_use_bulk_ci_only) # This feature prevents creation of restorables
    @org.convert_to_outside_collaborator!(@user)

    restorable = Restorable::OrganizationUser.first
    assert_predicate restorable, :restorable?
  end

  context "saves all restorables for repositories without direct memberships" do
    test "creates restorables for memberships" do
      disable_feature_flag(:remove_org_member_repo_stars_job_use_bulk_ci_only) # This feature prevents creation of restorables
      memberships = @org.user_direct_abilities_for_organization_teams_and_repositories(@user)
      assert_difference "Restorable::Membership.count", 2 do
        @org.convert_to_outside_collaborator!(@user)
      end
      assert_restorable_memberships_are_saved(memberships, @user)
      assert_org_user_is_restorable
    end

    test "creates restorables for watched repositories" do
      disable_feature_flag(:remove_org_member_repo_stars_job_use_bulk_ci_only) # This feature prevents creation of restorables
      repo_subscriptions = [@repo3]
      subscriptions = [
        SubscriptionMock.new(list_id: @repo3.id, ignored?: true),
      ]
      assert_difference "Restorable::WatchedRepository.count", 1 do
        @org.convert_to_outside_collaborator!(@user)
      end

      assert_restorable_watched_repositories_are_saved(repo_subscriptions, @user, subscriptions)
      assert_org_user_is_restorable
    end

    test "creates restorables for repositories stars" do
      disable_feature_flag(:remove_org_member_repo_stars_job_use_bulk_ci_only) # This feature prevents creation of restorables
      repo_stars = [@repo2]
      assert_difference "Restorable::RepositoryStar.count", 1 do
        @org.convert_to_outside_collaborator!(@user)
      end
      assert_restorable_repository_stars_are_saved(repo_stars, @user)
      assert_org_user_is_restorable
    end

    test "creates restorables for issue assignments" do
      disable_feature_flag(:remove_org_member_repo_stars_job_use_bulk_ci_only) # This feature prevents creation of restorables
      assigned_issues = [@issue1]
      assert_difference "Restorable::IssueAssignment.count", 1 do
        @org.convert_to_outside_collaborator!(@user)
      end
      assert_restorable_assigned_issues_are_saved(assigned_issues, @user)
      assert_org_user_is_restorable
    end

    test "creates restorables for member forks" do
      disable_feature_flag(:remove_org_member_repo_stars_job_use_bulk_ci_only) # This feature prevents creation of restorables
      forks = [@fork1]
      assert_difference "Restorable::Repository.count", 1 do
        @org.convert_to_outside_collaborator!(@user)
      end
      assert_equal 1, Restorable::Repository.count
      assert_restorable_repositories_are_saved(forks, @user)
      assert_org_user_is_restorable
    end

    test "creates restorables for custom email routings" do
      disable_feature_flag(:remove_org_member_repo_stars_job_use_bulk_ci_only) # This feature prevents creation of restorables
      @user.add_email(@email).verify!
      GitHub.newsies.get_and_update_settings(@user) do |settings|
        settings.email(@org, @email)
      end

      assert_difference "Restorable::CustomEmailRouting.count", 1 do
        @org.convert_to_outside_collaborator!(@user)
      end
      org_id_and_email_hash = { @org.id => @email }
      assert_restorable_custom_email_routings_are_saved(org_id_and_email_hash, @user)
      assert_org_user_is_restorable
    end

    test "doesn't create restorables for custom email routings if there is no custom email" do
      assert_difference "Restorable::CustomEmailRouting.count", 0 do
        @org.convert_to_outside_collaborator!(@user)
      end
    end
  end

  context "removes all member data for repositories without direct memberships" do
    test "removes memberships" do
      assert @org.direct_member?(@user), "expected user to be a member"
      assert @team.member?(@user), "expected user to be a member"
      @org.convert_to_outside_collaborator!(@user)
      refute @org.direct_member?(@user), "expected user to not be a member"
      refute @team.member?(@user), "expected user to not be a member"
    end

    test "removes watched repositories" do
      assert @user.watching_repo?(@repo1), "expected user to be watching repo"
      assert GitHub.newsies.subscription_status(@user, @repo3).is_ignored, "expected user to be ignoring the repo"
      @org.convert_to_outside_collaborator!(@user)
      assert @user.watching_repo?(@repo1), "expected user to not be watching repo"
      refute GitHub.newsies.subscription_status(@user, @repo3).is_ignored, "expected user to not be ignoring the repo"
    end

    test "removes repository stars" do
      assert_includes @user.starred_repositories.to_a, @repo1
      assert_includes @user.starred_repositories.to_a, @repo2
      @org.convert_to_outside_collaborator!(@user)
      assert_includes @user.reload.starred_repositories.to_a, @repo1
      refute_includes @user.starred_repositories.to_a, @repo2
    end

    test "removes issue assignments" do
      assert_includes @issue1.assignees, @user
      assert_includes @issue2.assignees, @user
      @org.convert_to_outside_collaborator!(@user)
      refute_includes @issue1.assignees, @user
      assert_includes @issue2.assignees, @user
    end

    test "removes member forks" do
      assert @fork1.present?, "expected there to be a user fork"
      assert @fork2.present?, "expected there to be a user fork"
      @org.convert_to_outside_collaborator!(@user)
      refute Repositories::Public.find_active(@fork1.id), "expected fork to not be pullable by user"
      assert Repositories::Public.find_active(@fork2.id), "expected fork to be pullable by user"
    end

    test "removes custom email routing" do
      @user.add_email(@email).verify!
      GitHub.newsies.get_and_update_settings(@user) do |settings|
        settings.email(@org, @email)
      end

      @org.convert_to_outside_collaborator!(@user)

      settings = GitHub.newsies.settings(@user)
      email_setting = settings.email(@org).address

      refute_equal @email, email_setting
    end
  end
end

class OrganizationRemoveOutsideCollaboratorTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @org = create(:organization)
    @org.allow_private_repository_forking(actor: @org.admins.first)
  end

  test "given an organization member, it returns without doing anything" do
    @member = create(:user, login: "member")
    @org.add_member(@member)
    assert_includes @org.members, @member

    Organization.expects(:save_organization_settings_for_user).with(@member).never
    @org.remove_outside_collaborator!(@member)

    assert_includes @org.members, @member
  end

  test "given a non-outside-collaborator who is not a member, it returns without doing anything" do
    billing_manager = create(:user, login: "billing-manager")
    @org.billing.add_manager(billing_manager, actor: @org.admin)
    assert_includes @org.billing_managers, billing_manager

    Organization.expects(:save_organization_settings_for_user).with(billing_manager).never
    @org.remove_outside_collaborator!(billing_manager)

    assert_includes @org.billing_managers, billing_manager
  end

  test "given a collaborator (member), returns without doing anything" do
    @collaborator = create(:user, login: "inside-collaborator")
    @org.add_member(@collaborator)
    repo = create(:repository, owner: @org)
    repo.add_member(@collaborator)
    assert_includes @org.members, @collaborator
    assert_includes repo.members, @collaborator

    Organization.expects(:save_organization_settings_for_user).with(@collaborator).never
    @org.remove_outside_collaborator!(@collaborator)

    assert_includes @org.members, @collaborator
    assert_includes repo.members, @collaborator
  end

  test "given an outside collaborator, removes them from all repos" do
    @outside_collaborator = create(:user, login: "outside-collaborator")
    repo1 = create(:repository, owner: @org, name: "repo1")
    repo1.add_member(@outside_collaborator)
    repo2 = create(:repository, owner: @org, name: "repo2")
    repo2.add_member(@outside_collaborator)

    @org.remove_outside_collaborator!(@outside_collaborator)

    refute @org.user_is_outside_collaborator?(@outside_collaborator.id)
  end

  test "given an outside collaborator, remove them from all memexes (project_reader_role)", skip_enterprise: true do
    @outside_collaborator = create(:user, login: "outside-collaborator")
    repo1 = create(:repository, owner: @org, name: "repo1")
    repo1.add_member(@outside_collaborator)

    memex_project = create(:memex_project, :with_reader, reader: @outside_collaborator, owner: @org)

    only = [RemoveOrgMemberProjectsNextAccessJob]
    perform_enqueued_jobs(only: only) do
      @org.remove_outside_collaborator!(@outside_collaborator)
    end

    granted_actors = UserRole.where(target_type: "MemexProject", target_id: memex_project.id, role: Role.project_reader_role).map(&:actor)
    refute_includes granted_actors, @outside_collaborator
  end

  test "given an outside collaborator, remove them from all memexes (project_writer_role)", skip_enterprise: true do
    @outside_collaborator = create(:user, login: "outside-collaborator")
    repo1 = create(:repository, owner: @org, name: "repo1")
    repo1.add_member(@outside_collaborator)

    memex_project = create(:memex_project, :with_writer, writer: @outside_collaborator, owner: @org)

    only = [RemoveOrgMemberProjectsNextAccessJob]
    perform_enqueued_jobs(only: only) do
      @org.remove_outside_collaborator!(@outside_collaborator)
    end

    granted_actors = UserRole.where(target_type: "MemexProject", target_id: memex_project.id, role: Role.project_writer_role).map(&:actor)
    refute_includes granted_actors, @outside_collaborator
  end

  test "given an outside collaborator, remove them from all memexes (project_admin_role)", skip_enterprise: true do
    @outside_collaborator = create(:user, login: "outside-collaborator")
    repo1 = create(:repository, owner: @org, name: "repo1")
    repo1.add_member(@outside_collaborator)

    memex_project = create(:memex_project, :with_admin, admin: @outside_collaborator, owner: @org)

    only = [RemoveOrgMemberProjectsNextAccessJob]
    perform_enqueued_jobs(only: only) do
      @org.remove_outside_collaborator!(@outside_collaborator)
    end

    granted_actors = UserRole.where(target_type: "MemexProject", target_id: memex_project.id, role: Role.project_admin_role).map(&:actor)
    refute_includes granted_actors, @outside_collaborator
  end

  test "unsubscribes the removed OC from org emails" do
    outside_collaborator = create(:user)
    org_repo = create(:private_repository, :minimal, owner: @org)
    org_repo.add_member(outside_collaborator)

    GitHub.newsies.get_and_update_settings(outside_collaborator) do |settings|
      settings.email(@org, "emailfororg.com")
    end

    assert_equal "emailfororg.com", GitHub.newsies.settings(outside_collaborator).email(@org).address
    @org.remove_outside_collaborator!(outside_collaborator)
    refute_equal "emailfororg.com", GitHub.newsies.settings(outside_collaborator).email(@org).address
  end

  test "creates a restorable OrganizationUser record" do
    outside_collaborator = create(:user)
    org_repo = create(:private_repository, :minimal, owner: @org)
    org_repo.add_member(outside_collaborator)
    assert @org.user_is_outside_collaborator?(outside_collaborator.id)

    assert_difference("Restorable::OrganizationUser.count", 1) do
      @org.remove_outside_collaborator!(outside_collaborator)
    end
  end

  test "with save_settings: false does not create a restorable record" do
    outside_collaborator = create(:user)
    org_repo = create(:private_repository, :minimal, owner: @org)
    org_repo.add_member(outside_collaborator)

    assert_difference("Restorable::OrganizationUser.count", 0) do
      @org.remove_outside_collaborator!(outside_collaborator, save_settings: false)
    end
  end

  test "restorable records should be marked as restorable" do
    disable_feature_flag(:remove_org_member_repo_stars_job_use_bulk_ci_only) # This feature prevents creation of restorables
    outside_collaborator = create(:user)
    org_repo = create(:private_repository, :minimal, owner: @org)
    org_repo.add_member(outside_collaborator)
    refute_includes @org.members, outside_collaborator
    assert_includes org_repo.members, outside_collaborator
    assert @org.user_is_outside_collaborator?(outside_collaborator.id)

    only = [RemoveOrgMemberForksJob, RemoveOrgMemberIssueAssignmentsJob, RemoveOrgMemberRepositoryStarsJob, RemoveOrgMemberWatchedRepositoriesJob]
    perform_enqueued_jobs(only: only) do
      @org.remove_outside_collaborator!(outside_collaborator)
    end

    restorable = Restorable::OrganizationUser.first
    assert_predicate restorable, :restorable?
  end

  test "creates restorables" do
    disable_feature_flag(:remove_org_member_repo_stars_job_use_bulk_ci_only) # This feature prevents creation of restorables
    outside_collaborator = create(:user)
    org_repo = create(:private_repository, owner: @org)
    org_repo.add_member(outside_collaborator)
    outside_collaborator.watch_repo org_repo
    issue = create(:issue, repository: org_repo, assignee: outside_collaborator)
    outside_collaborator.star(org_repo)
    collaborator_fork = org_repo.fork(forker: outside_collaborator)

    only = [RemoveOrgMemberForksJob, RemoveOrgMemberIssueAssignmentsJob, RemoveOrgMemberRepositoryStarsJob, RemoveOrgMemberWatchedRepositoriesJob]
    perform_enqueued_jobs(only: only) do
      @org.remove_outside_collaborator!(outside_collaborator)
    end

    assert_equal 1, Restorable::Repository.count
    assert_equal 1, Restorable::IssueAssignment.count
    assert_equal 1, Restorable::WatchedRepository.count
    assert_equal 1, Restorable::RepositoryStar.count
  end

  test "removes collaborator data" do
    outside_collaborator = create(:user)
    org_repo = create(:private_repository, owner: @org)
    org_repo.add_member(outside_collaborator)
    issue = create(:issue, repository: org_repo, assignee: outside_collaborator)
    outside_collaborator.star(org_repo)
    collaborator_fork = org_repo.fork(forker: outside_collaborator)

    only = [RemoveOrgMemberForksJob, RemoveOrgMemberIssueAssignmentsJob]
    perform_enqueued_jobs(only: only) do
      @org.remove_outside_collaborator!(outside_collaborator)
    end

    issue.reload
    refute_includes outside_collaborator.stars, org_repo
    refute_includes issue.assignees, outside_collaborator
    refute outside_collaborator.watching_repo?(org_repo), "expected collaborator to not be watching repo"
    refute_includes outside_collaborator.repositories, collaborator_fork.first
  end

  test "if notifications are enabled, delivers an email notification" do
    outside_collaborator = create(:user)
    org_repo = create(:private_repository, :minimal, owner: @org)
    assert org_repo.add_member(outside_collaborator)
    ActionMailer::Base.deliveries.clear

    perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
      @org.remove_outside_collaborator!(outside_collaborator)
    end
    # end

    assert_equal 1, ActionMailer::Base.deliveries.count,
                 "Expected an email notification to be sent"
  end

  test "if notifications are disabled, does not deliver an email notification" do
    outside_collaborator = create(:user)
    org_repo = create(:private_repository, :minimal, owner: @org)
    assert org_repo.add_member(outside_collaborator)
    ActionMailer::Base.deliveries.clear

    @org.remove_outside_collaborator!(outside_collaborator, send_notification: false)

    assert_empty ActionMailer::Base.deliveries
  end

  test "a reason the user was removed and membership_types should be passed into the instrumentation" do
    outside_collaborator = create(:user)
    org_repo = create(:private_repository, :minimal, owner: @org)
    org_repo.add_member(outside_collaborator)
    @org.reload

    events = subscribe "org.remove_outside_collaborator"
    reason = :two_factor_requirement_non_compliance

    @org.remove_outside_collaborator!(outside_collaborator, reason: reason)

    expected_payload = {
      user: outside_collaborator.login,
      user_id: outside_collaborator.id,
      org: @org.login,
      org_id: @org.id,
      membership_types: [:outside_collaborator],
      reason: reason,
    }

    assert event = events.pop, "expected an event"
    assert_equal expected_payload, event.payload
  end

  test "publishes a license snapshot messages when an the repository is owned by an organization in an enterprise account", skip_enterprise: true do
    business = create(:business)
    business.add_organization(@org)
    @org.reload # make organization aware of the business
    outside_collaborator = create(:user)
    repo = create(:repository, owner: @org)
    repo.add_member(outside_collaborator)

    reset_hydro # clear any messages that were sent during setup

    perform_enqueued_jobs(only: Licensing::SnapshotLicensesJob) do
      @org.remove_outside_collaborator!(outside_collaborator)
    end

    assert_hydro_messages(count: 1, schema: "github.billing.v0.LicenseSnapshot")
  end

  test "does not publish a license snapshot messages when an the repository is not owned by an organization in an enterprise account", skip_enterprise: true do
    outside_collaborator = create(:user)
    repo = create(:repository, owner: @org)
    repo.add_member(outside_collaborator)

    reset_hydro # clear any messages that were sent during setup

    perform_enqueued_jobs(only: Licensing::SnapshotLicensesJob) do
      @org.remove_outside_collaborator!(outside_collaborator)
    end

    assert_hydro_messages(count: 0, schema: "github.billing.v0.LicenseSnapshot")
  end

  unless GitHub.single_business_environment?
    test "updates license usage for business" do
      outside_collaborator = create(:user)
      repo = create(:repository, owner: @org)
      repo.add_member(outside_collaborator)
      business = create(:business, organizations: [@org])
      @org.reload
      assert_enqueued_jobs(1, only: BusinessUpdateLicenseUsageJob) do
        @org.remove_outside_collaborator!(outside_collaborator)
      end
    end
  end
end

module SCIMManagedOrganizationMembershipSharedTests
  include ExternalGroupHelpers

  def test_add_member_scim_managed_user_is_added_to_an_unlinked_team_that_creates_explicit_membership_in_the_organization_and_creates_explicit_membership_entry_for_user
    unlinked_team = create(:team, organization: @organization)
    assert_difference ["OrganizationMembershipEntry.count"], 1 do
      refute @organization.member?(@user)

      adder = GitHub.single_business_environment? ? @organization.admin : @org_user
      unlinked_team.add_member(@user, adder: adder)
      assert @organization.member?(@user)
      assert unlinked_team.member?(@user)

      organization_membership_entry = OrganizationMembershipEntry.find_by(user_id: @user.id, organization_id: @organization.id, adder_type: :admin)
      refute_nil organization_membership_entry
      assert_equal adder.id, T.must(organization_membership_entry).adder_id
    end
  end

  def test_add_member_scim_managed_user_is_not_added_to_an_organization_with_explicit_membership_and_not_create_explicit_organization_membership_entry_for_user
    #stubbing organization add member to fail the add member to call not add the user explicitly
    @organization.stubs(:add_member).returns(nil)
    assert_no_difference ["OrganizationMembershipEntry.count"] do
      @organization.add_member(@user, adder: @organization.admin)
      refute @organization.member?(@user)

      organization_membership_entry = OrganizationMembershipEntry.find_by(user_id: @user.id, organization_id: @organization.id, adder_type: :admin)
      assert_nil organization_membership_entry
    end
  end

  def test_add_member_scim_managed_user_is_being_added_to_an_organization_with_explicit_membership_for_the_second_time_and_second_explicit_organization_membership_entry_for_user_is_not_created
    assert_difference ["OrganizationMembershipEntry.count"], 1 do
      @organization.add_member(@user, adder: @organization.admin)
      assert @organization.member?(@user)

      organization_membership_entry = OrganizationMembershipEntry.find_by(user_id: @user.id, organization_id: @organization.id, adder_type: :admin)
      refute_nil organization_membership_entry
      assert_equal @organization.admin.id, T.must(organization_membership_entry).adder_id
    end

    assert_no_difference ["OrganizationMembershipEntry.count"] do
      @organization.add_member(@user, adder: @organization.admin)
      assert @organization.member?(@user)

      organization_membership_entry = OrganizationMembershipEntry.find_by(user_id: @user.id, organization_id: @organization.id, adder_type: :admin)
      refute_nil organization_membership_entry
      assert_equal @organization.admin.id, T.must(organization_membership_entry).adder_id
    end
  end

  def test_add_member_scim_managed_user_is_added_to_an_organization_with_explicit_membership_and_explicit_organization_membership_entry_for_user
    assert_difference ["OrganizationMembershipEntry.count"], 1 do
      @organization.add_member(@user, adder: @organization.admin)
      assert @organization.member?(@user)

      organization_membership_entry = OrganizationMembershipEntry.find_by(user_id: @user.id, organization_id: @organization.id, adder_type: :admin)
      refute_nil organization_membership_entry
      assert_equal @organization.admin.id, T.must(organization_membership_entry).adder_id
    end
  end

  def test_add_member_scim_managed_user_is_added_to_an_organization_with_explicit_membership_and_create_explicit_organization_membership_entry_for_user_with_admin_user_id_when_there_is_no_adder_id
    assert_difference ["OrganizationMembershipEntry.count"], 1 do
      @organization.add_member(@user)
      assert @organization.member?(@user)

      organization_membership_entry = OrganizationMembershipEntry.find_by(user_id: @user.id, organization_id: @organization.id, adder_type: :admin)
      refute_nil organization_membership_entry
      assert_equal @organization.admin.id, T.must(organization_membership_entry).adder_id
    end
  end

  def test_add_member_scim_managed_user_is_added_to_an_external_group_that_create_derived_membership_in_the_organization_and_creates_derived_membership_entry_for_user
    another_team = create :team, organization: @organization
    ExternalGroupTeam.create(external_group: @another_external_group, team: another_team)

    assert_difference ["OrganizationMembershipEntry.count"], 2 do
      ei_group_membership = ExternalIdentityGroupMembership.create(external_group: @external_group, external_identity: @external_identity)
      reconcile_external_group_teams(external_group: @external_group)

      assert @organization.member?(@user)
      assert @scim_team.member?(@user)

      organization_membership_entry = OrganizationMembershipEntry.find_by(user_id: @user.id, organization_id: @organization.id, adder_id: @scim_team.id, adder_type: :external_team)
      refute_nil organization_membership_entry
      assert_equal @scim_team.id, T.must(organization_membership_entry).adder_id

      ei_group_membership = ExternalIdentityGroupMembership.create(external_group: @another_external_group, external_identity: @external_identity)
      reconcile_external_group_teams(external_group: @another_external_group)

      assert @organization.member?(@user)
      assert another_team.member?(@user)

      organization_membership_entry = OrganizationMembershipEntry.find_by(user_id: @user.id, organization_id: @organization.id, adder_id: another_team.id, adder_type: :external_team)
      refute_nil organization_membership_entry
      assert_equal another_team.id, T.must(organization_membership_entry).adder_id
    end
  end

  def test_add_member_scim_managed_user_with_derived_membership_is_added_to_an_unlinked_team_in_the_organization_and_create_explicit_membership_entry
    assert_difference ["OrganizationMembershipEntry.count"], 1 do
      ei_group_membership = ExternalIdentityGroupMembership.create(external_group: @external_group, external_identity: @external_identity)
      reconcile_external_group_teams(external_group: @external_group)

      assert @organization.member?(@user)
      assert @scim_team.member?(@user)

      organization_membership_entry = OrganizationMembershipEntry.find_by(user_id: @user.id, organization_id: @organization.id, adder_id: @scim_team.id, adder_type: :external_team)
      refute_nil organization_membership_entry
      assert_equal @scim_team.id, T.must(organization_membership_entry).adder_id
    end

    unlinked_team = create(:team, organization: @organization)
    assert_difference ["OrganizationMembershipEntry.count"], 1 do
      unlinked_team.add_member(@user, adder: @organization.admin)
      assert @organization.member?(@user)
      assert unlinked_team.member?(@user)

      organization_membership_entry = OrganizationMembershipEntry.find_by(user_id: @user.id, organization_id: @organization.id, adder_type: :admin)
      refute_nil organization_membership_entry
    end
  end

  def test_add_member_scim_managed_user_with_derived_membership_and_explicit_membership_is_added_to_a_regular_github_team_in_the_organization_and_not_create_explicit_membership_entry
    assert_difference ["OrganizationMembershipEntry.count"], 1 do
      @organization.add_member(@user, adder: @organization.admin)
      assert @organization.member?(@user)

      organization_membership_entry = OrganizationMembershipEntry.find_by(user_id: @user.id, organization_id: @organization.id, adder_type: :admin)
      refute_nil organization_membership_entry
      assert_equal @organization.admin.id, T.must(organization_membership_entry).adder_id
    end

    assert_difference ["OrganizationMembershipEntry.count"], 1 do
      ei_group_membership = ExternalIdentityGroupMembership.create(external_group: @external_group, external_identity: @external_identity)
      reconcile_external_group_teams(external_group: @external_group)

      assert @organization.member?(@user)
      assert @scim_team.member?(@user)

      organization_membership_entry = OrganizationMembershipEntry.find_by(user_id: @user.id, organization_id: @organization.id, adder_id: @scim_team.id, adder_type: :external_team)
      refute_nil organization_membership_entry
      assert_equal @scim_team.id, T.must(organization_membership_entry).adder_id
    end

    unlinked_team = create(:team, organization: @organization)
    assert_no_difference ["OrganizationMembershipEntry.count"] do
      unlinked_team.add_member(@user, adder: @organization.admin)
      assert @organization.member?(@user)
      assert unlinked_team.member?(@user)

      organization_membership_entry = OrganizationMembershipEntry.find_by(user_id: @user.id, organization_id: @organization.id, adder_type: :admin)
      refute_nil organization_membership_entry
    end
  end

  def test_remove_member_scim_managed_user_with_explicit_member_is_removed_from_the_organization_when_removed_from_the_organization_explicitly
    disable_feature_flag(:remove_org_member_repo_stars_job_use_bulk_ci_only) # This feature prevents creation of restorables
    # explicit membership
    @organization.add_member(@user, adder: @organization.admin)
    assert @organization.member?(@user)

    assert_difference ["OrganizationMembershipEntry.count"], -1 do
      perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
        @organization.remove_member(@user)
      end

      organization_membership_entry = OrganizationMembershipEntry.find_by(user_id: @user.id, organization_id: @organization.id, adder_type: :admin)
      assert_nil organization_membership_entry
      refute @organization.member?(@user)
    end
  end

  def test_remove_member_scim_managed_user_with_derived_membership_is_removed_from_the_organization_when_removed_from_external_group
    # derived membership
    ei_group_membership = ExternalIdentityGroupMembership.create(external_group: @external_group, external_identity: @external_identity)
    reconcile_external_group_teams(external_group: @external_group)

    assert @organization.member?(@user)
    assert @scim_team.member?(@user)

    assert_difference ["OrganizationMembershipEntry.count"], -1 do
      ei_group_membership.destroy
      perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
        reconcile_external_group_teams(external_group: @external_group)
      end

      refute @scim_team.member?(@user)
      refute @organization.member?(@user)

      organization_membership_entry = OrganizationMembershipEntry.find_by(user_id: @user.id, organization_id: @organization.id, adder_id: @scim_team.id, adder_type: :external_team)
      assert_nil organization_membership_entry
    end
  end

  def test_remove_member_scim_managed_user_with_explicit_membership_by_adding_to_a_regular_github_team_and_derived_membership_not_removed_from_the_organization_when_removed_from_external_group
    # derived membership
    ei_group_membership = ExternalIdentityGroupMembership.create(external_group: @external_group, external_identity: @external_identity)
    perform_enqueued_jobs(only: [ExternalGroupTeamReconcileJob]) do
      reconcile_external_group_teams(external_group: @external_group)
    end

    assert @organization.member?(@user)
    assert @scim_team.member?(@user)

    # explicit membership
    unlinked_team = create(:team, organization: @organization)
    unlinked_team.add_member(@user)
    assert unlinked_team.member?(@user)

    assert_difference ["OrganizationMembershipEntry.count"], -1 do
      perform_enqueued_jobs(only: [ExternalGroupTeamReconcileJob, RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
        ei_group_membership.destroy
        reconcile_external_group_teams(external_group: @external_group)
      end

      organization_membership_entry = OrganizationMembershipEntry.find_by(user_id: @user.id, organization_id: @organization.id, adder_id: @scim_team.id, adder_type: :external_team)
      assert_nil organization_membership_entry

      organization_membership_entry = OrganizationMembershipEntry.find_by(user_id: @user.id, organization_id: @organization.id, adder_type: :admin)
      refute_nil organization_membership_entry

      refute @scim_team.member?(@user)
      assert @organization.member?(@user)
    end
  end

  def test_remove_member_scim_managed_user_with_derived_membership_not_removed_from_the_organization_when_removed_from_external_group_1_of_2
    # second emu team
    another_emu_team = create :team, organization: @organization
    ExternalGroupTeam.create(external_group: @another_external_group, team: another_emu_team)

    # create derived membership
    ei_group_membership = ExternalIdentityGroupMembership.create(external_group: @external_group, external_identity: @external_identity)
    ExternalIdentityGroupMembership.create(external_group: @another_external_group, external_identity: @external_identity)
    reconcile_external_group_teams(external_group: @external_group)
    reconcile_external_group_teams(external_group: @another_external_group)

    assert @organization.member?(@user)
    assert @scim_team.member?(@user)
    assert another_emu_team.member?(@user)

    # removed from external group
    assert_difference ["OrganizationMembershipEntry.count"], -1 do
      ei_group_membership.destroy
      perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
        reconcile_external_group_teams(external_group: @external_group)
      end

      organization_membership_entry = OrganizationMembershipEntry.find_by(user_id: @user.id, organization_id: @organization.id, adder_id: @scim_team.id, adder_type: :external_team)
      assert_nil organization_membership_entry
    end

    organization_membership_entry = OrganizationMembershipEntry.find_by(user_id: @user.id, organization_id: @organization.id, adder_id: another_emu_team.id, adder_type: :external_team)
    refute_nil organization_membership_entry

    assert @organization.member?(@user)
    refute @scim_team.member?(@user)
    assert another_emu_team.member?(@user)
  end

  def test_remove_member_scim_managed_user_with_explicit_membership_by_manually_adding_to_organization_and_derived_membership_not_removed_from_the_organization_when_derived_membership_is_removed
    # explicit membership
    @organization.add_member(@user, adder: @organization.admin)
    assert @organization.member?(@user)

    # derived membership
    ei_group_membership = ExternalIdentityGroupMembership.create(external_group: @external_group, external_identity: @external_identity)
    reconcile_external_group_teams(external_group: @external_group)
    assert @scim_team.member?(@user)

    # this user is removed by IDP via SCIM
    # and removed from team and Org
    assert_difference ["OrganizationMembershipEntry.count"], -1 do
      ei_group_membership.destroy
      perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
        reconcile_external_group_teams(external_group: @external_group)
      end

      assert @organization.member?(@user)
      refute @scim_team.member?(@user)
    end
  end

  def test_remove_member_scim_managed_user_with_explicit_membership_by_adding_to_unlinked_team_not_removed_from_organization_when_removed_from_the_unlinked_team
    # explicit membership
    unlinked_team = create(:team, organization: @organization)
    unlinked_team.add_member(@user)
    assert unlinked_team.member?(@user)

    assert_no_difference ["OrganizationMembershipEntry.count"] do
      unlinked_team.remove_member(@user)

      organization_membership_entry = OrganizationMembershipEntry.find_by(user_id: @user.id, organization_id: @organization.id, adder_type: :admin)
      refute_nil organization_membership_entry

      assert @organization.member?(@user)
    end
  end

  def test_remove_member_scim_managed_user_with_explicit_and_derived_membership_not_removed_from_the_organization_when_explicitly_removed
    # derived membership
    ei_group_membership = ExternalIdentityGroupMembership.create(external_group: @external_group, external_identity: @external_identity)
    reconcile_external_group_teams(external_group: @external_group)

    assert @organization.member?(@user)
    assert @scim_team.member?(@user)

    # explicit membership
    unlinked_team = create(:team, organization: @organization)
    unlinked_team.add_member(@user)
    assert unlinked_team.member?(@user)

    assert_raises Organization::UnableToRemoveEmuError do
      @organization.remove_member(@user)
    end
  end
end

class EMUOrganizationMembershipTest < GitHub::TestCase
  skip_enterprise

  include SCIMManagedOrganizationMembershipSharedTests

  fixtures do
    @enterprise = create :business, :enterprise_managed
    @scim_provider = create :business_saml_provider, business: @enterprise

    @organization_admin = create :emu, business: @enterprise
    @organization = create :organization, business: @enterprise, admin: @organization_admin

    @external_group = create :external_group, business: @enterprise
    @scim_team = create :team, organization: @organization
    ExternalGroupTeam.create(external_group: @external_group, team: @scim_team)

    @another_external_group = ExternalGroup.create(
      provider: @scim_provider,
      external_id: SecureRandom.uuid,
      display_name: "test-#{SecureRandom.hex(8)}"
    )

    @user = create :emu, business: @enterprise
    @external_identity = @user.external_identities.first

    @org_user = create :emu, business: @enterprise
    @organization.add_member(@org_user)
  end

  setup do
    disable_feature_flag(:disable_external_group_team_reconcile_job)
  end

  context "add_member" do
    test "non emu user is added to an non emu organization does not create organization membership entry for user" do
      org_admin = create :user
      user = create :user
      org = create(:organization, admin: org_admin)

      assert_no_difference ["OrganizationMembershipEntry.count"] do
        org.add_member(user)
      end
    end
  end

  context "remove_member" do
    test "emu user business user account is not removed when removed from an organization" do
      # explicit membership
      @organization.add_member(@user, adder: @organization.admin)
      assert @organization.member?(@user)

      perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
        @organization.remove_member(@user)
      end

      refute @organization.member?(@user)

      emu_business_user_account = @enterprise.business_user_account_for(@user)
      refute_nil emu_business_user_account
    end
  end
end unless GitHub.single_business_environment?

class OrganizationMembershipGHESWithSCIMTest < GitHub::TestCase
  include AuthenticationHelpers::SAML
  include SCIMManagedOrganizationMembershipSharedTests

  fixtures do
    setup_saml_auth_mode(with_scim: true)
    @owner = create :ghes_scim_user, :admin
    provider = @owner.external_identities.first.provider
    provider.update(scim_provisioning_state: "scim_provisioning_state_enabled")

    @enterprise = provider.business

    @external_group = create :external_group, :with_team, business: @enterprise

    @scim_team = @external_group.external_group_teams.first.team
    @organization = @scim_team.organization.reload

    @another_external_group = create :external_group, business: @enterprise

    @user = create :ghes_scim_user, business: @enterprise
    @external_identity = @user.external_identities.first

    @org_user = create :ghes_scim_user, business: @enterprise
    @org_user_external_identity = @org_user.external_identities.first

    @organization.add_member(@org_user)
  end

  setup do
    setup_saml_auth_mode(with_scim: true)
    disable_feature_flag(:disable_external_group_team_reconcile_job)
  end
end if GitHub.single_business_environment?
