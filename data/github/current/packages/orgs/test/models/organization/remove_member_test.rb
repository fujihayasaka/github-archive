# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationRemoveMemberTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @org = create(:organization, login: "remove-member-org", plan: "bronze")
    @org_admin = @org.admins.first
    @private_repo = create(:private_repository, owner: @org, name: "org-owned-private-repo", from_example: :simple)
    @user = create(:user)
    @new_org_admin = create(:user)
    @org.add_admin(@new_org_admin, adder: @org_admin)
  end

  test "does not remove the last admin" do
    GitHub.flipper[:org_remove_member_cleanup_in_bulk_test_only].disable # This feature does not support safety checks
    org_admin = create(:user)
    org = create(:organization, plan: "bronze", admin: org_admin)
    other_org_admin = create(:user)
    org.add_admin(other_org_admin, adder: org_admin)
    org.reload
    assert_raises(Organization::NoAdminsError) { [org_admin, other_org_admin].each { |u| org.remove_member!(u) } }
  end

  unless GitHub.single_business_environment?
    test "can remove the last admin if organization supports it" do
      business = create(:business, organizations: [@org])
      GitHub.flipper[:enterprise_idp_provisioning].enable(business)
      create(:business_saml_provider, :full_user_provisioning, business: business)
      assert @org.reload.can_be_orphaned?
      @org.admins.each { |admin| @org.remove_member!(admin, allow_last_admin_removal: true) }
      assert @org.admins.empty?
    end
  end

  test "removing admin removes their private forks" do
    @org.allow_private_repository_forking(actor: @org_admin)
    admin_fork, reason = @private_repo.fork(forker: @new_org_admin)
    assert_difference("Repository.active.count", -1) do
      only = [
        RevokeOrgMembershipAbilitiesJob,
        RemoveOrgMemberForksJob,
        BulkRemoveOrgMemberForksJob
      ]
      perform_enqueued_jobs only: only do
        @org.remove_member!(@new_org_admin, save_settings: false)
      end
    end
    assert Repositories::Public.is_deleted?(admin_fork.id), "Private fork should be deleted"
  end

  test "deletes member's user status specific to the organization" do
    @org.add_member(@user)
    status = create(:user_status, user: @user, organization: @org)

    assert_difference "UserStatus.count", -1 do
      @org.remove_member!(@user)
    end

    refute UserStatus.exists?(status.id)
  end

  test "creates a restorable OrganizationUser record" do
    GitHub.flipper[:org_remove_member_cleanup_in_bulk_test_only].disable # This feature does not create restorables
    @org.add_member(@user)

    assert_difference("Restorable::OrganizationUser.count", 1) do
      perform_enqueued_jobs(only: RevokeOrgMembershipAbilitiesJob) do
        @org.remove_member!(@user)
      end
    end
  end

  test "with save_settings: false does not create a restorable record" do
    assert_difference("Restorable::OrganizationUser.count", 0) do
      @org.remove_member!(@user, save_settings: false)
    end
  end

  test "will no-op on a nil user" do
    assert_difference("Restorable::OrganizationUser.count", 0) do
      @org.remove_member!(@nil_user)
    end
  end

  test "#save_organization_settings_for_user marks created restorable as complete" do
    @org.add_member(@user)

    assert_difference("Restorable::OrganizationUser.count", 1) do
      @org.save_organization_settings_for_user(@user)
    end

    organization_user = Restorable::OrganizationUser.first
    assert_equal true, organization_user.restorable.saved?([:restorable_memberships])
  end

  test "restorable records should be marked as restorable" do
    GitHub.flipper[:org_remove_member_cleanup_in_bulk_test_only].disable # Does not create restorables
    GitHub.flipper[:remove_org_member_repo_stars_job_use_bulk_ci_only].disable # This feature prevents creation of restorables
    @org.add_member(@user)

    only = [
      RevokeOrgMembershipAbilitiesJob,
      RemoveOrgMemberForksJob,
      RemoveOrgMemberWatchedRepositoriesJob,
      RemoveOrgMemberRepositoryStarsJob,
      RemoveOrgMemberIssueAssignmentsJob,
      RemoveOrgMemberVulnerabilityManagementJob,
      RemoveOrgMemberPackageAccessJob,
    ]
    perform_enqueued_jobs only: only do
      @org.remove_member!(@user)
    end

    restorable = Restorable::OrganizationUser.first
    assert_predicate restorable, :restorable?
  end

  test "instruments membership event to hydro", skip_enterprise: true do
    @org.add_member(@user)

    GitHub.hydro_publisher.sink&.messages&.clear

    @org.remove_member!(@user)
    assert_hydro_messages(count: 1, schema: "github.v1.MembershipUpdate")
  end

  test "should unsubscribe user from org email" do
    @org.add_member(@user)
    GitHub.newsies.get_and_update_settings(@user) do |settings|
      settings.email(@org, "emailfororg.com")
    end

    assert_equal "emailfororg.com", GitHub.newsies.settings(@user).email(@org).address
    perform_enqueued_jobs only: RevokeOrgMembershipAbilitiesJob do
      @org.remove_member!(@user)
    end

    refute_equal "emailfororg.com", GitHub.newsies.settings(@user).email(@org).address
  end

  test "a reason the user was removed should be passed into the instrumentation" do
    GitHub.context.push(actor: @user)
    @org.add_member(@user)
    events = subscribe "org.remove_member"
    reason = Organization::RemovedMemberNotification::TWO_FACTOR_REQUIREMENT_NON_COMPLIANCE

    @org.remove_member!(@user, reason: reason)

    expected_payload = {
      user: @user.login,
      user_id: @user.id,
      org: @org.login,
      org_id: @org.id,
      membership_types: ["direct_member"],
      reason: reason,
      actor_id: @user.id,
      actor: @user.login,
    }

    assert event = events.pop, "expected an event"
    assert_includes event.payload, :reason
    assert_equal reason, event.payload[:reason]
    assert_equal expected_payload, event.payload
  end

  test "if the user is a member and billing manager the reason the user was removed should be passed into org.remove_billing_manager event" do
    GitHub.flipper[:org_remove_member_cleanup_in_bulk_test_only].disable # This feature has simple audit logging for now
    @org.add_member(@user)
    @org.billing.add_manager(@user, actor: nil)
    events = subscribe "org.remove_billing_manager"

    reason = :two_factor_requirement_non_compliance

    @org.remove_member!(@user, reason: reason)

    expected_payload = {
      actor: nil,
      user: @user.login,
      user_id: @user.id,
      org: @org.login,
      org_id: @org.id,
      reason: reason,
    }

    assert event = events.pop, "expected an event"
    assert_equal event.name, "org.remove_billing_manager"
    assert_equal expected_payload, event.payload
  end

  test "the membership type the user had should be passed into the instrumentation" do
    GitHub.flipper[:org_remove_member_cleanup_in_bulk_test_only].disable # Only direct member removals are supported in bulk removals
    GitHub.context.push(actor: @user)
    @org.add_member(@user)
    @org.billing.add_manager(@user, actor: create(:user))
    events = subscribe "org.remove_member"

    @org.remove_member!(@user)

    expected_membership_types = %w[direct_member billing_manager]
    expected_payload = {
      user: @user.login,
      user_id: @user.id,
      org: @org.login,
      org_id: @org.id,
      membership_types: expected_membership_types,
      reason: nil,
      actor_id: @user.id,
      actor: @user.login,
    }

    assert event = events.pop, "expected an event"
    assert_includes event.payload, :membership_types
    assert_equal expected_membership_types, event.payload[:membership_types]
    assert_equal expected_payload, event.payload
  end

  test "deprovisions SAML external identities linked to the user and organization" do
    external_identity = create :external_identity
    provider = external_identity.provider
    org = provider.organization
    user = external_identity.user

    assert ExternalIdentity.linked? \
      provider: provider,
      user: user

    assert_difference("org.saml_provider.external_identities.count", -1) do
      org.remove_member!(user)
    end

    refute ExternalIdentity.linked? \
      provider: provider,
      user: user
  end

  test "preserves SCIM external identities linked to the user and organization" do
    external_identity = create :external_identity, :scim
    provider = external_identity.provider
    org = provider.organization
    user = external_identity.user

    assert ExternalIdentity.linked? \
      provider: provider,
      user: user

    assert_no_difference("org.saml_provider.external_identities.count") do
      org.remove_member!(user)
    end

    assert ExternalIdentity.linked? \
      provider: provider,
      user: user
  end

  test "deprovisions SAML external identities linked to the billing manager and organization" do
    provider = create(:organization_saml_provider)
    org = provider.organization
    billing_manager = create :user
    create :external_identity, provider: provider, user: billing_manager
    org.billing.add_manager(billing_manager, actor: org.admins.first)

    assert ExternalIdentity.linked? \
      provider: provider,
      user: billing_manager

    assert_difference("org.saml_provider.external_identities.count", -1) do
      org.billing.remove_manager(billing_manager, actor: org.admins.first)
    end

    refute ExternalIdentity.linked? \
      provider: provider,
      user: billing_manager
  end

  test "preserves SCIM external identities linked to the billing manager and organization" do
    provider = create(:organization_saml_provider)
    org = provider.organization
    billing_manager = create :user
    create :external_identity, :scim, provider: provider, user: billing_manager
    org.billing.add_manager(billing_manager, actor: org.admins.first)

    assert ExternalIdentity.linked? \
      provider: provider,
      user: billing_manager

    assert_no_difference("org.saml_provider.external_identities.count") do
      org.billing.remove_manager(billing_manager, actor: org.admins.first)
    end

    assert ExternalIdentity.linked? \
      provider: provider,
      user: billing_manager
  end

  test "deletes external identities if SAML is disabled for the org" do
    external_identity = create :external_identity
    provider = external_identity.provider
    org = provider.organization
    billing_manager = create :user
    org.billing.add_manager(billing_manager, actor: org.admins.first)
    manager_identity = create :external_identity, provider: provider, user: billing_manager

    assert_same_elements [external_identity, manager_identity],
                         org.saml_provider.external_identities

    assert_difference("org.saml_provider.external_identities.count", -2) do
      perform_enqueued_jobs only: DestroyDependentRecordsJob do
        org.saml_provider.destroy
      end
    end
  end

  test "cancels pending invitations from the member" do
    GitHub.flipper[:org_remove_member_cleanup_in_bulk_test_only].disable # This feature does not cancel invitations
    inviter = create(:user)
    @org.add_member(inviter, action: :admin)
    invitee = create(:user)
    invitation = @org.invite(invitee, inviter: inviter)
    assert_nil invitation.cancelled_at
    @org.remove_member!(inviter)
    invitation.reload
    refute_nil invitation.cancelled_at
  end

  test "does not cancel accepted invitations from the member" do
    inviter = create(:user)
    @org.add_member(inviter, action: :admin)
    invitee = create(:user)
    invitation = @org.invite(invitee, inviter: inviter)
    assert_equal OrganizationInvitation.count, 1
    invitation.accept
    @org.remove_member!(inviter)
    assert_equal OrganizationInvitation.count, 1
  end

  test "enqueues a job to revoke the app-management grants for the member" do
    @org.add_member(@user)
    assert_performed_with(
      job: RevokeOrgAppsManagementGrantsJob,
      args: [@org, @user],
      queue: "revoke_org_apps_management_grants",
    ) do
      @org.remove_member!(@user)
    end
  end

  test "does not allow app manager to be added while an org member is async removed" do
    # This test mimics a race condition with app manager permisions
    # https://github.com/github/ecosystem-apps/issues/4795
    @org.add_member(@user)
    integration = create(:integration, owner: @org)

    # mocks granting app manager permissions during async org membership removal
    RevokeOrgMemberProgrammaticAccessGrantsJob.expects(:perform_later).with do |_org, _user|
      Permissions::Granter.grant(
        action: :manage_app,
        actor_id: @user.id,
        subject_id: integration.id,
        entry_point: :test_case,
      )
      assert ::Permissions::Enforcer.authorize(
        actor: @user,
        action: :manage_app,
        subject: integration,
      ).allow?
    end

    perform_enqueued_jobs(only: [RevokeOrgMembershipAbilitiesJob, RevokeOrgAppsManagementGrantsJob]) do
      @org.remove_member!(@user)
    end

    refute ::Permissions::Enforcer.authorize(
      actor: @user,
      action: :manage_app,
      subject: integration,
    ).allow?
  end

  test "enqueues a job to revoke programmatic access grants for the member" do
    @org.add_member(@user)
    assert_performed_with(
      job: RevokeOrgMemberProgrammaticAccessGrantsJob,
      args: [@org, @user],
      queue: "programmatic_access_grants",
    ) do
      @org.remove_member!(@user)
    end
  end

  test "revokes internal OAuth authorizations when user 'leaves' enterprise via removal of last organization membership" do
    business = create(:global_business)
    app = create(:enterprise_owned_integration, owner: business)
    org_one = create(:organization, business: business)
    org_two = create(:organization, business: business) # Part of the enterprise, but user is not a member.
    member = create(:user)

    org_one.add_member(member)

    app.grant(member)

    perform_enqueued_jobs only: [RevokeInternalAppAuthorizationsJob, BusinessMembershipCleanupJob] do
      org_one.remove_member!(member)
    end

    assert_equal 0, app.accesses.count
    assert_equal 0, app.authorizations.count
  end

  test "does not revoke internal OAuth authorizations when user remains member of enterprise via other organization memberships" do
    GitHub.flipper[:org_remove_member_cleanup_in_bulk_test_only].disable # Runs an incomprehensible forked set of cleanup logic that ends up enqueing the RevokeInternalAppAuthorizationsJob without the proper guards in place.

    business = create(:global_business)
    app = create(:enterprise_owned_integration, owner: business)
    org_one = create(:organization, business: business)
    org_two = create(:organization, business: business)
    member = create(:user)

    org_one.add_member(member)
    org_two.add_member(member)

    app.grant(member)

    # For some reason, in TEST_ALL_FEATURES mode this test fails because
    # `Business#organization_member_ids` returns an empty array. No idea why.
    # Presumably some combination of feature flags is conspiring against us.
    # Reloading the model before attempting to exercise the behavior we're
    # interested in alleviates the problem.
    business.reload

    perform_enqueued_jobs only: [RevokeInternalAppAuthorizationsJob, BusinessMembershipCleanupJob] do
      org_one.remove_member!(member)
    end

    assert business.async_member?(member)
    assert org_two.member?(member)

    assert_equal 1, app.accesses.count
    assert_equal 1, app.authorizations.count
  end

  if GitHub.user_abuse_mitigation_enabled?
    test "removes user as a moderator" do
      @org.add_member(@user)
      @org.moderation.add_moderator(@user, actor: @org_admin)

      assert @org.moderation.moderator?(@user)
      assert_includes @org.members, @user

      perform_enqueued_jobs only: RevokeOrgMembershipAbilitiesJob do
        @org.remove_member!(@user)
      end

      refute @org.moderation.moderator?(@user)
      refute_includes @org.members, @user
    end
  end

  unless GitHub.single_business_environment?
    test "publishes license snapshot messages when a user is removed from an organization owned by a business" do
      business = create(:business)
      @org.update(business: business)
      @org.add_member(@user)
      reset_hydro # clear any messages that were sent during setup

      perform_enqueued_jobs(only: Licensing::SnapshotLicensesJob) do
        @org.reload.remove_member!(@user)
      end

      assert_hydro_messages(count: 1, schema: "github.billing.v0.LicenseSnapshot")
    end

    test "does not publish license snapshot messages when a user is removed from an organization not owned by a business" do
      @org.add_member(@user)
      reset_hydro # clear any messages that were sent during setup

      perform_enqueued_jobs(only: Licensing::SnapshotLicensesJob) do
        @org.reload.remove_member!(@user)
      end

      assert_hydro_messages(count: 0, schema: "github.billing.v0.LicenseSnapshot")
    end
  end

  # When multiple invitations exist for a member (E.g. one for org membership,
  # one for outside collaborator membership on a org-owned repository) we
  # should remove them all so that a removed member cannot regain access to
  # either the organization or one of its repositories.
  # https://github.com/github/github/issues/82731
  if GitHub.repo_invites_enabled?
    test "cancels pending repository invitations involving the member" do
      GitHub.flipper[:org_remove_member_cleanup_in_bulk_test_only].disable # This feature does not cancel invitations
      invitee = create(:user, login: "invited-user")
      private_repo_2 = create(:private_repository, owner: @org, name: "private-repo-2")

      org_invitation = @org.invite(invitee, inviter: @org_admin)

      RepositoryInvitation.invite_to_repo(invitee, @org_admin, @private_repo)
      RepositoryInvitation.invite_to_repo(invitee, @org_admin, private_repo_2)

      assert_equal 1, @org.pending_invitations.with_invitee_or_normalized_email(invitee: invitee).count
      assert @private_repo.has_invitation_for?(invitee)
      assert private_repo_2.has_invitation_for?(invitee)

      org_invitation.accept

      @org.remove_member!(invitee)

      refute @private_repo.has_invitation_for?(invitee), "should have cancelled repo invitation to #{@private_repo} for #{invitee}"
      refute private_repo_2.has_invitation_for?(invitee), "should have cancelled repo invitation to #{private_repo_2} for #{invitee}"
    end
  end

  context "#can_be_orphaned?" do
    test "returns false if org is not owned by a business" do
      refute @org.can_be_orphaned?
    end

    unless GitHub.single_business_environment?
      test "returns false if belongs to a business without SAML" do
        business = create(:business, organizations: [@org])
        GitHub.flipper[:enterprise_idp_provisioning].enable(business)
        refute @org.reload.can_be_orphaned?
      end

      test "returns false if feature flag isn't enabled for the business" do
        business = create(:business, organizations: [@org])
        GitHub.flipper[:enterprise_idp_provisioning].disable
        create(:business_saml_provider, :full_user_provisioning, business: business)
        refute @org.reload.can_be_orphaned?
      end

      test "returns true if belongs to a business with SAML enabled" do
        business = create(:business, organizations: [@org])
        GitHub.flipper[:enterprise_idp_provisioning].enable(business)
        create(:business_saml_provider, :full_user_provisioning, business: business)
        assert @org.reload.can_be_orphaned?
      end

      test "returns false if the organization belongs to a business on trial that is not cancelled" do
        business = create(:business, organizations: [@org])
        business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        assert_predicate business, :trial?
        refute_predicate business, :trial_cancelled?
        refute @org.reload.can_be_orphaned?
      end

      test "returns true if the organization belongs to a business on a cancelled enterprise trial" do
        business = create(:business, organizations: [@org])
        business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        assert_predicate business, :trial?
        refute_predicate business, :trial_cancelled?

        business.cancel_trial(@org_admin)

        assert_predicate business.reload, :trial_cancelled?
        assert @org.reload.can_be_orphaned?
      end
    end
  end
end
