# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessOrganizationsTest < GitHub::TestCase
  include GitHub::DatabaseQueryWarningsTestHelpers
  include GitHub::ZuoraTestHelper
  include AuditLog::IntegrationTestHelpers
  include HydroTestHelpers
  include TurboghasHelpers

  fixtures do
    @owner = create :user
    @user = create :user, login: "user"
    @member1 = create(:user, :verified, login: "member1")
    @billing_manager = create :user, login: "billing-manager"
    @org1 = create :organization, plan: GitHub::Plan.business_plus, seats: 10
    @org1.add_member(@member1)
    @org2 = create :organization, plan: GitHub::Plan.business_plus, seats: 10

    only = [SyncBusinessOrganizationBillingSettingsJob, BusinessOrganizationBillingJob]
    @business = perform_enqueued_jobs only: only do
      create :business, :with_valid_contact_for_billing, name: "CDE Ltd", owners: [@owner], organizations: [@org1, @org2], seats: 20
    end
    @business.billing.add_manager(@billing_manager, actor: @owner)

    unless GitHub.single_business_environment?
      @deletable_business = create :business, owners: [@owner]
      @enterprise_managed_business = \
        create :business, business_type: :enterprise_managed, shortcode: "qqq"
      @another_business = create :business, name: "ANO Ltd"
      @upgrading_org = create :organization, name: "upgrading-org", plan: "business", admins: [@owner]
      @upgrading_business = perform_enqueued_jobs only: only do
        create :business, name: "Business to upgrade", owners: [@owner], upgrade_initiated_from_organization_id: @upgrading_org.id
      end
      @upgrading_business.customer.update(billing_type: ::Customer::BILLING_TYPE_CARD)
      @upgrading_org.upgrade_to_enterprise_in_progress!(@upgrading_business)
    end
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  context "#organizations" do
    test "through memberhip records are destroyed when the business is" do
      membership_ids = @business.organization_membership_ids

      @business.destroy

      refute Business::OrganizationMembership.exists?(id: membership_ids)
    end

    test "are not destroyed when the business is" do
      organization_ids = @business.organization_ids

      @business.destroy

      assert_same_elements [@org1, @org2], Organization.find(organization_ids)
    end

    if GitHub.single_business_environment?
      test "returns all orgs except the trusted oauth apps org" do
        org = Organization.create_trusted_oauth_apps_owner
        @business.add_organization(org)
        @business.reload
        refute @business.organizations.include?(org)
      end
    end
  end

  context "#filtered_organizations" do
    test "loads all member organizations by default" do
      assert_same_elements \
        [@org1, @org2],
        @business.filtered_organizations.to_a
    end

    test "orders organizations by login ascending by default" do
      @org2.update login: "aaaaaaaaaaaaaaaaaa"
      @org1.update login: "zzzzzzzzzzzzzzzzzz"

      assert_equal \
        [@org2, @org1],
        @business.filtered_organizations.to_a
    end

    test "orders organizations when order provided" do
      @org2.update login: "aaaaaaaaaaaaaaaaaa"
      @org1.update login: "zzzzzzzzzzzzzzzzzz"

      assert_equal \
        [@org1, @org2],
        @business.filtered_organizations(
          order_by_field: "login",
          order_by_direction: "DESC",
        ).to_a
    end

    test "ignores invalid ordering arguments" do
      @org2.update login: "aaaaaaaaaaaaaaaaaa"
      @org1.update login: "zzzzzzzzzzzzzzzzzz"

      assert_equal \
        [@org2, @org1],
        @business.filtered_organizations(
          order_by_field: "invalid field",
          order_by_direction: "invalid direction",
        ).to_a
    end

    test "queries for organizations by login" do
      @org2.update login: "very-fancy-login"
      @org1.update login: "nothing-to-see-here"

      assert_same_elements \
        [@org2],
        @business.filtered_organizations(query: "very-fancy").to_a
    end

    test "queries for orgs by profile name" do
      @org2.update profile_name: "So fancy"
      @org1.update profile_name: "Nothing to see here"

      assert_same_elements \
        [@org2],
        @business.filtered_organizations(query: "So fancy").to_a
    end

    test "returns an empty result when query doesn't match any organizations" do
      @org2.update login: "aaaaaaaaaaaaaaaaa"
      @org1.update login: "xxxxxxxxxxxxxxxxx"

      assert_empty @business.filtered_organizations(query: "find nothing").to_a
    end

    test "returns organizations where 2FA can be enabled when can_enable_two_factor provided" do
      org_admin_with_two_factor = create :two_factor_credential_user
      two_factor_org = create :organization, login: "two-factor-org", admin: org_admin_with_two_factor
      @business.add_organization two_factor_org

      assert_same_elements \
        [two_factor_org],
        @business.filtered_organizations(can_enable_two_factor: true).to_a
    end

    test "returns organizations with team sync enabled" do
      team_sync_tenant = create :team_sync_tenant
      org_with_team_sync = team_sync_tenant.organization
      @business.add_organization org_with_team_sync

      assert_same_elements \
        [org_with_team_sync],
        @business.filtered_organizations(team_sync_statuses: :enabled).to_a
    end

    test "returns organizations with team sync disabled" do
      team_sync_tenant = create :team_sync_tenant
      org_with_team_sync = team_sync_tenant.organization
      @business.add_organization org_with_team_sync

      disabled_team_sync_tenant = create :team_sync_tenant, status: :disabled
      org_with_team_sync_disabled = disabled_team_sync_tenant.organization
      @business.add_organization org_with_team_sync_disabled

      assert_same_elements \
        [org_with_team_sync_disabled],
        @business.filtered_organizations(team_sync_statuses: :disabled).to_a
    end

    test "returns organizations where 2FA can be enabled and where team sync is enabled" do
      org_admin_with_two_factor = create :two_factor_credential_user
      team_sync_tenant = create :team_sync_tenant
      org = team_sync_tenant.organization
      org.add_member org_admin_with_two_factor, action: :admin
      @business.add_organization org

      assert_same_elements \
        [org],
        @business.filtered_organizations(
          can_enable_two_factor: true,
          team_sync_statuses: :enabled,
        ).to_a
    end

    test "returns matching orgs when viewer present and viewer_role is owner" do
      @org2.add_admin @member1
      orgs = @business.filtered_organizations(
        viewer: @member1,
        viewer_role: "owner"
      ).to_a

      assert_same_elements [@org2], orgs
    end

    test "returns matching orgs when viewer present and viewer_role is member" do
      @org2.add_admin @member1
      orgs = @business.filtered_organizations(
        viewer: @member1,
        viewer_role: "member"
      ).to_a

      assert_same_elements [@org1], orgs
    end

    test "returns matching orgs when viewer present and viewer_role is unaffiliated" do
      orgs = @business.filtered_organizations(
        viewer: @member1,
        viewer_role: "unaffiliated"
      ).to_a

      assert_same_elements [@org2], orgs
    end

    test "returns all orgs when viewer present and viewer_role is unsupported" do
      orgs = @business.filtered_organizations(
        viewer: @member1,
        viewer_role: "unsupported role"
      ).to_a

      assert_same_elements [@org1, @org2], orgs
    end

    test "returns only soft deleted org when passed as argument", skip_enterprise: true do
      @org2.soft_delete!

      assert_predicate @org2, :soft_deleted?

      orgs = @business.filtered_organizations(only_deleted: true).to_a

      assert_same_elements [@org2], orgs
    end

    test "returns only orgs with deploy keys when has_deploy_keys is true" do
      repo = create(:repository, owner: @org1)
      create(:public_key, repository: repo)
      orgs = @business.filtered_organizations(
        has_deploy_keys: true,
      ).to_a
      assert_same_elements [@org1], orgs
    end

    test "returns only orgs without deploy keys when has_deploy_keys is false" do
      repo = create(:repository, owner: @org1)
      create(:public_key, repository: repo)
      orgs = @business.filtered_organizations(
        has_deploy_keys: false,
      ).to_a
      assert_same_elements [@org2], orgs
    end

    test "returns all orgs regardless of deploy keys when has_deploy_keys is nil" do
      repo = create(:repository, owner: @org1)
      create(:public_key, repository: repo)
      orgs = @business.filtered_organizations(
        has_deploy_keys: nil,
      ).to_a
      assert_same_elements [@org1, @org2], orgs
    end
  end

  context "#orphaned_organizations" do
    test "can find any orphaned organizations in this business" do
      GitHub.flipper[:enterprise_idp_provisioning].enable(@business)
      create(:business_saml_provider, :full_user_provisioning, business: @business)
      @business.reload

      @org1.admins.each do |admin|
        @org1.remove_member!(admin, allow_last_admin_removal: true)
      end

      assert_same_elements [@org1], @business.orphaned_organizations
    end

    test "finds an orphaned organization which shares id with another abilities entry" do
      new_id = [Business.maximum(:id).to_i, User.maximum(:id).to_i].max + 5000
      org = create(:organization, id: new_id)
      business = create(:business, organizations: [org], id: new_id)
      assert_equal business.id, org.id

      GitHub.flipper[:enterprise_idp_provisioning].enable(business)
      create(:business_saml_provider, :full_user_provisioning, business: business)
      business.reload

      org.reload.admins.each do |admin|
        org.remove_member!(admin, allow_last_admin_removal: true)
      end

      refute Ability.where(subject_id: org.id,
        actor_type: "User", action: "admin").empty?
      assert Ability.where(subject_id: org.id, subject_type: "Organization",
        actor_type: "User", action: "admin").empty?

      assert_same_elements [org], business.orphaned_organizations
    end

    test "orders results by login ascending by default" do
      GitHub.flipper[:enterprise_idp_provisioning].enable(@business)
      create(:business_saml_provider, :full_user_provisioning, business: @business)
      @business.reload

      @org1.update(login: "aaaa")
      @org2.update(login: "ffff")
      @business.organizations.each do |org|
        org.admins.each do |admin|
          org.remove_member!(admin, allow_last_admin_removal: true)
        end
      end

      assert_equal [@org1, @org2], @business.orphaned_organizations.to_a
    end

    test "can sort results" do
      GitHub.flipper[:enterprise_idp_provisioning].enable(@business)
      create(:business_saml_provider, :full_user_provisioning, business: @business)
      @business.reload

      @org1.update(login: "aaaa")
      @org2.update(login: "ffff")
      @business.organizations.each do |org|
        org.admins.each do |admin|
          org.remove_member!(admin, allow_last_admin_removal: true)
        end
      end

      expected_results = [@org2, @org1]
      assert_equal expected_results,
                   @business.orphaned_organizations(order_by_field: "login",
                                                    order_by_direction: "DESC").to_a
    end

    test "ignores invalid ordering arguments" do
      GitHub.flipper[:enterprise_idp_provisioning].enable(@business)
      create(:business_saml_provider, :full_user_provisioning, business: @business)
      @business.reload

      @org1.update(login: "aaaa")
      @org2.update(login: "ffff")
      @business.organizations.each do |org|
        org.admins.each do |admin|
          org.remove_member!(admin, allow_last_admin_removal: true)
        end
      end

      assert_equal \
        [@org1, @org2],
        @business.orphaned_organizations(
          order_by_field: "invalid field",
          order_by_direction: "invalid direction"
        ).to_a
    end
  end unless GitHub.single_business_environment?

  context "#organizations_hash" do
    test "returns a hash of organizations using id for key and login for value" do
      new_org = create(:organization)
      @business.add_organization(new_org)
      expected_results = {
        @org1.id => @org1.login,
        @org2.id => @org2.login,
        new_org.id => new_org.login
      }
      assert_same_hash expected_results, @business.organizations_hash
    end

    test "can use different fields for keys and values" do
      expected_results = {
        @org1.login => @org1.billing_email,
        @org2.login => @org2.billing_email
      }
      assert_same_hash expected_results,
        @business.organizations_hash(key_field: :login, value_field: :billing_email)
    end

    test "memoizes the results" do
      expected_results = {
        @org1.id => @org1.login,
        @org2.id => @org2.login
      }
      assert_same_hash expected_results, @business.organizations_hash

      new_org = create(:organization)
      @business.add_organization(new_org)
      assert_same_hash expected_results, @business.reload.organizations_hash

      reloaded_business = Business.find_by(id: @business.id)
      updated_results = expected_results.dup
      updated_results[new_org.id] = new_org.login
      assert_same_hash updated_results, T.must(reloaded_business).organizations_hash
    end
  end

  context "#enterprise_created_organizations" do
    test "does not include organization invited to the business" do
      invited_org = create :organization
      create :business_organization_invitation, business: @business, invitee: invited_org, confirmed_at: Time.current
      @business.add_organization(invited_org)

      @business.reload
      assert_includes @business.organizations, invited_org
      refute_includes @business.enterprise_created_organizations, invited_org
    end

    test "does not include organization used to upgrade the business" do
      upgraded_from_org = create :organization
      @business.add_organization(upgraded_from_org)
      @business.update upgraded_from: upgraded_from_org

      @business.reload
      assert_includes @business.organizations, upgraded_from_org
      refute_includes @business.enterprise_created_organizations, upgraded_from_org
    end

    test "includes organization created from the business" do
      assert_includes @business.organizations, @org1
      assert_includes @business.enterprise_created_organizations, @org1
    end
  end

  context "#organization?" do
    test "returns false for Business instances" do
      refute_predicate @business, :organization?
    end
  end

  context "::from_org_id" do
    test "finds business given org id" do
      assert_equal @business, Business.from_org_id(@org1.id)
    end

    test "returns nil when not found" do
      assert_nil Business.from_org_id(@user.id)
    end
  end

  context "#organizations_blocking_deletion?" do
    test "returns true when enterprise has member orgs" do
      assert_predicate @business.organization_ids, :any?
      assert_predicate @business, :organizations_blocking_deletion?
    end

    test "returns false when enterprise has no member orgs", skip_enterprise: true do
      assert_predicate @deletable_business.organization_ids, :empty?
      refute_predicate @deletable_business, :organizations_blocking_deletion?
    end
  end

  context "#add_organization" do
    test "raises ArgumentError unless an org is passed" do
      assert_raises ArgumentError do
        @business.add_organization @user
      end
    end

    test "returns valid membership if organization belongs to business" do
      membership = @business.add_organization(@org1)
      assert membership.valid?
      assert_includes @business.organizations, @org1
    end

    test "returns valid membership if organization is added" do
      org = create :organization
      membership = @business.add_organization(org)
      assert membership.valid?
      assert_includes @business.organizations.reload, org
    end

    test "instruments organization_add hydro event" do
      reset_hydro # clear any messages that were sent during setup

      membership = @business.add_organization(@org1, actor: @owner)

      assert_hydro_published({
        enterprise: Hydro::EntitySerializer.business(@business),
        organization: Hydro::EntitySerializer.organization(@org1),
        actor: Hydro::EntitySerializer.user(@owner),
        enterprise_trial: false,
        new_organization: false,
        previous_plan: "business_plus"
      }, schema: "github.enterprise_account.v0.OrganizationAdd")
    end

    unless GitHub.single_business_environment?
      test "returns valid membership if business contains name with emoji" do
        assert_no_query_warnings do
          @business.update! name: "Much #{GRIN_EMOJI}"
          org = create :organization
          membership = @business.add_organization(org)
          assert membership.valid?
          assert_includes @business.organizations.reload, org
        end
      end

      test "updates the number of billable users" do
        org = create :organization

        perform_enqueued_jobs(only: [BusinessUserAccountCreateForOrganizationJob, BusinessUpdateLicenseUsageJob]) do
          # Need to load a fresh business to avoid stale memoization
          assert_difference -> { Business.find(@business.id).consumed_invitable_licenses } do
            @business.add_organization(org)
          end
        end
      end

      test "overallocation is not allowed by default" do
        create(:enterprise_agreement, business: @business, seats: 0)
        # Set the business to have exactly enough seats, but not enough to add a new organization
        @business.update(seats: @business.consumed_invitable_licenses)

        user = create(:user)
        organization = create(:organization, admins: [user])

        membership = @business.add_organization(organization)

        refute membership.persisted?
      end

      test "allows org creation by a license-consuming org admin when licenses are overallocated" do
        create(:enterprise_agreement, business: @business, seats: 0)
        # Set business owner as an organization member, thus consuming a license
        @org1.add_member(@owner)
        @business.update(seats: @business.consumed_invitable_licenses)
        organization = create(:organization, admins: [@owner])

        membership = @business.add_organization(organization)

        assert membership.persisted?
      end

      test "allows using volume licenses", skip_enterprise: true do
        create(:enterprise_agreement, business: @business, seats: 100)
        # Set the business to have exactly enough seats, but not enough to add a new organization
        @business.update(seats: @business.consumed_invitable_licenses)

        user = create(:user)
        organization = create(:organization, admins: [user])

        membership = @business.add_organization(organization)

        assert membership.persisted?
      end

      test "triggers team sync setup job for the org if the business team_sync is enabled and membership is valid" do
        create :business_team_sync_tenant, business: @business, status: "enabled"
        org = create(:organization)

        assert_enqueued_jobs 1, only: UpdateTeamSyncForBusinessOrganizationJob do
          assert_enqueued_with args: [{ org_id: org.id }], job: UpdateTeamSyncForBusinessOrganizationJob do
            @business.add_organization(org)
          end
        end
      end

      test "does not trigger team sync setup job for the org if the business does not have team sync enabled" do
        create :business_team_sync_tenant, business: @business, status: "disabled"
        org = create(:organization)

        assert_enqueued_jobs 0, only: UpdateTeamSyncForBusinessOrganizationJob do
          @business.add_organization(org)
        end
      end

      test "deletes org custom properties which name conflicts with target business" do
        GitHub.flipper[:enterprise_custom_properties].enable

        org = create :organization
        repo = create :repository, owner: org
        orgprop = create :custom_property_definition, source: org, property_name: "same_name"
        orgprop_value = create :custom_property_value, target: repo, definition: orgprop, value: "value"

        bizprop = create :custom_property_definition, source: @business, property_name: "same_name"

        perform_enqueued_jobs(only: [DeleteConflictCustomPropertyDefinitionsJob]) do
          @business.add_organization(org)
        end

        assert_raises(ActiveRecord::RecordNotFound) { orgprop.reload }
        assert_raises(ActiveRecord::RecordNotFound) { orgprop_value.reload }
      end

      test "does not trigger team sync setup job for the org if membership is not valid" do
        create(:enterprise_agreement, business: @business, seats: 0)
        create :business_team_sync_tenant, business: @business, status: "enabled"
        # Set the business to have exactly enough seats so that membership for added organization fails
        @business.update(seats: @business.consumed_invitable_licenses)

        user = create(:user)
        organization = create(:organization, admins: [user])

        assert_no_enqueued_jobs only: UpdateTeamSyncForBusinessOrganizationJob do
          @business.add_organization(organization)
        end
      end
    end
  end

  if GitHub.billing_enabled?
    context "organization billing settings" do
      test "syncs billing settings when the organization is added" do
        initial_org = create :organization,
          seats: 10,
          plan: GitHub::Plan.business,
          billed_on: GitHub::Billing.today - 1.day
        refute_predicate initial_org, :invoiced?

        added_org = create :organization,
          seats: 10,
          plan: GitHub::Plan.business,
          billed_on: GitHub::Billing.today - 1.day
        refute_predicate added_org, :invoiced?

        only = [BusinessOrganizationBillingJob]
        business = perform_enqueued_jobs(only: only) do
          create :business,
            organizations: [initial_org],
            seats: 20,
            terms_of_service_type: "Custom",
            terms_of_service_company_name: "Acme, Inc",
            customer_attributes: {
              billing_end_date: 30.days.from_now,
            }
        end

        perform_enqueued_jobs(only: [BusinessOrganizationBillingJob]) do
          business.add_organization(added_org)
        end

        [initial_org, added_org].each do |org|
          assert_predicate org.reload, :invoiced?
          assert_equal GitHub::Plan.business_plus, org.plan
          assert_equal 20, org.seats
          assert_equal business.billed_on, org.billed_on
          assert_predicate org.terms_of_service, :custom?
        end
      end

      test "tracks billing settings changes when organization is added in the audit log" do
        added_org = create :organization,
          seats: 5,
          plan: GitHub::Plan.business,
          billed_on: GitHub::Billing.today - 1.day

        events = assert_performed_audit_entries(count: 2, only: "account.plan_change") do
          perform_enqueued_jobs(only: [BusinessOrganizationBillingJob]) do
            @business.add_organization(added_org)
          end
        end
        assert_equal last_performed_audit_entries, events

        seat_change_payload = {
          org: added_org.to_s,
          old_seats: 5,
          seats: 20,
          reason: "Synced with parent business billing settings",
        }
        assert seat_change_event = events.pop
        assert_equal seat_change_payload, seat_change_event.slice(:old_seats, :seats, :org, :reason)

        plan_change_payload = {
          org: added_org.to_s,
          old_plan: GitHub::Plan.business.name,
          plan: GitHub::Plan.business_plus.name,
          reason: "Synced with parent business billing settings",
        }
        assert plan_change_event = events.pop
        assert_equal plan_change_payload, plan_change_event.slice(:old_plan, :plan, :org, :reason)
      end

      test "tracks billing settings changes when organization is added in the billing transaction log" do
        added_org = create :organization,
          seats: 5,
          plan: GitHub::Plan.business,
          billed_on: GitHub::Billing.today - 1.day

        assert_difference "added_org.transactions.count", 2 do
          perform_enqueued_jobs only: BusinessOrganizationBillingJob do
            @business.add_organization(added_org)
          end
        end

        transactions = added_org.transactions.last(2)
        assert plan_change = transactions.find { |t| t.old_plan? }
        assert_equal GitHub::Plan.business, plan_change.old_plan
        assert_equal @business.plan, plan_change.current_plan

        assert seat_change = transactions.find { |t| t.old_seats? }
        assert_equal 5, seat_change.old_seats
        assert_equal 20, seat_change.current_seats
      end

      test "tracks seat changes on the organization when business is updated in the audit log" do
        events = assert_performed_audit_entries(count: 2, only: "account.plan_change") do
          perform_enqueued_jobs only: SyncBusinessOrganizationBillingSettingsJob do
            @business.update! seats: 42
          end
        end
        assert_equal last_performed_audit_entries, events

        seat_change_payload = {
          old_seats: 20,
          seats: 42,
          reason: "Synced with parent business billing settings",
        }
        assert seat_change_event = events.pop
        assert_equal seat_change_payload, seat_change_event.slice(:old_seats, :seats, :reason)
        assert_includes [@org1.login, @org2.login], seat_change_event[:org]
      end

      test "tracks seat changes on the organization when business is updated in the billing transaction log" do
        perform_enqueued_jobs only: SyncBusinessOrganizationBillingSettingsJob do
          assert_difference "@org1.transactions.count" do
            @business.update! seats: 42
          end
        end

        seat_change = @org1.transactions.last
        assert_equal 20, seat_change.old_seats
        assert_equal 42, seat_change.current_seats
      end

      test "updates terms of service data for orgs when it's updated" do
        perform_enqueued_jobs only: SyncBusinessOrganizationBillingSettingsJob do
          @business.update! \
            terms_of_service_type: "Custom",
            terms_of_service_company_name: "Acme, Inc"
        end

        assert_equal "Custom", @business.terms_of_service_type
        assert_equal "Acme, Inc", @business.terms_of_service_company_name
        @business.organizations.each do |org|
          assert_predicate org.terms_of_service, :custom?
          assert_equal "Acme, Inc", org.company.name
        end
      end

      test "keeps seats in sync" do
        perform_enqueued_jobs only: SyncBusinessOrganizationBillingSettingsJob do
          @business.update seats: 42
        end

        @business.organizations.each do |org|
          assert_equal 42, org.reload.seats
        end
      end

      test "keeps billed_on date in sync" do
        perform_enqueued_jobs only: SyncBusinessOrganizationBillingSettingsJob do
          @business.update billing_term_ends_at: 1.week.from_now
        end

        @business.organizations.each do |org|
          assert_equal @business.billed_on, org.reload.billed_on
        end
      end
    end
  end

  context "#actor_can_transfer_organizations?" do
    if GitHub.single_business_environment?
      test "returns false in single business environment" do
        refute @business.actor_can_transfer_organizations?(actor: @business.owners.first)
      end
    else
      test "returns false for an externally managed business" do
        assert_predicate @enterprise_managed_business, :enterprise_managed_user_enabled?
        refute @enterprise_managed_business.actor_can_transfer_organizations?(actor: @enterprise_managed_business.owners.first)
      end

      test "returns false for a spammy business" do
        @business.mark_as_spammy
        assert_predicate @business, :spammy?
        refute @business.actor_can_transfer_organizations?(actor: @business.owners.first)
      end

      test "returns false for a trial business" do
        @business.update! trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now
        assert_predicate @business, :trial?
        refute @business.actor_can_transfer_organizations?(actor: @business.owners.first)
      end

      test "returns false if actor is blank" do
        refute @business.actor_can_transfer_organizations?(actor: nil)
      end

      test "returns false for billing manager of eligible business" do
        refute @business.actor_can_transfer_organizations?(actor: @billing_manager)
      end

      test "returns true for owner of eligible business" do
        assert @business.actor_can_transfer_organizations?(actor: @business.owners.first)
      end
    end
  end

  context "#actor_can_remove_organizations?" do
    if GitHub.single_business_environment?
      test "returns false in single-business environment" do
        refute @business.actor_can_remove_organizations?(actor: @business.owners.first)
      end
    else
      test "returns false when actor is not present" do
        refute @business.actor_can_remove_organizations?(actor: nil)
      end

      test "returns false when actor is not a business owner" do
        refute @business.actor_can_remove_organizations?(actor: create(:user))
      end

      test "returns true when actor is business owner in multi-business environment" do
        assert @business.actor_can_remove_organizations?(actor: @business.owners.first)
      end

      test "returns true even when business can not self-serve" do
        @business.update! can_self_serve: false
        assert @business.actor_can_remove_organizations?(actor: @business.owners.first)
      end
    end
  end

  context "#remove_organization" do
    unless GitHub.single_business_environment?
      test "raises Business::OrganizationIsNotMemberError unless an org in the business is passed" do
        assert_raises Business::OrganizationIsNotMemberError do
          @business.remove_organization @user
        end
      end

      test "raises Business::OrganizationHasNoAdminsError if the org has no owners" do
        @org1.admins.delete_all
        assert_raises Business::OrganizationHasNoAdminsError do
          @business.remove_organization @org1
        end

        assert_includes @business.organizations.reload, @org1
      end

      test "raises CannotRemoveOrganizationError if business on trial and org was created in business" do
        GitHub.flipper[:cap_enterprise_in_trial_org_creation].disable
        @business.update! trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now

        assert_predicate @business, :trial?
        assert_raises Business::CannotRemoveOrganizationError do
          @business.remove_organization @org1
        end
      end

      test "successfully removes an organization" do
        org = create :organization
        @business.add_organization org
        assert_includes @business.organizations.reload, org

        @business.remove_organization org
        @business.reload
        refute_includes @business.organizations, org
      end

      test "successfully removes an organization if business on trial and org was transferred to business" do
        @business.update! trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now
        org = create :organization
        create :business_organization_invitation, business: @business, invitee: org, confirmed_at: Time.current
        @business.add_organization org
        @business.reload

        assert_predicate @business, :trial?
        @business.remove_organization org

        @business.reload
        refute_includes @business.organizations, org
      end

      test "disables SSH CA requirement when removing an organization from a business_plus enterprise" do
        ca = create(:ssh_certificate_authority, owner: @org1)
        @org1.enable_ssh_certificate_requirement(@org1)
        @org1.reload

        events = assert_performed_audit_entries(count: 1, only: "account.plan_change") do
          @business.remove_organization @org1, actor: @owner
        end
        assert_equal last_performed_audit_entries, events
        refute SshCertificateAuthority.eligible_for_feature?(@org1)

        expected_payload = {
          old_plan: GitHub::Plan::BUSINESS_PLUS,
          plan: GitHub::Plan::FREE,
          old_plan_duration: User::BillingDependency::YEARLY_PLAN,
          plan_duration: User::BillingDependency::MONTHLY_PLAN,
          actor: @owner.login,
          actor_id: @owner.id
        }
        assert_subset_hash expected_payload, events.first

        # verify the ssh certificate requirement is now disabled
        @org1.reload
        refute_predicate @org1, :ssh_certificate_requirement_enabled?
      end

      test "successfully removes an organization if business on trial and actor is staff" do
        @business.update! trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now
        staff = create :staff_admin_user

        assert_predicate @business, :trial?
        @business.remove_organization @org1, actor: staff

        @business.reload
        refute_includes @business.organizations, @org1
      end

      test "instruments organization_remove hydro event" do
        @business.add_organization @org1

        reset_hydro # clear any messages that were sent during setup
        @business.remove_organization @org1, actor: @owner

        assert_hydro_published({
          enterprise: Hydro::EntitySerializer.business(@business),
          organization: Hydro::EntitySerializer.organization(@org1.reload),
          actor: Hydro::EntitySerializer.user(@owner),
          enterprise_trial: false,
          new_plan: "free"
        }, schema: "github.enterprise_account.v0.OrganizationRemove")
      end

      if GitHub.team_synchronization_available?
        test "disables the org's tenant if org is removed and business has team sync enabled" do
          org_tenant = create :team_sync_tenant
          org_in_business = org_tenant.organization
          @business.add_organization org_in_business
          create :business_team_sync_tenant, business: @business
          assert org_in_business.team_sync_enabled?

          @business.remove_organization org_in_business
          org_in_business.reload
          refute org_in_business.team_sync_enabled?
        end

        test "removes an org without a team_sync_tenant even if team sync is enabled on the Business" do
          org = create :organization
          @business.add_organization org
          create :business_team_sync_tenant, business: @business
          refute_predicate org, :team_sync_enabled?
          assert_predicate @business, :team_sync_enabled?

          @business.remove_organization org

          refute_includes @business.organizations, org
        end
      end

      test "cleans up source_ip_disclosure config if present" do
        org = create :organization
        @business.add_organization org
        assert_includes @business.organizations.reload, org

        @business.enable_source_ip_disclosure(actor: @business.owners.first)
        assert @business.source_ip_disclosure_enabled?

        @business.remove_organization org
        org.reload
        refute org.source_ip_disclosure_enabled?
      end

      test "removes an organization" do
        org_tenant = create :team_sync_tenant
        org_in_business = org_tenant.organization
        @business.add_organization org_in_business
        create :business_team_sync_tenant, business: @business

        @business.remove_organization(org_in_business)

        @business.reload
        refute_includes @business.organizations, org_in_business
      end

      test "applies business policies to the organization before removing it" do
        org = create :organization
        assert org.repository_projects_enabled?

        @business.disable_repository_projects(actor: @owner, force: true)
        @business.add_organization org
        @business.reload
        assert_includes @business.organizations.reload, org
        org.reload
        refute org.repository_projects_enabled?

        @business.remove_organization org

        @business.reload
        refute_includes @business.organizations, org
        refute org.repository_projects_enabled?
      end

      if GitHub.billing_enabled?
        test "does not apply business policies to the organization before removing it from a trial" do
          org = create :organization
          create :business_organization_invitation, business: @business, invitee: org, confirmed_at: Time.current
          assert org.repository_projects_enabled?

          @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
          @business.disable_repository_projects(actor: @owner, force: true)
          @business.add_organization org
          @business.reload
          assert_includes @business.organizations.reload, org
          org.reload
          refute org.repository_projects_enabled?

          @business.remove_organization org

          @business.reload
          refute_includes @business.organizations, org
          assert org.repository_projects_enabled?
        end

        test "resumes billing for organizations when removing it from a trial" do
          org = create(:credit_card_org, admin: @owner)
          create(:business_organization_invitation, business: @business, invitee: org, confirmed_at: Time.current)
          plan_subscription = create(:billing_plan_subscription, user: org)
          @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
          @business.add_organization org
          assert_enqueued_jobs 1, only: ResumePlanSubscriptionJob do
            @business.remove_organization org
          end
        end

        test "removes organization for business with sales serve plan subscription" do
          plan_sub = create :billing_sales_serve_plan_subscription,
            customer: @business.customer,
            billing_start_date:  GitHub::Billing.today - 5.days
          org = create :organization
          @business.add_organization org
          @business.reload
          refute_nil @business.sales_serve_plan_subscription
          assert_includes @business.organizations, org

          @business.remove_organization org
          refute_includes @business.reload.organizations, org
        end

        context "self-serve business" do
          test "cancels EA org subscription items when it is removed from a self-serve EA" do
            business = create(:business, :with_self_serve_payment)
            business_owner_org_admin = business.owners.first
            business_plan_subscription = create(:billing_plan_subscription, :zuora, :business_owned,
              customer: business.customer
            )
            business_org = create :organization, business: business, admin: business_owner_org_admin
            other_business_org = create :organization, business: business, admin: business_owner_org_admin
            subscription_item = create(:billing_subscription_item,
              plan_subscription: business_plan_subscription,
              organization: business_org
            )
            other_member_org_subscription_item = create(:billing_subscription_item,
              plan_subscription: business_plan_subscription,
              organization: other_business_org
            )
            sponsors_subscription_item = create(:sponsors_subscription_item,
              account: business_org,
            )
            sponsors_subscription_item2 = create(:sponsors_subscription_item,
              account: business_org,
            )
            other_member_org_sponsors_subscription_item = create(:sponsors_subscription_item,
              account: other_business_org,
            )

            # general-purpose and sponsors-specific plan subscription syncs should each be enqueued once each.
            assert_enqueued_jobs 2, only: SynchronizePlanSubscriptionJob do
              assert_enqueued_with(
                job: SynchronizePlanSubscriptionJob,
                args: [
                  { plan_name: "business_plus", purpose: "general", business_id: business.id },
                  business: business
                ]
              ) do
                assert_enqueued_with(
                  job: SynchronizePlanSubscriptionJob,
                  args: [
                    { plan_name: "business_plus", purpose: "sponsors", business_id: business.id },
                    business: business
                  ]
                ) do
                  business.remove_organization(business_org)
                end
              end
            end

            business.reload
            refute_includes business.organizations, business_org
            assert_predicate subscription_item.reload, :cancelled?
            assert_predicate other_member_org_subscription_item.reload, :active?
            assert_predicate sponsors_subscription_item.reload, :cancelled?
            assert_predicate sponsors_subscription_item2.reload, :cancelled?
            assert_predicate other_member_org_sponsors_subscription_item.reload, :active?
          end
        end
      end

      test "does not apply any business settings to the organization that are not policies" do
        org = create :organization
        assert org.repository_projects_enabled?

        @business.disable_repository_projects(actor: @owner)
        @business.add_organization org
        @business.reload

        @business.remove_organization org

        @business.reload
        refute_includes @business.organizations, org
        assert org.repository_projects_enabled?
      end

      test "delete values for source enterprise custom properties" do
        GitHub.flipper[:enterprise_custom_properties].enable

        org = create :organization
        @business.add_organization org
        @business.reload

        repo = create :repository, owner: org
        bizprop = create :custom_property_definition, source: @business
        bizprop_value = create :custom_property_value, target: repo, definition: bizprop, value: "foo"

        perform_enqueued_jobs(only: [DeleteCustomPropertyValuesJob]) do
          @business.remove_organization org
        end

        assert_raises(ActiveRecord::RecordNotFound) { bizprop_value.reload }
      end
    end

    if GitHub.single_business_environment?
      test "does not convert internal repositories to private when it is a single business environment" do
        org = create(:enterprise_linked_organization, business: @business)
        org2 = create(:enterprise_linked_organization, business: @business)

        create(:internal_repository, owner: org)
        create(:internal_repository, owner: org)
        create(:private_repository, :minimal, owner: org)

        create(:internal_repository, owner: org2)
        create(:private_repository, :minimal, owner: org2)

        perform_enqueued_jobs(only: [RemoveInternalRepositoriesJob]) do
          @business.remove_organization org
        end
        assert_equal org.repositories.to_a.count { |r| r.internal? }, 2
        assert_equal org2.repositories.to_a.count { |r| r.internal? }, 1
      end
    else
      test "does not convert internal repositories to private when is_transfer is true" do
        org = create(:enterprise_linked_organization, business: @business)
        org2 = create(:enterprise_linked_organization, business: @business)

        create(:internal_repository, owner: org)
        create(:internal_repository, owner: org)
        create(:private_repository, :minimal, owner: org)

        create(:internal_repository, owner: org2)
        create(:private_repository, :minimal, owner: org2)

        perform_enqueued_jobs(only: [RemoveInternalRepositoriesJob]) do
          @business.remove_organization(org, is_transfer: true)
        end

        assert_equal org.repositories.to_a.count { |r| r.internal? }, 2
        assert_equal org2.repositories.to_a.count { |r| r.internal? }, 1
      end

      test "converts internal repositories that belong to the org being removed from the business to private" do
        org = create(:enterprise_linked_organization, business: @business)
        org2 = create(:enterprise_linked_organization, business: @business)

        ir = create(:internal_repository, owner: org)
        ir2 = create(:internal_repository, owner: org)
        create(:private_repository, :minimal, owner: org)

        create(:internal_repository, owner: org2)
        create(:private_repository, :minimal, owner: org2)

        perform_enqueued_jobs(only: [RemoveInternalRepositoriesJob]) do
          @business.remove_organization org
        end

        assert_empty InternalRepository.where(repository_id: [ir.id, ir2.id])
        assert_empty org.repositories.select(&:internal?)
        assert_equal org2.repositories.to_a.count { |r| r.internal? }, 1
      end

      test "creates an audit log event when internal repository is converted to private" do
        org = create(:enterprise_linked_organization, business: @business)
        ir = create(:internal_repository, owner: org)

        events = assert_performed_audit_entries(count: 1, only: "repo.access") do
          perform_enqueued_jobs(only: [RemoveInternalRepositoriesJob]) do
            @business.remove_organization org
          end
        end

        assert_equal last_performed_audit_entries, events

        expected_payload = {
          action: "repo.access",
          repo: ir.name_with_owner,
          org: org.name,
          visibility: :private,
          access: :private,
          previous_visibility: :internal,
        }

        assert_subset_hash expected_payload, events.first
      end

      test "no internal repositories are converted to private when org removed does not have any" do
        org = create(:enterprise_linked_organization, business: @business)
        org2 = create(:enterprise_linked_organization, business: @business)

        create(:private_repository, :minimal, owner: org)
        create(:private_repository, :minimal, owner: org)
        create(:private_repository, :minimal, owner: org)

        create(:internal_repository, owner: org2)
        create(:private_repository, :minimal, owner: org2)

        assert_equal org.repositories.to_a.count { |r| r.internal? }, 0

        perform_enqueued_jobs(only: [RemoveInternalRepositoriesJob]) do
          @business.remove_organization org
        end

        assert_equal org.repositories.to_a.count { |r| r.internal? }, 0
        assert_equal org2.repositories.to_a.count { |r| r.internal? }, 1
      end
    end

    if GitHub.billing_enabled?
      test "remove_organization enqueues a job to update plan subscription's customer" do
        org = create(:enterprise_linked_organization, business: @business)

        assert_enqueued_with(job: Billing::DetachOrganizationFromBusinessCustomerJob, args: [
          @business, org, { actor: @owner }
        ]) do
          @business.remove_organization org, actor: @owner
        end
      end

      test "switches to self serve billing" do
        assert_predicate @org1, :invoiced?
        @business.remove_organization @org1, actor: @owner
        @org1.reload

        refute_predicate @org1, :invoiced?
      end

      test "updates org plan to free" do
        assert_predicate @org1.plan, :business_plus?
        @business.remove_organization @org1, actor: @owner
        @org1.reload

        assert_predicate @org1.plan, :free?
      end

      test "disables IP allow list enabled at the org level when org plan set to free" do
        create :ip_allowlist_entry, owner: @org1
        @org1.enable_ip_allowlist actor: @org1.admins.first

        assert_predicate @org1.plan, :business_plus?
        assert_predicate @org1, :ip_allowlist_enabled?

        @business.remove_organization @org1, actor: @owner
        @org1.reload

        assert_predicate @org1.plan, :free?
        refute_predicate @org1, :ip_allowlist_enabled?
      end

      test "does not disable IP allow list enabled at the org level when is_transfer is true" do
        create :ip_allowlist_entry, owner: @org1
        @org1.enable_ip_allowlist actor: @org1.admins.first

        assert_predicate @org1.plan, :business_plus?
        assert_predicate @org1, :ip_allowlist_enabled?

        @business.remove_organization @org1, actor: @owner, is_transfer: true
        @org1.reload

        assert_predicate @org1.plan, :free?
        assert_predicate @org1, :ip_allowlist_enabled?
      end

      test "updates org plan duration to monthly" do
        assert_equal User::BillingDependency::YEARLY_PLAN, @org1.plan_duration
        @business.remove_organization @org1, actor: @owner
        @org1.reload

        assert_equal User::BillingDependency::MONTHLY_PLAN, @org1.plan_duration
      end

      test "converts a SToS org to the corporate terms of service" do
        # There should never be a SToS org in a non-trial enterprise account. But this is just an extra check.

        standard_owner = create(:user, :verified)
        create(:account_screening_profile, owner: standard_owner)
        stos_organization = create(:organization, admin: standard_owner)
        standard_owner.link_trade_screening_record_to_org(organization: stos_organization)

        @business.add_organization(stos_organization)
        assert_predicate stos_organization.reload.terms_of_service, :standard?
        @business.remove_organization stos_organization, actor: @owner

        assert_predicate stos_organization.reload.terms_of_service, :corporate?
      end

      test "ensures CToS org is preserved on the corporate terms of service" do
        assert_predicate @org1.terms_of_service, :corporate?
        @business.remove_organization @org1, actor: @owner

        assert_predicate @org1.reload.terms_of_service, :corporate?
      end

      test "preserves the terms of service for a SToS org when it is removed from a trial account" do
        GitHub.flipper[:cap_enterprise_in_trial_org_creation].enable

        @business.update! trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now
        assert_predicate @business, :trial?

        standard_owner = create(:user, :verified)
        create(:account_screening_profile, owner: standard_owner)
        stos_organization = create(:organization, admin: standard_owner)
        standard_owner.link_trade_screening_record_to_org(organization: stos_organization)

        @business.add_organization(stos_organization)
        assert_predicate stos_organization.reload.terms_of_service, :standard?
        @business.remove_organization stos_organization, actor: standard_owner

        assert_predicate stos_organization.reload.terms_of_service, :standard?
      end

      test "preserves the terms of service for a CToS org when it is removed from a trial account" do
        GitHub.flipper[:cap_enterprise_in_trial_org_creation].enable

        @business.update! trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now
        assert_predicate @business, :trial?

        assert_predicate @org1.terms_of_service, :corporate?
        @business.remove_organization @org1, actor: @owner

        assert_predicate @org1.reload.terms_of_service, :corporate?
      end

      test "notifies enterprise and org owners by email" do
        GitHub.flipper[:enterprise_teams_migrate_from_cfb].disable
        actor = @business.owners.first
        org = create :organization
        @business.add_organization org
        assert_includes @business.organizations.reload, org

        perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
          assert_difference "ActionMailer::Base.deliveries.size", +1 do
            @business.remove_organization org, actor: actor
          end
        end

        @business.reload
        refute_includes @business.organizations, org
        mail = ActionMailer::Base.deliveries.last
        assert_equal \
          "[GitHub] #{org.name} has been removed from the #{@business.name} enterprise",
          mail.subject
        assert_includes mail.bcc, @business.owners.first.email
        assert_includes mail.bcc, org.admins.first.email
      end

      test "does not notify enterprise and org owners by email when is_transfer is true" do
        actor = @business.owners.first
        org = create :organization
        @business.add_organization org
        assert_includes @business.organizations.reload, org

        perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
          assert_no_difference "ActionMailer::Base.deliveries.size" do
            @business.remove_organization org, actor: actor, is_transfer: true
          end
        end

        refute_includes @business.reload.organizations, org
      end

      test "does not notify enterprise and org owners by email when gh_role=staff_delete and remove_et_migration_ff_dependencies is enabled", feature_enabled: :remove_et_migration_ff_dependencies do
        actor = @business.owners.first
        org = create(:organization, gh_role: "staff_delete")
        @business.add_organization org
        assert_includes @business.organizations.reload, org

        perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
          assert_no_difference "ActionMailer::Base.deliveries.size" do
            @business.remove_organization org, actor: actor
          end
        end

        refute_includes @business.reload.organizations, org
      end

      test "does not notify enterprise and org owners by email when enterprise_teams_migrate_from_cfb is enabled", feature_disabled: :remove_et_migration_ff_dependencies do
        GitHub.flipper[:enterprise_teams_migrate_from_cfb].enable
        actor = @business.owners.first
        org = create :organization
        @business.add_organization org
        assert_includes @business.organizations.reload, org

        perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
          assert_no_difference "ActionMailer::Base.deliveries.size" do
            @business.remove_organization org, actor: actor
          end
        end

        refute_includes @business.reload.organizations, org
      end
    else
      test "does not send email notification when billing not enabled" do
        org = create :organization
        @business.add_organization org

        perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
          assert_no_difference "ActionMailer::Base.deliveries.size" do
            @business.remove_organization org
          end
        end
      end
    end

    test "disables GHAS on repositories and recalculates indexes" do
      if GitHub.enterprise?
        GitHub::Enterprise.ensure_business!
        GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
      else
        Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
      end

      repo = create(:private_repository, :minimal, owner: @org1)
      repo.enable_advanced_security!(actor: repo.owner)

      assert repo.advanced_security_enabled?

      perform_enqueued_jobs(only: SecurityAnalysisSettingsUpdateJob) do
        @business.remove_organization @org1
      end

      refute repo.reload.advanced_security_enabled?
    end

    test "clears individual organization ghas license" do
      @business.mark_advanced_security_as_purchased_for_entity(actor: @owner)

      assert @org1.advanced_security_purchased?
      refute @org1.advanced_security_purchased_for_entity?
      assert @business.advanced_security_purchased?
      assert @business.advanced_security_purchased_for_entity?

      perform_enqueued_jobs(only: SecurityAnalysisSettingsUpdateJob) do
        @business.remove_organization @org1
      end

      @org1.reload

      refute @org1.advanced_security_purchased?
      refute @org1.advanced_security_purchased_for_entity?
      assert @business.advanced_security_purchased?
      assert @business.advanced_security_purchased_for_entity?
    end if GitHub.billing_enabled?
  end

  context "#transfer_organization" do
    test "removes an organization from the previous business" do
      @business.add_organization @org1
      assert_includes @business.organizations.reload, @org1

      @business.transfer_organization(@org1, @another_business)
      @business.reload
      refute_includes @business.organizations, @org1
    end

    test "does not convert any internal repositories to private for the org being transferred" do
      create(:internal_repository, owner: @org1)
      create(:internal_repository, owner: @org1)
      create(:private_repository, :minimal, owner: @org1)

      @business.transfer_organization(@org1, @another_business)

      assert @org1.repositories.to_a.count { |r| r.internal? }, 2
    end

    test "updates internal repositories to point to new business" do
      @business.add_organization @org1
      create(:internal_repository, owner: @org1)
      create(:internal_repository, owner: @org1)
      create(:private_repository, :minimal, owner: @org1)

      repo_ids = @org1.repositories.pluck(:id)
      assert_equal [@business], InternalRepository.where(repository_id: repo_ids).map(&:business).uniq

      @business.transfer_organization(@org1, @another_business)

      assert_equal [@another_business], InternalRepository.where(repository_id: repo_ids).map(&:business).uniq
    end

    test "returns valid membership if organization is added to new business" do
      membership = @business.add_organization(@org1)
      assert membership.valid?

      new_membership = @business.transfer_organization(@org1, @another_business)

      assert new_membership.valid?
      assert_includes @another_business.organizations.reload, @org1
      refute_includes @business.organizations.reload, @org1
    end

    test "does not do the transfer of an org created inside the previous business if it is on a trial" do
      GitHub.flipper[:cap_enterprise_in_trial_org_creation].disable
      @business.add_organization @org1
      assert_includes @business.organizations.reload, @org1

      @business.update! trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now
      assert_predicate @business, :trial?

      assert_raises Business::CannotRemoveOrganizationError do
        @business.transfer_organization(@org1, @another_business, actor: @member1)
      end

      refute_includes @another_business.organizations.reload, @org1
      assert_includes @business.organizations.reload, @org1
    end

    test "does not do the transfer of an org invited inside the previous business if it is on a trial" do
      GitHub.flipper[:cap_enterprise_in_trial_org_creation].disable
      org_transfered_into_trial = create :organization
      create :business_organization_invitation, business: @business, invitee: org_transfered_into_trial, confirmed_at: Time.current
      @business.add_organization org_transfered_into_trial
      @business.reload
      assert_includes @business.organizations.reload, @org1

      @business.update! trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now
      assert_predicate @business, :trial?

      assert_raises Business::CannotRemoveOrganizationError do
        @business.transfer_organization(@org1, @another_business, actor: @member1)
      end

      refute_includes @another_business.organizations.reload, @org1
      assert_includes @business.organizations.reload, @org1
    end

    test "does the transfer of an org if the business is metered" do
      org = create :organization
      create :business_organization_invitation, business: @business, invitee: org, confirmed_at: Time.current
      @business.add_organization org
      @business.customer.update metered_ghe: true
      @business.reload
      assert_includes @business.organizations.reload, @org1

      @business.transfer_organization(@org1, @another_business, actor: @member1)

      assert_includes @another_business.organizations.reload, @org1
      refute_includes @business.organizations.reload, @org1
    end

    test "does the transfer of an org created inside the previous business if it is on a trial and the actor is staff" do
      @business.add_organization @org1
      assert_includes @business.organizations.reload, @org1

      @business.update! trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now
      assert_predicate @business, :trial?

      staff = create :staff_admin_user
      @business.transfer_organization(@org1, @another_business, actor: staff)

      assert_includes @another_business.organizations.reload, @org1
      refute_includes @business.organizations.reload, @org1
    end

    test "does the transfer of an org invited inside the previous business if it is on a trial and the actor is staff" do
      org_transfered_into_trial = create :organization
      create :business_organization_invitation, business: @business, invitee: org_transfered_into_trial, confirmed_at: Time.current
      @business.add_organization org_transfered_into_trial
      @business.reload
      assert_includes @business.organizations.reload, @org1

      @business.update! trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now
      assert_predicate @business, :trial?

      staff = create :staff_admin_user
      @business.transfer_organization(@org1, @another_business, actor: staff)

      assert_includes @another_business.organizations.reload, @org1
      refute_includes @business.organizations.reload, @org1
    end
  end unless GitHub.single_business_environment?

  context "#attach_organization_for_upgrade" do
    test "attaches an organization to an enterprise account" do
      organization = create :organization, admin: @owner, plan: "business"
      assert_nil organization.business

      @business.attach_organization_for_upgrade(organization, @owner)
      assert_equal @business, organization.reload.business
    end

    test "attaches an organization to an enterprise trial account" do
      organization = create :organization, admin: @owner, plan: "business"
      assert_nil organization.business

      @business.update!(trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now)
      assert_predicate @business, :trial?

      @business.attach_organization_for_upgrade(organization, @owner)
      assert_equal @business, organization.reload.business
    end

    test "transfers billing managers and billing email from the upgraded organization to the enterprise" do
      new_billing_manager = create :user
      organization = create :organization, plan: GitHub::Plan.business_plus, seats: 10, admins: [@owner]
      organization.billing.add_manager(new_billing_manager, actor: @owner)
      assert_nil organization.business

      perform_enqueued_jobs only: BusinessCreatedFromOrganizationJob do
        @business.attach_organization_for_upgrade(organization, @owner)
      end
      assert_equal @business, organization.reload.business
      assert_equal organization.billing_email, @business.billing_email
      assert @business.billing_manager?(new_billing_manager)
    end

    test "transfers owners from a Free/Team plan upgraded organization on self-serve billing to the enterprise" do
      new_owner = create :user
      organization = create :organization, plan: GitHub::Plan.business, seats: 10, admins: [@owner], billing_type: "card"
      organization.add_admin(new_owner)
      assert_nil organization.business

      @business.customer.update!(billing_type: Customer::BILLING_TYPE_CARD)

      perform_enqueued_jobs only: BusinessCreatedFromOrganizationJob do
        @business.attach_organization_for_upgrade(organization, @owner)
      end
      assert_equal @business, organization.reload.business
      assert @business.owner?(new_owner)
    end

    test "users that are both admins and billing managers of a Free/Team plan org upgrading to an EA become owners of the enterprise only" do
      org_admin_and_billing_manager = create :user
      organization = create :organization, plan: GitHub::Plan.business, seats: 10, admins: [@owner], billing_type: "card"
      organization.add_admin(org_admin_and_billing_manager)
      organization.billing.add_manager(org_admin_and_billing_manager, actor: @owner)
      assert_nil organization.business

      @business.customer.update!(billing_type: Customer::BILLING_TYPE_CARD)

      perform_enqueued_jobs only: BusinessCreatedFromOrganizationJob do
        @business.attach_organization_for_upgrade(organization, @owner)
      end
      assert_equal @business, organization.reload.business
      assert @business.owner?(org_admin_and_billing_manager)
      refute @business.billing_manager?(org_admin_and_billing_manager)
    end

    test "transfers specified settings to invoiced-billing enterprise when provided" do
      organization = create :organization, plan: GitHub::Plan.business_plus, seats: 10, admin: @owner, billing_type: "invoice"
      assert_predicate organization, :invoiced?
      create :verifiable_domain, owner: organization, domain: "www.github.com", verified: false
      create :verifiable_domain, owner: organization, domain: "sub.github.com", verified: true
      organization.enable_notification_restrictions(actor: @owner, notify_members: false)
      assert_predicate organization, :restrict_notifications_to_verified_domains?

      perform_enqueued_jobs only: BusinessCreatedFromOrganizationJob do
        @business.attach_organization_for_upgrade(
          organization,
          @owner,
          settings_to_transfer: [{
            name: :domains,
            description: "Verified and approved domains configuration"
          },])
      end

      assert_equal 2, @business.reload.verifiable_domains.count
      assert_predicate @business, :restrict_notifications_to_verified_domains?
      assert_predicate organization.reload, :restrict_notifications_to_verified_domains?
      assert_predicate organization, :restrict_notifications_to_verified_domains_policy?
    end

    test "transfers specified settings to card-billing enterprise when provided" do
      organization = create :organization, plan: GitHub::Plan.business_plus, seats: 10, admin: @owner, billing_type: "card"
      refute_predicate organization, :invoiced?
      create :verifiable_domain, owner: organization, domain: "www.github.com", verified: false
      create :verifiable_domain, owner: organization, domain: "sub.github.com", verified: true
      organization.enable_notification_restrictions(actor: @owner, notify_members: false)
      assert_predicate organization, :restrict_notifications_to_verified_domains?

      perform_enqueued_jobs only: BusinessCreatedFromOrganizationJob do
        @business.attach_organization_for_upgrade(
          organization,
          @owner,
          settings_to_transfer: [{
            name: :domains,
            description: "Verified and approved domains configuration"
          },])
      end

      assert_equal 2, @business.reload.verifiable_domains.count
      assert_predicate @business, :restrict_notifications_to_verified_domains?
      assert_predicate organization.reload, :restrict_notifications_to_verified_domains?
      assert_predicate organization, :restrict_notifications_to_verified_domains_policy?
    end

    test "enables Copilot on the business if upgrading from business_plus plan organization with it enabled" do
      organization = create :organization, :with_valid_contact_for_billing, plan: GitHub::Plan.business_plus, seats: 10, admin: @owner, billing_type: "card"
      assert_nil organization.business

      business_customer = create :credit_card_customer
      @business.customer = business_customer

      Copilot::Organization.new(organization).enable_copilot!
      assert_predicate Copilot::Organization.new(organization.reload), :copilot_enabled?

      perform_enqueued_jobs only: BusinessCreatedFromOrganizationJob do
        @business.attach_organization_for_upgrade(organization, @owner)
      end

      assert_equal Copilot::Business.new(@business.reload).copilot_enabled_organizations_count, 1
      assert_predicate Copilot::Organization.new(organization.reload), :copilot_enabled?
    end

    test "does not enable Copilot on the business if upgrading from business_plus plan organization is invoiced" do
      organization = create :organization, plan: GitHub::Plan.business_plus, seats: 10, admin: @owner, billing_type: "invoice"
      assert_nil organization.business

      @business.customer.update(billing_type: Customer::BILLING_TYPE_INVOICE)

      Copilot::Organization.new(organization).enable_copilot!
      assert_predicate Copilot::Organization.new(organization.reload), :copilot_enabled?

      perform_enqueued_jobs only: BusinessCreatedFromOrganizationJob do
        @business.attach_organization_for_upgrade(organization, @owner)
      end

      assert_equal Copilot::Business.new(@business.reload).copilot_enabled_organizations_count, 0
      refute_predicate Copilot::Organization.new(organization.reload), :copilot_enabled?
    end

    test "enables Copilot on the business if upgrading from teams plan organization with it enabled" do
      organization = create :organization, plan: GitHub::Plan.business, seats: 10, admin: @owner, billing_type: "card"
      assert_nil organization.business

      business_customer = create :credit_card_customer
      @business.customer = business_customer

      Copilot::Organization.new(organization).enable_copilot!
      assert_predicate Copilot::Organization.new(organization.reload), :copilot_enabled?

      perform_enqueued_jobs only: BusinessCreatedFromOrganizationJob do
        @business.attach_organization_for_upgrade(organization, @owner)
      end

      assert_equal Copilot::Business.new(@business.reload).copilot_enabled_organizations_count, 1
      assert_predicate Copilot::Organization.new(organization.reload), :copilot_enabled?
    end

    test "creates the business with 'write' workflow permission as default, if organization has it enabled" do
      GitHub.flipper[:actions_default_workflow_permissions_new_repos].enable
      organization = create :organization, plan: GitHub::Plan.business_plus, seats: 10, admin: @owner, billing_type: "card"
      business = create(:business, owners: [@owner])
      business_customer = create :credit_card_customer
      business.customer = business_customer
      assert_nil organization.business

      organization.set_default_workflow_permissions("write", @owner)
      organization.set_actions_workflow_permission_can_approve_pr(true, @owner)
      refute_predicate organization, :actions_default_workflow_permissions_read_only?
      assert_predicate organization, :actions_workflow_permission_can_approve_pr?

      perform_enqueued_jobs only: BusinessCreatedFromOrganizationJob do
        business.attach_organization_for_upgrade(organization, @owner)
      end

      refute_predicate business, :actions_default_workflow_permissions_read_only?  # Permission is 'write'
      assert_predicate business, :actions_workflow_permission_can_approve_pr?
    end

    test "creates the business with selected fork pr workflow permissions, if organization has them enabled" do
      organization = create :organization, plan: GitHub::Plan.business_plus, seats: 10, admin: @owner, billing_type: "card"
      business = create(:business, owners: [@owner])
      business_customer = create :credit_card_customer
      business.customer = business_customer
      assert_nil organization.business
      refute_predicate business, :can_run_fork_pr_workflows?

      policy = Configurable::ForkPrWorkflowsPolicy::RUN_WORKFLOWS
      policy |= Configurable::ForkPrWorkflowsPolicy::RUN_WITH_TOKENS
      policy |= Configurable::ForkPrWorkflowsPolicy::RUN_WITH_SECRETS
      organization.set_fork_pr_workflows_policy(policy: policy, actor: @owner)
      organization.set_actions_private_fork_pr_approvals_policy(policy: Configurable::ActionsPrivateForkPrApprovals::READ_ONLY_USERS, actor: @owner)
      assert_predicate organization, :can_run_fork_pr_workflows?
      assert_equal organization.actions_private_fork_pr_approvals_policy, Configurable::ActionsPrivateForkPrApprovals::READ_ONLY_USERS

      perform_enqueued_jobs only: BusinessCreatedFromOrganizationJob do
        business.attach_organization_for_upgrade(organization, @owner)
      end

      assert_predicate business, :can_run_fork_pr_workflows?
      assert_predicate business, :can_run_fork_pr_workflows_with_write_tokens?
      assert_predicate business, :can_run_fork_pr_workflows_with_secrets?
      assert_equal business.actions_private_fork_pr_approvals_policy, Configurable::ActionsPrivateForkPrApprovals::READ_ONLY_USERS
    end

    test "does not create the business with 'write' workflow permission as default, if organization does not have it enabled" do
      GitHub.flipper[:actions_default_workflow_permissions_new_repos].enable
      organization = create :organization, plan: GitHub::Plan.business_plus, seats: 10, admin: @owner, billing_type: "card"
      business = create(:business, owners: [@owner])
      business_customer = create :credit_card_customer
      business.customer = business_customer
      assert_nil organization.business

      organization.set_default_workflow_permissions("read", @owner)
      organization.set_actions_workflow_permission_can_approve_pr(false, @owner)
      assert_predicate organization, :actions_default_workflow_permissions_read_only?
      refute_predicate organization, :actions_workflow_permission_can_approve_pr?

      perform_enqueued_jobs only: BusinessCreatedFromOrganizationJob do
        business.attach_organization_for_upgrade(organization, @owner)
      end

      assert_predicate business, :actions_default_workflow_permissions_read_only?  # Permission is 'read'
      refute_predicate business, :actions_workflow_permission_can_approve_pr?
    end

    test "does not enable Copilot on the business if the upgrading organization has it disabled" do
      organization = create :organization, plan: GitHub::Plan.business_plus, seats: 10, admin: @owner, billing_type: "card"
      assert_nil organization.business

      refute_predicate Copilot::Organization.new(organization.reload), :copilot_enabled?

      perform_enqueued_jobs only: BusinessCreatedFromOrganizationJob do
        @business.attach_organization_for_upgrade(organization, @owner)
      end

      assert_equal Copilot::Business.new(@business.reload).copilot_enabled_organizations_count, 0
      refute_predicate Copilot::Organization.new(organization.reload), :copilot_enabled?
    end

    test "does not enable Copilot on the business if the upgrading organization has it enabled, but the business is on trial" do
      organization = create :organization, plan: GitHub::Plan.business_plus, seats: 10, admin: @owner, billing_type: "card"
      assert_nil organization.business

      Copilot::Organization.new(organization).enable_copilot!
      assert_predicate Copilot::Organization.new(organization.reload), :copilot_enabled?

      @business.update!(trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now)
      assert_predicate @business, :trial?

      perform_enqueued_jobs only: [BusinessCreatedFromOrganizationJob] do
        @business.attach_organization_for_upgrade(organization, @owner)
      end

      assert_equal Copilot::Business.new(@business.reload).copilot_enabled_organizations_count, 0
      refute_predicate Copilot::Organization.new(organization.reload), :copilot_enabled?
    end

    test "transfers spending limits to the business if upgrading from business_plus plan organization" do
      organization = create :organization, plan: GitHub::Plan.business_plus, seats: 10, admin: @owner, billing_type: "card"
      org_customer = create :credit_card_customer
      organization.customer = org_customer
      assert_nil organization.business

      business_customer = create :credit_card_customer
      @business.customer = business_customer
      @business.customer.update!(billing_type: Customer::BILLING_TYPE_CARD)

      organization.budget_for(group: :codespaces).configure(
        enforce_spending_limit: true,
        limit: 100
      )
      organization.budget_for(group: :shared).configure(
        enforce_spending_limit: true,
        limit: 200
      )

      assert_predicate organization.budget_for(group: :codespaces), :valid?
      assert_predicate organization.budget_for(group: :shared), :valid?

      perform_enqueued_jobs only: BusinessCreatedFromOrganizationJob do
        @business.attach_organization_for_upgrade(organization, @owner)
      end

      assert_equal @business.budget_for(group: :codespaces).spending_limit_in_subunits / 100, 100
      assert_equal @business.budget_for(group: :shared).spending_limit_in_subunits / 100, 200
    end

    test "transfers spending limits to the business if upgrading from business plan organization" do
      organization = create :organization, plan: GitHub::Plan.business, seats: 10, admin: @owner, billing_type: "card"
      org_customer = create :credit_card_customer
      organization.customer = org_customer
      assert_nil organization.business

      business_customer = create :credit_card_customer
      @business.customer = business_customer
      @business.customer.update!(billing_type: Customer::BILLING_TYPE_CARD)

      organization.budget_for(group: :codespaces).configure(
        enforce_spending_limit: true,
        limit: 100
      )
      organization.budget_for(group: :shared).configure(
        enforce_spending_limit: true,
        limit: 200
      )

      assert_predicate organization.budget_for(group: :codespaces), :valid?
      assert_predicate organization.budget_for(group: :shared), :valid?

      perform_enqueued_jobs only: BusinessCreatedFromOrganizationJob do
        @business.attach_organization_for_upgrade(organization, @owner)
      end

      assert_equal @business.budget_for(group: :codespaces).spending_limit_in_subunits / 100, 100
      assert_equal @business.budget_for(group: :shared).spending_limit_in_subunits / 100, 200
    end

    test "transfers spending limits to the business if upgrading from business plan organization, even if payment method was detached" do
      organization = create :organization, plan: GitHub::Plan.business, seats: 10, admin: @owner, billing_type: "card"
      org_customer = create :credit_card_customer
      organization.customer = org_customer
      assert_nil organization.business

      business_customer = create :credit_card_customer
      @business.customer = business_customer
      @business.customer.update!(billing_type: Customer::BILLING_TYPE_CARD)

      organization.budget_for(group: :codespaces).configure(
        enforce_spending_limit: true,
        limit: 100
      )
      organization.budget_for(group: :shared).configure(
        enforce_spending_limit: true,
        limit: 200
      )

      Organization.any_instance.stubs(:has_valid_payment_method?).returns(false)

      perform_enqueued_jobs only: BusinessCreatedFromOrganizationJob do
        @business.attach_organization_for_upgrade(organization, @owner)
      end

      assert_equal @business.budget_for(group: :codespaces).spending_limit_in_subunits / 100, 100
      assert_equal @business.budget_for(group: :shared).spending_limit_in_subunits / 100, 200
    end

    test "does not transfer spending limits to the business if they are not valid" do
      organization = create :organization, plan: GitHub::Plan.business_plus, seats: 10, admin: @owner, billing_type: "card"
      org_customer = create :credit_card_customer
      organization.customer = org_customer
      assert_nil organization.business

      business_customer = create :credit_card_customer
      @business.customer = business_customer
      @business.customer.update!(billing_type: Customer::BILLING_TYPE_CARD)

      organization.budget_for(group: :codespaces).configure(
        enforce_spending_limit: true,
        limit: 100
      )
      organization.budget_for(group: :shared).configure(
        enforce_spending_limit: true,
        limit: 200
      )

      errors = [ActiveModel::Error.new("Error", :payment_method, "must be present and valid"), ActiveModel::Error.new("Error", :tiered_spending, "other error")]  # Multiple errors
      Billing::Budget.any_instance.stubs(:errors).returns(errors)
      Billing::Budget.any_instance.stubs(:valid?).returns(false)  # Not valid due to multiple validation errors
      assert_equal organization.budget_for(group: :codespaces).errors.count, 2
      assert_equal organization.budget_for(group: :shared).errors.count, 2

      perform_enqueued_jobs only: BusinessCreatedFromOrganizationJob do
        @business.attach_organization_for_upgrade(organization, @owner)
      end

      assert_equal @business.budget_for(group: :codespaces).spending_limit_in_subunits, 0
      assert_equal @business.budget_for(group: :shared).spending_limit_in_subunits, 0
    end

    test "does not transfer spending limits if the business does not have a valid payment method" do
      organization = create :organization, plan: GitHub::Plan.business, seats: 10, admin: @owner, billing_type: "card"
      org_customer = create :credit_card_customer
      organization.customer = org_customer
      assert_nil organization.business

      @business.customer.update!(billing_type: Customer::BILLING_TYPE_CARD)

      organization.budget_for(group: :codespaces).configure(
        enforce_spending_limit: true,
        limit: 100
      )
      organization.budget_for(group: :shared).configure(
        enforce_spending_limit: true,
        limit: 200
      )

      assert_predicate organization.budget_for(group: :codespaces), :valid?
      assert_predicate organization.budget_for(group: :shared), :valid?

      perform_enqueued_jobs only: BusinessCreatedFromOrganizationJob do
        @business.attach_organization_for_upgrade(organization, @owner)
      end

      assert_equal @business.budget_for(group: :codespaces).spending_limit_in_subunits, 0
      assert_equal @business.budget_for(group: :shared).spending_limit_in_subunits, 0
    end

    test "does not transfer spending limits to the business if none are set on upgrading organization" do
      organization = create :organization, plan: GitHub::Plan.business_plus, seats: 10, admin: @owner, billing_type: "card"
      org_customer = create :credit_card_customer
      organization.customer = org_customer
      assert_nil organization.business

      business_customer = create :credit_card_customer
      @business.customer = business_customer
      @business.customer.update!(billing_type: Customer::BILLING_TYPE_CARD)

      assert_empty organization.budgets

      perform_enqueued_jobs only: BusinessCreatedFromOrganizationJob do
        @business.attach_organization_for_upgrade(organization, @owner)
      end

      assert_empty @business.budgets
    end

    test "does not transfer spending limits to the business if it is on trial" do
      organization = create :organization, plan: GitHub::Plan.business, seats: 10, admin: @owner, billing_type: "card"
      org_customer = create :credit_card_customer
      organization.customer = org_customer
      assert_nil organization.business

      business_customer = create :credit_card_customer
      @business.customer = business_customer
      @business.customer.update!(billing_type: Customer::BILLING_TYPE_CARD)

      organization.budget_for(group: :codespaces).configure(
        enforce_spending_limit: true,
        limit: 100
      )
      organization.budget_for(group: :shared).configure(
        enforce_spending_limit: true,
        limit: 200
      )

      @business.update!(trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now)
      assert_predicate @business, :trial?

      perform_enqueued_jobs only: [BusinessCreatedFromOrganizationJob] do
        @business.attach_organization_for_upgrade(organization, @owner)
      end

      assert_empty @business.budgets
    end

    test "saves the organization's previous plan when upgrading into an enterprise" do
      organization = create :organization, admin: @owner, plan: "business"
      assert_nil organization.business

      @business.attach_organization_for_upgrade(organization, @owner)
      assert_equal @business.upgraded_from, organization.reload
      refute_nil @business.upgraded_at
      assert_equal @business.upgraded_from_plan, "business"
    end

    test "suspends organization's Zuora subscription if attached to an enterprise trial account" do
      organization = create :organization, admin: @owner, plan: "business"
      assert_nil organization.business

      plan_subscription = create(:billing_plan_subscription, :zuora, user: organization)

      @business.update!(trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now)
      assert_predicate @business, :trial?

      # Ensure plan subscription is suspended
      assert_enqueued_with(job: SuspendPlanSubscriptionJob, args: [organization.plan_subscription]) do
        perform_enqueued_jobs only: [BusinessCreatedFromOrganizationJob] do
          @business.attach_organization_for_upgrade(organization, @owner)
        end
      end
      assert_equal @business, organization.reload.business
    end

    test "transfers enterprise-plan organization's Zuora account and subscription to the Business" do
      organization = create :organization, admin: @owner, plan: "business_plus"
      zuora_successful_customer_account_creation(organization)

      with_live_zuora("zuora/transfer_zuora_subscription_of_attaching_org") do
        business = create :business
        organization.reload

        transferred_customer = organization.customer  # Get current customer and subscription to be used for future comparison
        transferred_subscription = organization.plan_subscription
        refute_nil transferred_customer
        refute_nil transferred_subscription
        assert_equal transferred_customer.name, organization.name

        business.attach_organization_for_upgrade(organization, @owner)
        assert_equal business, organization.reload.business

        assert_nil organization.reload.customer  # Organization should no longer be associated with the customer account or subscription
        assert_nil organization.plan_subscription
        assert_equal business.reload.customer, transferred_customer.reload # Customer and plan subscription should now be attached to the Business
        assert_equal business.customer.plan_subscription, transferred_subscription.reload
        assert_equal transferred_customer.name, business.name # The customer's name is updated to match the Business
      end
    end

    test "transfers enterprise-plan organization's next billing date to the Business" do
      organization = create :organization, admin: @owner, plan: "business_plus"
      zuora_successful_customer_account_creation(organization)

      with_live_zuora("zuora/transfer_billing_end_date_of_attaching_org") do
        business = create :business
        organization.billed_on = GitHub::Billing.today + 1.year
        organization.save!
        organization.reload

        billed_on_date = organization.billed_on
        refute_nil billed_on_date

        business.attach_organization_for_upgrade(organization, @owner)
        assert_equal business, organization.reload.business

        assert_equal business.reload.customer.billing_end_date.to_date, billed_on_date.to_date - 1.day
      end
    end

    test "transfers enterprise-plan organization's active marketplace items to the Business" do
      organization = create :organization, admin: @owner, plan: "business_plus", billing_type: "card"
      zuora_successful_customer_account_creation(organization)

      with_live_zuora("zuora/transfer_marketplace_items_of_upgrading_enterprise_plan_org") do
        listing_plan = create :marketplace_listing_plan, :verified_listing
        ano_listing_plan = create :marketplace_listing_plan, :verified_listing
        qty = 99
        org_subscription_item = create :billing_subscription_item, plan_subscription: organization.plan_subscription,
          subscribable: listing_plan, quantity: qty
        cancelled_org_subscription_item = create :billing_subscription_item, plan_subscription: organization.plan_subscription,
          subscribable: ano_listing_plan, quantity: 0

        business = create :business
        organization.reload

        assert_equal 0, business.subscription_items.count

        business.attach_organization_for_upgrade(organization, @owner)

        assert_equal business, organization.reload.business
        assert_equal 2, business.subscription_items.count

        business_subscription_item = business.subscription_items.find { |si| si.quantity == qty }
        cancelled_business_subscription_item = business.subscription_items.find { |si| si.quantity == 0 }

        assert_equal org_subscription_item.subscribable, business_subscription_item.subscribable
        assert_equal qty, business_subscription_item.quantity

        assert_equal cancelled_org_subscription_item.subscribable, cancelled_business_subscription_item.subscribable

        assert_equal organization.id, business_subscription_item.organization_id
        assert_equal organization.id, cancelled_business_subscription_item.organization_id
      end
    end

    test "sets marketplace trial end date to original trial date if marketplace app still in trial at time of transfer" do
      organization = create :organization, admin: @owner, plan: "business_plus", billing_type: "card"
      zuora_successful_customer_account_creation(organization)

      with_live_zuora("zuora/transfer_marketplace_items_of_upgrading_enterprise_plan_org") do
        listing_plan = create :marketplace_listing_plan, :verified_listing
        org_subscription_item = create :billing_subscription_item, plan_subscription: organization.plan_subscription,
          subscribable: listing_plan, free_trial_ends_on: 1.week.from_now

        business = create :business
        organization.reload

        assert_equal 0, business.subscription_items.count

        business.attach_organization_for_upgrade(organization, @owner)

        assert_equal business, organization.reload.business
        assert_equal 1, business.subscription_items.count

        business_subscription_item = business.subscription_items.last
        assert_equal org_subscription_item.free_trial_ends_on, business_subscription_item.free_trial_ends_on
      end
    end

    test "transfers enterprise-plan organization's sponsor subscriptions items to the business" do
      organization = create :organization, :sponsorable, admin: @owner, plan: "business_plus", billing_type: "card"
      zuora_successful_customer_account_creation(organization)

      with_live_zuora("zuora/transfer_sponsors_items_of_upgrading_enterprise_plan_org") do
        sponsorship_1 = create(:sponsorship, sponsor: organization)
        sponsorship_2 = create(:sponsorship, sponsor: organization)

        qty = 5
        org_sponsor_subscription_item = sponsorship_1.subscription_item
        org_sponsor_subscription_item.update(quantity: qty)
        cancelled_org_sponsor_subscription_item = sponsorship_2.subscription_item
        cancelled_org_sponsor_subscription_item.update(quantity: 0)

        business = create :business
        organization.reload

        assert_equal 0, business.subscription_items.for_sponsors_tiers.count
        assert_equal 2, organization.subscription_items.for_sponsors_tiers.count

        business.attach_organization_for_upgrade(organization, @owner)

        assert_equal business, organization.reload.business
        assert_equal 2, business.subscription_items.for_sponsors_tiers.count
        assert_equal 0, organization.subscription_items.for_sponsors_tiers.count

        business_subscription_item = business.subscription_items.find { |si| si.quantity == qty }
        cancelled_business_subscription_item = business.subscription_items.find { |si| si.quantity == 0 }

        assert_equal org_sponsor_subscription_item.subscribable, business_subscription_item.subscribable
        assert_equal qty, business_subscription_item.quantity

        assert_equal cancelled_org_sponsor_subscription_item.subscribable, cancelled_business_subscription_item.subscribable

        assert_equal organization.id, business_subscription_item.organization_id
        assert_equal organization.id, cancelled_business_subscription_item.organization_id
      end
    end

    test "transfers enterprise-plan organization's trade screening record if it has a valid business schema" do
      user = create(:user, :verified)
      organization = create(:organization, :with_account_screening_profile, admin: user, plan: "business_plus")
      organization.terms_of_service.update(type: "Corporate", actor: user)  # Create Corporate Tos trade screening record
      assert organization.trade_screening_record.valid?(:entity)
      assert_predicate organization.trade_screening_record, :valid?
      assert_equal organization.trade_screening_record.owner_id, organization.id  # Owner of the TSR is the organization

      zuora_successful_customer_account_creation(organization)

      with_live_zuora("zuora/transfer_zuora_subscription_of_attaching_org") do
        business = create :business
        organization.reload

        trade_screening_record = organization.trade_screening_record
        refute_nil trade_screening_record

        business.attach_organization_for_upgrade(organization, user)
        assert_equal business, organization.reload.business

        assert_equal business.reload.trade_screening_record, trade_screening_record.reload # Trade screening record should now be attached to the Business
        assert_equal trade_screening_record.owner_id, business.id  # Owner of the TSR is now the business
      end
    end

    test "does not transfer enterprise-plan organization's trade screening record if it does not have a valid business schema" do
      standard_owner = create(:user, :verified)
      create(:account_screening_profile, owner: standard_owner)
      organization = create(:organization, admin: standard_owner)
      standard_owner.link_trade_screening_record_to_org(organization: organization)  # Create standard ToS trade screening record
      assert_predicate organization.trade_screening_record, :valid?
      refute organization.trade_screening_record.valid?(:entity)
      assert_equal organization.trade_screening_record.owner_id, standard_owner.id  # Owner of the TSR is the organization's admin

      zuora_successful_customer_account_creation(organization)

      with_live_zuora("zuora/transfer_zuora_subscription_of_attaching_org") do
        business = create :business
        organization.reload

        trade_screening_record = organization.trade_screening_record
        refute_nil trade_screening_record

        business.attach_organization_for_upgrade(organization, standard_owner)
        assert_equal business, organization.reload.business

        refute_equal business.reload.trade_screening_record, trade_screening_record.reload # Trade screening record should not be attached to the Business
        assert_equal trade_screening_record.owner_id, standard_owner.id  # Owner of the TSR is still the organization's admin
      end
    end

    test "does not transfer organization's Zuora account and subscription to the Business if org is not on the business_plus plan" do
      organization = create :organization, admin: @owner, plan: "business"
      zuora_successful_customer_account_creation(organization)

      with_live_zuora("zuora/transfer_zuora_subscription_of_attaching_org") do
        business = create :business
        organization.reload

        transferred_customer = organization.customer  # Get current customer and subscription to be used for future comparison
        transferred_subscription = organization.plan_subscription
        refute_nil transferred_customer
        refute_nil transferred_subscription

        business.attach_organization_for_upgrade(organization, @owner)
        assert_equal business, organization.reload.business

        refute_nil organization.customer  # Organization should still be associated with the customer account or subscription
        refute_nil organization.plan_subscription
        refute_equal business.customer, transferred_customer.reload  # Customer and plan subscription should not be attached to the Business
        refute_equal business.customer.plan_subscription, transferred_subscription.reload
      end
    end

    test "expires organization's coupon when attached to an enterprise account, and sends email informing the user of coupon expiration" do
      coupon = create(:coupon, discount: "$5")
      organization = create :organization, admin: @owner, plan: "business"
      organization.redeem_coupon(coupon)

      assert organization.coupon.present?
      assert_nil organization.business

      # BusinessCreatedFromOrganizationJob also creates a BusinessMailer job but we're interested in the coupon email job
      assert_difference "ActionMailer::Base.deliveries.count", 2 do
        assert_performed_email(mailer: "BillingNotificationsMailer", action: "coupon_removed_from_enterprise_owned_organization", args: [organization, @business]) do
          @business.attach_organization_for_upgrade(organization, @owner)
        end
      end
      assert_equal @business, organization.reload.business
      assert_empty organization.reload.coupon_redemptions
    end

    test "expires enterprise-plan organization's coupon when upgrading to an enterprise account, but doesn't send coupon expiration email" do
      coupon = create(:coupon, discount: "$5")
      organization = create :organization, admin: @owner, plan: "business_plus"
      organization.redeem_coupon(coupon)
      @business.organization_direct_upgraded!

      assert organization.coupon.present?
      assert_nil organization.business

      assert_no_difference "ActionMailer::Base.deliveries.count" do
        @business.attach_organization_for_upgrade(organization, @owner)
      end

      assert_equal @business, organization.reload.business
      assert_empty organization.reload.coupon_redemptions
    end

    test "expires enterprise-plan organization's coupon when upgrading to an enterprise account, explains coupon was tranferred from org to EA in general email for business created from organization" do
      coupon = create(:coupon, discount: "$5")
      organization = create :organization, admin: @owner, plan: "business_plus", billing_type: "card"
      organization.redeem_coupon(coupon)
      @business.organization_direct_upgraded!

      assert_predicate organization, :has_an_active_coupon?
      assert_nil organization.business

      perform_enqueued_jobs(only: [ApplicationDeliveryJob, BusinessCreatedFromOrganizationJob]) do
        @business.attach_organization_for_upgrade(organization, @owner)
      end

      assert_equal @business, organization.reload.business
      assert_empty organization.reload.coupon_redemptions
      assert_predicate @business.reload, :has_an_active_coupon?

      mail = ActionMailer::Base.deliveries.last
      assert_equal \
        "[GitHub] #{@business.name} enterprise created for the #{organization.safe_profile_name} organization",
        mail.subject
      assert_includes \
        mail.html_part.body.to_s,
        "The #{organization.safe_profile_name} organization's current coupon has been transferred to the #{@business.name} enterprise. The conditions and remaining duration of the coupon will carry over."
    end

    test "transfers enterprise-plan organization's coupon to the business if feature flag is enabled, even if the org does not have a plan subscription" do
      business_plus_card_org = create(:business_plus_organization, admin: @owner, billing_type: "card")
      coupon = create(:coupon, plan: "business_plus", discount: "100%")
      business_plus_card_org.redeem_coupon(coupon.code, actor: @owner)

      assert_predicate business_plus_card_org, :has_an_active_coupon?
      assert_nil business_plus_card_org.plan_subscription
      refute_predicate @business, :has_an_active_coupon?

      @business.attach_organization_for_upgrade(business_plus_card_org, @owner)

      assert_equal @business, business_plus_card_org.reload.business
      refute_predicate business_plus_card_org, :has_an_active_coupon?
      assert_predicate @business.reload, :has_an_active_coupon?
    end
  end unless GitHub.single_business_environment?

  context "#pending_organization_invitation_for" do
    test "finds unaccepted organization invitation" do
      org = create(:organization)
      create :business_organization_invitation, \
        business: @business,
        inviter: @business.owners.first,
        invitee: org

      invitation = @business.pending_organization_invitation_for(org)

      assert_equal @business, invitation.business
      assert_equal @business.owners.first, invitation.inviter
      assert_equal org, invitation.invitee
    end

    test "finds accepted-but-not-confirmed invitation" do
      org = create(:organization)
      create :business_organization_invitation, \
        business: @business,
        inviter: @business.owners.first,
        invitee: org,
        accepted_at: Time.now

      invitation = @business.pending_organization_invitation_for(org)

      assert_equal @business, invitation.business
      assert_equal @business.owners.first, invitation.inviter
      assert_equal org, invitation.invitee
    end

    test "nil when invitee is not provided" do
      org = create(:organization)
      create :business_organization_invitation, \
        business: @business,
        inviter: @business.owners.first,
        invitee: org

      assert_nil @business.pending_organization_invitation_for
    end

    test "nil when invitee is not an organization" do
      org = create(:organization)
      create :business_organization_invitation, \
        business: @business,
        inviter: @business.owners.first,
        invitee: org

      invitation = @business.pending_organization_invitation_for(@user)
      assert_nil invitation
    end

    test "nil when no invitation exists for organization" do
      org = create(:organization)
      invitation = @business.pending_organization_invitation_for(org)
      assert_nil invitation
    end

    test "nil when invitation is confirmed" do
      org = create(:organization)
      create :business_organization_invitation, \
        business: @business,
        inviter: @business.owners.first,
        invitee: org,
        accepted_at: Time.now,
        confirmed_at: Time.now

      invitation = @business.pending_organization_invitation_for(org)
      assert_nil invitation
    end

    test "nil when invitation is canceled" do
      org = create(:organization)
      create :business_organization_invitation, \
        business: @business,
        inviter: @business.owners.first,
        invitee: org,
        canceled_at: Time.now

      invitation = @business.pending_organization_invitation_for(org)
      assert_nil invitation
    end

    test "nil when invitation is expired" do
      org = create(:organization)
      create :business_organization_invitation, \
        business: @business,
        inviter: @business.owners.first,
        invitee: org,
        expired_at: Time.now

      invitation = @business.pending_organization_invitation_for(org)
      assert_nil invitation
    end
  end

  context "set_org_upgrade_onboarding_notice" do
    test "no-ops if the business is not labelled as `upgraded_from_organization?" do
      refute_predicate @business, :upgraded_from_organization?
      @business.set_org_upgrade_onboarding_notice(initiating_owner: @business.owners.first)

      refute @business.org_upgrade_onboarding_notice_set?(@business.owners.first)
    end

    test "if no organization is passed in as the argument, the notice only gets set on the initiating owner" do
      @upgrading_business.organization_upgrade_completed!
      second_business_owner = create :user
      @upgrading_business.add_owner(second_business_owner, actor: @upgrading_business.owners.first)
      @upgrading_org.add_admin(second_business_owner)
      assert_predicate @upgrading_business, :upgraded_from_organization?

      @upgrading_business.set_org_upgrade_onboarding_notice(initiating_owner: @upgrading_business.owners.first)
      owners_with_notice_set = @upgrading_business.owners.filter do |owner|
        @upgrading_business.org_upgrade_onboarding_notice_set?(owner)
      end

      assert @upgrading_business.owners.count > 1
      refute_same_elements @upgrading_business.owners, owners_with_notice_set
      assert_equal [@upgrading_business.owners.first], owners_with_notice_set
    end

    test "if an organization is passed in, the notice gets set on all admins of the upgrading organization" do
      @upgrading_business.organization_upgrade_completed!
      second_business_owner = create :user
      @upgrading_business.add_owner(second_business_owner, actor: @upgrading_business.owners.first)
      @upgrading_org.add_admin(second_business_owner)
      assert_predicate @upgrading_business, :upgraded_from_organization?

      @upgrading_business.set_org_upgrade_onboarding_notice(initiating_owner: @upgrading_business.owners.first, organization: @upgrading_org)
      owners_with_notice_set = @upgrading_business.owners.filter do |owner|
        @upgrading_business.org_upgrade_onboarding_notice_set?(owner)
      end

      assert @upgrading_org.admins.count > 1
      assert_same_elements @upgrading_org.admins, owners_with_notice_set
    end
  end unless GitHub.single_business_environment?

  context "#upgraded_from_organization?" do
    test "returns true if the business went through a free- or team-org to EA upgrade" do
      @upgrading_business.initiate_organization_upgrade(@owner)
      @upgrading_business.initiate_organization_upgrade_purchase(@owner)
      @upgrading_business.upgrade_from_organization
      assert_predicate @upgrading_business, :organization_upgrade_completed?

      assert_predicate @upgrading_business, :upgraded_from_organization?
    end

    test "returns true if the business went through a GHEC-org to EA upgrade" do
      business_plus = create :organization, plan: GitHub::Plan.business_plus
      direct_upgraded_business = create :business, \
        :with_self_serve_payment,
        owners: business_plus.admins,
        name: "Upgraded from a business plus org",
        upgraded_at: 2.days.ago,
        upgraded_from: business_plus,
        upgraded_from_plan: business_plus.plan.name
      direct_upgraded_business.organization_direct_upgraded!
      assert_predicate direct_upgraded_business, :organization_direct_upgraded?

      assert_predicate direct_upgraded_business, :upgraded_from_organization?
    end

    test "returns false for a business that is neither a direct upgrade nor a free/team-org to EA upgrade" do
      refute_predicate @business, :organization_upgrade_completed?
      refute_predicate @business, :organization_direct_upgraded?

      refute_predicate @business, :upgraded_from_organization?
    end
  end unless GitHub.single_business_environment?

  context "#review_upgrade" do
    if GitHub.single_business_environment?
      test "returns false when in a single business environment" do
        staff = create :staff_admin_user

        refute @business.review_upgrade(staff)
        refute_predicate @business.reload, :reviewed?
      end
    else
      test "returns false if upgrade not being reviewed by staff" do
        refute_predicate @member1, :site_admin?
        refute @business.review_upgrade(@member1)
        refute_predicate @business.reload, :reviewed?
      end

      test "returns false if reviewed by staff and business wasn't upgraded from an organization" do
        staff = create :staff_admin_user

        assert_predicate staff, :site_admin?
        refute_predicate @business, :upgraded?
        refute @business.review_upgrade(staff)
        refute_predicate @business.reload, :reviewed?
      end

      test "returns true if reviewed by staff and business was upgraded from an organization" do
        staff = create :staff_admin_user
        @business.update(upgraded_at: 1.day.ago, upgraded_from: @org1)
        @business.reload

        assert_predicate staff, :site_admin?
        assert_predicate @business, :upgraded?
        assert @business.review_upgrade(staff)
        @business.reload
        assert_equal staff, @business.upgrade_reviewed_by
        assert_predicate @business, :reviewed?
      end

      test "raises AlreadyReviewedUpgradeError when attempting to review an already reviewed upgrade" do
        staff = create :staff_admin_user
        @business.update(upgraded_at: 1.day.ago, upgraded_from: @org1)
        @business.reload
        @business.review_upgrade(staff)
        @business.reload

        assert_predicate @business, :reviewed?

        assert_raises Business::AlreadyReviewedUpgradeError do
          @business.review_upgrade(staff)
        end
      end
    end
  end

  unless GitHub.single_business_environment?
    context "#upgraded?" do
      test "returns false if business was not upgraded from an organization" do
        refute_predicate @business, :upgraded?
      end

      test "returns true if business was upgraded from an organization" do
        staff = create :staff_admin_user
        @business.update(upgraded_at: 1.day.ago, upgraded_from: @org1)

        assert_predicate @business.reload, :upgraded?
      end
    end

    context "#reviewed?" do
      test "returns false if business has not been reviewed before" do
        refute_predicate @business, :reviewed?
      end

      test "returns true if business has been reviewed before" do
        staff = create :staff_admin_user
        @business.update(upgraded_at: 1.day.ago, upgraded_from: @org1)
        @business.review_upgrade(staff)

        assert_predicate @business.reload, :reviewed?
      end
    end
  end
end
