# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessOrganizationMembershipTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @admin = create :two_factor_credential_user
    @business = create :business, owners: [@admin]
    @organization = create :organization
    #Enterprise creates a config entry for display_commenter_full_name in new orgs by default
    #This would throw off tests that assert on configuration entries
    #Clearing it allows us to have the same test coverage for enterprise
    @organization.configuration_entries.first.delete if GitHub.enterprise?
    @repo = create(:private_repository, :minimal, owner: @organization)

    perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) { @business.update_default_repository_permission(:write, actor: @admin) }

    @member = create :user
    @organization.add_member(@member)

    @organization2 = create(:organization, admins: [create(:two_factor_credential_user)])

    only = [SyncOrganizationDefaultRepositoryPermissionJob, BusinessUserAccountCreateForOrganizationJob, BusinessUpdateLicenseUsageJob]
    perform_enqueued_jobs(only: only) do
      @org_membership = create :business_organization_membership, business: @business, organization: @organization
    end
  end

  context "validations" do
    test "require that a business be present" do
      membership = build :business_organization_membership, business: nil

      refute_predicate membership, :valid?
      assert_includes membership.errors[:business], "can't be blank"
    end

    test "require that an organization can only be associated with one business" do
      membership = build :business_organization_membership, organization: @organization

      refute_predicate membership, :valid?
      assert_includes membership.errors[:organization_id], "is already associated with an enterprise account"
    end

    test "allow overallocation of enterprise licenses if there are sufficient volume licenses", skip_enterprise: true do
      @organization2.add_member(create(:user))
      @business.update! seats: @business.consumed_invitable_licenses

      membership = @business.organization_memberships.new(organization: @organization2)

      refute_predicate membership, :valid?
      assert_includes membership.errors[:base], "Insufficient seats to add this organization (2 seats required to add #{@organization2.login}, 2 more must be purchased for the enterprise account)"

      enterprise_agreement = create(:enterprise_agreement, business: @business, seats: 1)

      refute_predicate membership, :valid?
      assert_includes membership.errors[:base], "Insufficient seats to add this organization (2 seats required to add #{@organization2.login}, 1 more must be purchased for the enterprise account)"

      enterprise_agreement.update(seats: 2)

      assert_predicate membership, :valid?

      membership.save!

      # Ensure all enqueued jobs perform successfully
      assert_empty Failbot.reports
    end

    if GitHub.single_business_environment?
      test "don't block adding orgs to the global business on GitHub Enterprise" do
        license = GitHub::Enterprise::LicenseMock.new \
          expire_at: 1.year.from_now.to_datetime,
          seats: 10,
          perpetual: false,
          unlimited: false
        GitHub::Enterprise.stubs(:license).returns(license)
        license.sync_with_global_business

        to_add = create :organization
        # Add all _existing_ users to the org.
        User.where(type: "User").each do |user|
          to_add.add_member user
        end
        # Suspend an existing business member
        @member.suspend "Reasons"

        @business.update! seats: @business.consumed_invitable_licenses

        membership = @business.organization_memberships.build organization: to_add
        assert_predicate membership, :valid?
      end
    else
      test "require that the business has enough seats to cover the organization" do
        license = GitHub::Enterprise::LicenseMock.new \
          expire_at: 1.year.from_now.to_datetime,
          seats: 10,
          perpetual: false,
          unlimited: false
        GitHub::Enterprise.stubs(:license).returns(license)
        license.sync_with_global_business

        to_add = create :organization
        to_add.add_member @organization.admins.first

        @business.update! seats: 2
        membership = @business.organization_memberships.build organization: to_add

        refute_predicate membership, :valid?
        assert_includes membership.errors[:base], "Insufficient seats to add this organization (1 seat required to add #{membership.organization.login}, 1 more must be purchased for the enterprise account)"

        @business.update! seats: 3
        assert_predicate membership, :valid?
      end
    end

    test "don't block adding orgs if the business is using metered GHEC" do
      @business.seats = 0
      @business.customer.update!(metered_ghe: true)

      membership = @business.organization_memberships.new(organization: @organization2)
      assert_predicate membership, :valid?
    end

    test "don't upgrade billing if billing is disabled" do
      GitHub.stubs(:billing_enabled?).returns(false)
      @business.expects(:migrate_organization_to_business_billing).never
      create :business_organization_membership, business: @business, organization: @organization2
    end

    test "does not look at seats if the GitHub license is unlimited" do
      GitHub.stubs(:single_business_environment?).returns(true)

      # Set seats to the current consumed_invitable_licenses so any additional would
      # otherwise not be allowed.
      @business.update! seats: @business.consumed_invitable_licenses

      to_add = create :organization
      to_add.add_member @organization.admins.first
      membership = @business.organization_memberships.build organization: to_add

      assert_predicate membership, :valid?
    end
  end

  test "schedules the job to update app installations in orgs when business membership is created" do
    org = create :organization
    expected_args = [
      @business.id,
      { entry_point: :business_organization_membership_update_private_search_on_orgs }
    ]
    assert_enqueued_with(job: UpdatePrivateSearchOnEnterpriseOrgsJob, args: expected_args) do
      membership = @business.add_organization(org)
    end
  end

  test "schedules the job to update app installations in orgs when business membership is destroyed" do
    org = create :organization
    @business.add_organization(org)

    expected_args = [
      @business.id,
      { entry_point: :business_organization_membership_update_private_search_on_orgs }
    ]
    assert_enqueued_with(job: UpdatePrivateSearchOnEnterpriseOrgsJob, args: expected_args) do
      @business.remove_organization(org)
    end
  end

  test "updates default repository permission when business membership is created" do
    # test that the creation of the org membership in the fixtures
    # synced the default repository permissions for the org
    assert_equal :write, @organization.default_repository_permission
    assert_able @member, :write, @repo
  end

  test "does not sync permission multiple times for a single organization" do
    @organization.expects(:sync_default_repository_permission).once
    # intentionally not using RockQueue.inline so that we can test whether
    # multiple jobs would be queued
    @org_membership.destroy
    create :business_organization_membership, business: @business, organization: @organization
  end

  test "enables 2fa for the organization if the Business it's joining requires 2fa" do
    assert_enqueued_with(
      job: EnforceTwoFactorRequirementOnOrganizationJob,
      args: [@organization2, @organization2, { disallowed_methods: [] }]) do
      @business.enable_two_factor_required(actor: @admin, force: true)
      create :business_organization_membership, business: @business, organization: @organization2
    end
  end

  test "does not enable 2fa for the org, if the business doesn't require it" do
    assert_no_enqueued_jobs only: EnforceTwoFactorRequirementOnOrganizationJob do
      create :business_organization_membership, business: @business, organization: @organization2
    end
  end

  test "does not enable 2fa for the organization if it already requires it" do
    @organization2.enable_two_factor_required(actor: @organization2.admins.first)

    assert_no_enqueued_jobs only: EnforceTwoFactorRequirementOnOrganizationJob do
      @business.enable_two_factor_required(actor: @admin, force: true)
      create :business_organization_membership, business: @business, organization: @organization2
    end
  end

  test "enables 2fa for an organization when updating a membership record" do
    @organization2.enable_two_factor_required(actor: @organization2.admins.first)
    @business.enable_two_factor_required(actor: @admin, force: true)

    org_membership = create :business_organization_membership, business: @business, organization: @organization2

    org3 = create(:organization, admins: [create(:two_factor_credential_user)])

    assert_enqueued_with(
      job: EnforceTwoFactorRequirementOnOrganizationJob,
      args: [org3, org3, { disallowed_methods: [] }]) do
      org_membership.organization = org3
      org_membership.save
    end
  end

  unless GitHub.single_business_environment?
    test "enables 2fa for an organization when moving it into a business that requires 2fa" do
      business2 = create :business, owners: [@admin]
      business2.enable_two_factor_required(actor: @admin, force: true)

      assert_enqueued_with(
        job: EnforceTwoFactorRequirementOnOrganizationJob,
        args: [@org_membership.organization, @org_membership.organization, { disallowed_methods: [] }]) do
        @org_membership.business = business2
        @org_membership.save
      end
    end

    test "enables 2fa secure methods for an organization when moving it into a business that requires 2fa secure methods" do
      GitHub.flipper[:two_factor_cap_enforcement].enable
      GitHub.flipper[:members_without_2fa_allowed].enable
      GitHub.flipper[:disallow_two_factor_methods].enable
      business2 = create :business, owners: [@admin]
      business2.enable_two_factor_required(actor: @admin, force: true)
      business2.disallow_insecure_two_factor_methods(actor: @admin)

      assert_enqueued_with(
        job: EnforceTwoFactorRequirementOnOrganizationJob,
        args: [@org_membership.organization, @org_membership.organization, { disallowed_methods: [] }]) do
        @org_membership.business = business2
        @org_membership.save
      end
    end

    test "does not enable 2fa secure methods for an organization when moving it into a business that does not require 2fa secure methods" do
      GitHub.flipper[:two_factor_cap_enforcement].enable
      GitHub.flipper[:members_without_2fa_allowed].enable
      GitHub.flipper[:disallow_two_factor_methods].enable
      business2 = create :business, owners: [@admin]
      business2.enable_two_factor_required(actor: @admin, force: true)

      assert_enqueued_with(
        job: EnforceTwoFactorRequirementOnOrganizationJob,
        args: [@org_membership.organization, @org_membership.organization, { disallowed_methods: [] }]) do
        @org_membership.business = business2
        @org_membership.save
      end
    end

    test "does not enable 2fa when moving org between two business which both require 2fa" do
      @organization2.enable_two_factor_required(actor: @organization2.admins.first)
      @business.enable_two_factor_required(actor: @admin, force: true)

      org_membership = create :business_organization_membership, business: @business, organization: @organization2

      business2 = create :business, owners: [@admin]
      business2.enable_two_factor_required(actor: @admin, force: true)

      assert_no_enqueued_jobs only: EnforceTwoFactorRequirementOnOrganizationJob do
        org_membership.business = business2
        org_membership.save
      end
    end
  end

  test "preserves 2fa settings when org membership is destroyed" do
    @business.enable_two_factor_required(actor: @admin, force: true)
    assert @organization.two_factor_requirement_enabled?

    @organization.expects(:sync_two_factor_requirement).never

    @org_membership.destroy

    assert @organization.reload.two_factor_requirement_enabled?
  end

  test "preserves configuration entries mapping to business policies when an org membership is destroyed" do
    @business.enable_two_factor_required(actor: @admin, force: true)
    @business.disallow_team_discussions(true, actor: @admin)
    @business.disable_deploy_key_policy(actor: @admin)
    business_policy_names = ["two_factor.required", "team_discussions.disable", Configurable::DeployKeyPolicy::KEY]
    if GitHub.flipper[:actions_default_workflow_permissions_new_repos].enabled?
      # Default workflow permissions are final and set by default on businesses and organizations
      @organization.set_default_workflow_permissions("write", @admin)
      business_policy_names << Configurable::DefaultWorkflowPermissions::KEY
    end

    assert_same_elements business_policy_names, @business.configuration_entries.select(&:final?).map(&:name)
    assert_same_elements [], @organization.configuration_entries.where(name: business_policy_names).map(&:name)

    @business.remove_organization(@organization)

    assert_same_elements business_policy_names, @organization.reload.configuration_entries.where(name: business_policy_names).map(&:name)
  end

  test "does not preserve configuration entries that don't apply to orgs when an org membership is destroyed" do
    @business.enterprise_admins_only_can_invite_outside_collaborators(actor: @admin)
    @business.disable_deploy_key_policy(actor: @admin)
    business_policy_names = ["disable_members_can_invite_outside_collaborators", Configurable::DeployKeyPolicy::KEY]

    if GitHub.flipper[:actions_default_workflow_permissions_new_repos].enabled?
      # Default workflow permissions are final and set by default on businesses and organizations
      @organization.set_default_workflow_permissions("write", @admin)
      business_policy_names << Configurable::DefaultWorkflowPermissions::KEY
    end

    assert_same_elements business_policy_names, @business.configuration_entries.select(&:final?).map(&:name)
    assert_same_elements [], @organization.configuration_entries.where(name: business_policy_names).map(&:name)
    assert @organization.enterprise_admins_only_can_invite_outside_collaborators?

    @business.remove_organization(@organization)
    org_policies = [Configurable::DeployKeyPolicy::KEY]
    org_policies << Configurable::DefaultWorkflowPermissions::KEY if GitHub.flipper[:actions_default_workflow_permissions_new_repos].enabled?
    if GitHub.flipper[:actions_default_workflow_permissions_new_repos].enabled?
      assert_same_elements org_policies, @organization.reload.configuration_entries.where(name: business_policy_names).map(&:name)
    else
      assert_same_elements org_policies, @organization.reload.configuration_entries.where(name: business_policy_names).map(&:name)
    end
    assert @organization.members_can_invite_outside_collaborators?
  end

  context "creation" do
    if GitHub.single_business_environment?
      test "does not schedule BusinessUserAccountCreateForOrganizationJob for single business environment" do
        Business.delete_all
        business = create :business
        org = create :organization, plan: GitHub::Plan.business_plus, seats: 10
        org.add_member(@member)

        assert_no_enqueued_jobs only: BusinessUserAccountCreateForOrganizationJob do
          business.add_organization(org)
        end
      end

      test "does not create business user accounts for single business environment" do
        Business.delete_all
        business = create :business
        org = create :organization, plan: GitHub::Plan.business_plus, seats: 10
        org.add_member(@member)

        business.add_organization(org)
        assert_equal 0, business.user_accounts.count
      end
    else
      test "enqueues BusinessUserAccountCreateForOrganizationJob when required" do
        business = create :business
        org = create :organization, plan: GitHub::Plan.business_plus, seats: 10
        org.add_member(@member)

        org = create :organization
        ids = Organization::LicenseAttributer.new(org).user_ids.to_a

        assert_enqueued_with(
          job: BusinessUserAccountCreateForOrganizationJob,
          args: [business, org]) do
          business.add_organization(org)
        end
      end

      test "creates business user accounts for unique users who are not already in the business" do
        business = create :business
        org = create :organization, plan: GitHub::Plan.business_plus, seats: 10
        org.add_member(@member)
        assert_equal 1, business.user_accounts.count

        perform_enqueued_jobs(only: [BusinessUserAccountCreateForOrganizationJob]) { business.add_organization(org) }
        assert_equal 3, business.user_accounts.count
      end

      test "does not enqueue BusinessUserAccountCreateForOrganizationJob when organization_upgrade is true" do
        business = create :business
        org = create :organization, plan: GitHub::Plan.business_plus, seats: 10
        org.add_member(@member)

        org = create :organization

        assert_no_enqueued_jobs only: BusinessUserAccountCreateForOrganizationJob do
          business.add_organization(org, organization_upgrade: true)
        end
      end
    end
  end

  context "#business_members_cleanup" do
    if GitHub.single_business_environment?
      test "does not remove business user accounts for single business environment" do
        @business.add_organization @organization
        assert_equal 0, @business.user_accounts.count

        @business.remove_organization @organization
        assert_equal 0, @business.user_accounts.count
      end
    else
      test "enqueues BusinessMembershipCleanupJob job to clean up business membership" do
        @business.add_organization @organization
        @business.remove_organization @organization

        assert_enqueued_jobs 1, only: BusinessMembershipCleanupJob
      end

      test "removes members of the organization who are not members of any other organization in the business" do
        GitHub.flipper[:unaffiliated_user_accounts].disable
        GitHub.flipper[:enterprise_teams_migrate_from_cfb].disable
        @business.add_organization @organization
        assert_equal 3, @business.user_accounts.count

        perform_enqueued_jobs(only: [BusinessMembershipCleanupJob]) do
          @business.remove_organization @organization
        end
        assert_equal 1, @business.user_accounts.count
      end

      test "does not remove members of the organization who are not members of any other organization in the business when unaffiliated user account support is enabled" do
        GitHub.flipper[:unaffiliated_user_accounts].enable
        @business.add_organization @organization
        assert_equal 3, @business.user_accounts.count

        perform_enqueued_jobs(only: [BusinessMembershipCleanupJob]) do
          @business.remove_organization @organization
        end
        assert_equal 3, @business.user_accounts.count
      end

      test "does not remove business user accounts of members that are business administrators" do
        billing_manager = create :two_factor_credential_user
        @business.billing.add_manager billing_manager, actor: @admin
        @organization.add_member @admin
        @organization.add_member billing_manager

        expected_members = [*@organization.admins, @member, @admin, billing_manager]
        assert_same_elements expected_members.map(&:id), @business.user_accounts.pluck(:user_id)

        perform_enqueued_jobs(only: [BusinessMembershipCleanupJob]) do
          @business.remove_organization @organization
        end

        if GitHub.flipper[:unaffiliated_user_accounts].enabled?
          assert_same_elements expected_members.map(&:id), @business.user_accounts.pluck(:user_id)
        else
          expected_members = [@admin, billing_manager]
          assert_same_elements expected_members.map(&:id), @business.user_accounts.pluck(:user_id)
        end
      end
    end
  end

  context "verified domains" do
    # Organizations can not be removed from the business in a single business environment
    unless GitHub.single_business_environment?
      test "disables notification restrictions if domains are owned by enterprise" do
        @business_domain = create(:verifiable_domain, owner: @business, verified: true)
        @business.add_organization @organization
        assert @organization.enable_notification_restrictions(actor: @organization.admin)

        @business.remove_organization @organization
        refute @organization.reload.restrict_notifications_to_verified_domains?
      end

      test "disables notification restrictions if a domain is owned by organization" do
        @business_domain = create(:verifiable_domain, owner: @business, verified: true)
        @org_domain = create(:verifiable_domain, owner: @organization, verified: true)
        @business.add_organization @organization
        assert @business.enable_notification_restrictions(actor: @admin, force: true)
        assert @organization.restrict_notifications_to_verified_domains_policy?

        @business.remove_organization @organization
        refute @organization.reload.restrict_notifications_to_verified_domains?
        refute @organization.restrict_notifications_to_verified_domains_policy?
      end

      test "disables notification restrictions if domains are owned by organization" do
        @org_domain = create(:verifiable_domain, owner: @organization, verified: true)
        @business.add_organization @organization
        assert @organization.enable_notification_restrictions(actor: @organization.admin)
        refute @organization.restrict_notifications_to_verified_domains_policy?

        @business.remove_organization @organization
        refute @organization.reload.restrict_notifications_to_verified_domains?
        refute @organization.restrict_notifications_to_verified_domains_policy?
      end

      test "disables notification restrictions if enabled by enterprise and all domains are owned by enterprise" do
        @business_domain = create(:verifiable_domain, owner: @business, verified: true)
        @business.add_organization @organization
        assert @business.enable_notification_restrictions(actor: @admin, force: true)
        assert @organization.restrict_notifications_to_verified_domains_policy?

        @business.remove_organization @organization
        refute @organization.reload.restrict_notifications_to_verified_domains?
        refute @organization.restrict_notifications_to_verified_domains_policy?
      end
    end
  end

  context "licensing" do
    include HydroTestHelpers

    test "publishes license snapshot messages when an organization is added" do
      organization = create(:organization)

      reset_hydro # clear any messages that were sent during setup

      perform_enqueued_jobs only: [BusinessUserAccountCreateForOrganizationJob, Licensing::SnapshotLicensesJob, BusinessOrganizationBillingJob] do
        @business.add_organization(organization)
      end

      assert_hydro_messages(count: 1, schema: "github.billing.v0.LicenseSnapshot")
    end
  end if GitHub.billing_enabled?

  test "enqueues a job to detach the organization's customer if the organization", skip_enterprise: true do
    business = create(:business)
    organization = create(:organization)
    business.add_organization(organization)
    actor = organization.admins.first

    assert_enqueued_with(
      job: Billing::DetachOrganizationFromBusinessCustomerJob,
      args: [business, organization, { actor: actor }]
    ) do
      business.reload.remove_organization(organization, actor: actor)
    end
  end
end

class EmuBusinessOrganizationMembershipTest < GitHub::TestCase
  fixtures do
    @emu = create :emu
    @emu_business = @emu.enterprise_managed_business
    @emu_org = create :enterprise_linked_organization, business: @emu_business, admin: @emu
  end

  test "does not remove business user accounts for enterprise managed businesses when organization is deleted" do
    assert_equal 2, @emu_business.user_accounts.count # emu and implicit admin

    refute_nil Organization.find(@emu_org.id)

    assert_difference ["Business::OrganizationMembership.count", "Organization.count"], -1 do
      perform_enqueued_jobs only: [UserDeleteJob] do
        @emu_org.async_destroy
      end
    end

    assert_raises ActiveRecord::RecordNotFound do
      Organization.find(@emu_org.id)
    end

    assert_equal 2, @emu_business.user_accounts.count
  end
end unless GitHub.single_business_environment?
