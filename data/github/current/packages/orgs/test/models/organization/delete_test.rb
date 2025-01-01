# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationDeleteTest < GitHub::TestCase
  include ActiveJob::TestHelper
  include ApiProgrammaticGrantHelpers
  include AuditLog::IntegrationTestHelpers
  include HydroTestHelpers
  include HookIntegrationTestHelper

  fixtures do
    GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?
    @org_admin = create :user, login: "org-admin"
    @org = create :organization, :with_account_screening_profile, admin: @org_admin
    @credit_card_org = create :credit_card_org, :with_account_screening_profile, admin: @org_admin
    @staff = create :staff_admin_user

    @business = Business.first || create(:business)
    @business.seats = 100
    @business.save

    @business_org = create(:organization, business: @business)
    @business_org.add_admin(@org_admin)
    @business_org_repo = create(:repository, :minimal, owner: @business_org)
    @business_org_repo_private = create(:private_repository, owner: @business_org)
  end

  context "#permit_deletion?" do
    test "returns false for trade controls restricted orgs for admin actor" do
      @org.trade_controls_restriction.full!

      refute @org.permit_deletion?(@org_admin)
    end

    test "returns true for trade controls restricted orgs for staff actor" do
      @org.trade_controls_restriction.full!

      assert @org.permit_deletion?(@staff)
    end

    test "returns false for trade screening restricted orgs for admin actor" do
      @org.trade_screening_record.hit_in_review!

      refute @org.permit_deletion?(@org_admin)
    end

    test "returns false for trade screening restricted orgs for staff actor" do
      @org.trade_screening_record.hit_in_review!

      refute @org.permit_deletion?(@staff)
    end

    test "returns false when a legal hold exists even for staff actor" do
      assert @org.permit_deletion?(@org)
      assert @org.permit_deletion?(@staff)

      @org.place_legal_hold(actor: @staff)
      assert @org.reload.legal_hold?
      refute @org.permit_deletion?(@org)
      refute @org.permit_deletion?(@staff)

      @org.clear_legal_hold(actor: @staff)
      refute @org.reload.legal_hold?
      assert @org.permit_deletion?(@org)
      assert @org.permit_deletion?(@staff)
    end
  end

  context "#cannot_delete_reason" do
    test "returns nil when deletion permitted" do
      assert @org.permit_deletion?(@org_admin)
      assert_nil @org.cannot_delete_reason(@org_admin)
    end

    test "returns :trusted_oauth_apps_owner when expected" do
      @org.stubs(:trusted_oauth_apps_owner?).returns(true)
      assert_equal :trusted_oauth_apps_owner, @org.cannot_delete_reason(@org_admin)
      assert_equal :trusted_oauth_apps_owner, @org.cannot_delete_reason(@staff)
    end

    test "returns :sponsorable when expected" do
      @org.stubs(:sponsorable?).returns(true)
      assert_equal :sponsorable, @org.cannot_delete_reason(@org_admin)
      assert_equal :sponsorable, @org.cannot_delete_reason(@staff)
    end

    test "returns :legal_hold when expected" do
      @org.stubs(:legal_hold?).returns(true)
      assert_equal :legal_hold, @org.cannot_delete_reason(@org_admin)
      assert_equal :legal_hold, @org.cannot_delete_reason(@staff)
    end

    test "returns nil when actor is site admin" do
      assert @org.permit_deletion?(@staff)
      assert_nil @org.cannot_delete_reason(@staff)
    end

    test "returns :trade_restrictions for trade controls restricted user" do
      @org.stubs(:has_any_trade_restrictions?).returns(true)
      assert_equal :trade_restrictions, @org.cannot_delete_reason(@org_admin)
    end

    test "returns :trade_restrictions for trade screening restricted user" do
      @org.trade_screening_record.stubs(:delete_restricted?).returns(true)
      assert_equal :trade_restrictions, @org.cannot_delete_reason(@org_admin)
    end

    test "returns :repo_deletion_not_allowed when expected" do
      @org.stubs(:repo_deletion_allowed?).returns(false)
      assert_equal :repo_deletion_not_allowed, @org.cannot_delete_reason(@org_admin)
    end

    test "returns :system_account when expected" do
      @org.stubs(:system_account?).returns(true)
      assert_equal :system_account, @org.cannot_delete_reason(@org_admin)
    end

    test "returns :spammy when expected" do
      @org.stubs(:spammy?).returns(true)
      @org.stubs(:spammy_deleting_overridden?).returns(false)
      assert_equal :spammy, @org.cannot_delete_reason(@org_admin)
    end

    test "returns nil when spammy but spammy deletion is overridden" do
      @org.stubs(:spammy?).returns(true)
      @org.stubs(:spammy_deleting_overridden?).returns(true)
      assert_nil @org.cannot_delete_reason(@org_admin)
    end

    test "returns nil when organization is soft-deleted" do
      @org.soft_delete!(@org_admin)
      assert_predicate @org, :soft_deleted?
      assert_nil @org.cannot_delete_reason(@org_admin)
    end

    if GitHub.sponsors_enabled?
      test "returns :sponsorable when org has active sponsorships" do
        sponsors_listing = create(:sponsors_listing, :approved, sponsorable: @org)
        create(:sponsorship, sponsorable: @org)
        refute_empty @org.sponsorships_as_sponsorable
        assert_equal :sponsorable, @org.cannot_delete_reason(@org_admin)
      end

      test "returns :sponsorable for site admin when org has active sponsorships" do
        sponsors_listing = create(:sponsors_listing, :approved, sponsorable: @org)
        create(:sponsorship, sponsorable: @org)
        refute_empty @org.sponsorships_as_sponsorable
        assert_equal :sponsorable, @org.cannot_delete_reason(@org_admin)
      end

      test "returns :sponsorable for site admin when org has active sponsorship" do
        sponsors_listing = create(:sponsors_listing, :approved, sponsorable: @org)
        create(:sponsorship, sponsorable: @org)
        refute_empty @org.sponsorships_as_sponsorable
        assert_equal :sponsorable, @org.cannot_delete_reason(@staff)
      end

      test "returns :sponsors_listing_not_deletable when org was previously sponsored" do
        sponsors_listing = create(:sponsors_listing, :approved, sponsorable: @org)
        sponsorship = create(:sponsorship, sponsorable: @org)
        sponsorship.cancel(actor: @org, force: true)
        sponsors_listing.redraft!
        refute_empty @org.reload.sponsorships_as_sponsorable
        assert_equal :sponsors_listing_not_deletable, @org.cannot_delete_reason(@org_admin)
      end

      test "returns nil if previously sponsored but listing has since been deleted" do
        sponsors_listing = create(:sponsors_listing, :approved, sponsorable: @org)
        sponsorship = create(:sponsorship, sponsorable: @org)
        refute_empty @org.sponsorships_as_sponsorable

        sponsorship.cancel(actor: @org_admin, force: true)
        sponsors_listing.redraft!
        sponsors_listing.deletion_confirmation = @org.display_login
        sponsors_listing.destroy!

        assert_nil @org.reload.cannot_delete_reason(@org_admin)
      end

      test "returns nil if org has an unpublished listing but has never been sponsored" do
        sponsors_listing = create(:sponsors_listing, :draft, sponsorable: @org)
        assert_empty @org.sponsorships_as_sponsorable
        assert_nil @org.cannot_delete_reason(@org_admin)
      end
    end

    test "returns nil if org does not have a sponsors listing" do
      assert_nil @org.sponsors_listing
      assert_nil @org.cannot_delete_reason(@org_admin)
    end
  end

  context "#async_destroy" do
    test "marks user as deleted" do
      org_admin = create(:user, login: "first-admin")
      org = create(:organization, admin: org_admin, plan: "bronze", business: GitHub.global_business)

      second_admin = create(:user)
      second_admin.stubs(:site_admin?).returns(false)

      org.add_admin second_admin

      org.async_destroy(second_admin)

      assert org.deleted
      assert_equal org.deleted_by, second_admin.login
    end

    test "removes all owned OAuth applications" do
      GitHub.context.push(actor_id: @org_admin.id)
      org_app = create :oauth_application, user: @org
      other_app = create :oauth_application
      perform_enqueued_jobs(only: [UserDeleteJob]) do
        @org.async_destroy
      end
      refute OauthApplication.exists?(org_app.id)
      assert OauthApplication.exists?(other_app.id)
    end

    test "removes all tokens for owned OAuth applications" do
      GitHub.context.push(actor_id: @org_admin.id)
      org_app = create :oauth_application, user: @org
      other_app = create :oauth_application
      org_app_token = create :oauth_access, user: create(:user), application: org_app
      other_app_token = create :oauth_access, user: create(:user), application: other_app
      perform_enqueued_jobs(only: [UserDeleteJob]) do
        @org.async_destroy
      end
      refute OauthAccess.exists?(org_app_token.id)
      assert OauthAccess.exists?(other_app_token.id)
    end

    test "removes all teams" do
      child_team = create(:team, organization: @org, privacy: :closed)
      team = create(:team, organization: @org, privacy: :closed)
      child_team.update_attribute(:parent_team_id, team.id)

      perform_enqueued_jobs(only: [UserDeleteJob]) do
        @org.async_destroy
      end

      refute Team.find_by(id: team.id), "Parent team #{team.name} should be removed."
      refute Team.find_by(id: child_team.id), "Child team #{child_team.name} should be removed."
    end

    test "deletes org when repo count > 1" do
      org_with_repos = create(:organization)
      create(:repository, :minimal, owner: org_with_repos)
      perform_enqueued_jobs(only: [UserDeleteJob]) { org_with_repos.async_destroy }

      refute Organization.find_by(id: org_with_repos.id), "expect organization to be destroyed"
    end

    test "works even when the org has a sanctioned billing email" do
      refute @org.deleted
      @org.billing_email = "test-user@justice.ir"
      refute_predicate @org, :valid?

      @org.async_destroy

      assert @org.deleted
    end

    test "removes Business::OrganizationMembership when owned by an enterprise account" do
      business_org_count = @business.organizations.count
      perform_enqueued_jobs only: [UserDeleteJob] do
        @business_org.async_destroy
      end

      assert_nil \
        Business::OrganizationMembership.find_by(organization_id: @business_org.id),
        "Business::OrganizationMembership should have been removed"
      assert_equal \
        business_org_count - 1,
        @business.reload.organizations.count
    end

    if GitHub.enterprise?
      test "does not delete org when repo count > 1 and repository deletion is disabled on the appliance" do
        GitHub.global_business.disallow_members_can_delete_repositories(force: true, actor: @org_admin)

        org_with_repos = create(:organization)
        create(:repository, :minimal, owner: org_with_repos)
        only = []
        perform_enqueued_jobs(only: only) { org_with_repos.async_destroy }

        assert Organization.find_by(id: org_with_repos.id), "did not expect organization to be destroyed"
      end

      test "does not delete org when repo count > 1, repository deletion is disabled on the appliance, and actor is not a site admin" do
        GitHub.global_business.disallow_members_can_delete_repositories(force: true, actor: @org_admin)

        org_admin = create(:user)

        org_with_repos = create :organization, admin: org_admin
        create(:repository, :minimal, owner: org_with_repos)
        only = []
        perform_enqueued_jobs(only: only) { org_with_repos.async_destroy(org_admin) }

        assert Organization.find_by(id: org_with_repos.id), "did not expect organization to be destroyed"
      end

      test "deletes org when repo count == 0 and repository deletion is disabled on the appliance" do
        GitHub.global_business.disallow_members_can_delete_repositories(force: true, actor: @org_admin)

        org_with_no_repos = create(:organization)
        perform_enqueued_jobs(only: [UserDeleteJob]) { org_with_no_repos.async_destroy }

        refute Organization.find_by(id: org_with_no_repos.id), "expect organization to be destroyed"
      end

      test "deletes org when repo count > 1, repository deletion is disabled on the appliance, and actor is a site admin" do
        GitHub.global_business.disallow_members_can_delete_repositories(force: true, actor: @org_admin)

        site_admin = create :staff_admin_user

        org_with_repos = create(:organization)
        create(:repository, :minimal, owner: org_with_repos)
        perform_enqueued_jobs(only: [UserDeleteJob]) { org_with_repos.async_destroy(site_admin) }

        refute Organization.find_by(id: org_with_repos.id), "expect organization to be destroyed"
      end
    end
  end

  context "#destroy" do
    test "destroying a suspended organisation sends no deletion confirmation email" do
      organisation = create(:suspended_org)
      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        ActionMailer::Base.deliveries.clear
        organisation.destroy

        assert_equal 0, ActionMailer::Base.deliveries.size
      end
    end

    test "destroying a gh_role of staff_delete organisation sends no deletion confirmation email" do
      organisation = create(:organization, gh_role: "staff_delete")

      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        ActionMailer::Base.deliveries.clear
        organisation.destroy

        assert_equal 0, ActionMailer::Base.deliveries.size
      end
    end

    test "destroying a spammy organisation sends no deletion confirmation email" do
      spammyorg = create(:organization, spammy: true).reload

      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        ActionMailer::Base.deliveries.clear
        spammyorg.destroy

        assert_equal 0, ActionMailer::Base.deliveries.size
      end
    end

    test "destroying an organisation removes associated programmatic access grants and requests" do
      organisation = create(:organization)

      admin = create(:user)
      organisation.add_admin(admin)

      member = create(:user)
      organisation.add_member(member)

      granted_pat = create(:user_programmatic_access, :org_grants, owner: admin, org: organisation)
      grant = granted_pat.grant
      refute_nil grant

      pending_pat = make_user_programmatic_access_with_grant_request(
        actor: member, target: organisation, permissions: { "members" => :read }
      )
      request = pending_pat.grant_request
      refute_nil request

      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        organisation.destroy

        assert UserProgrammaticAccess.exists?(granted_pat.id)
        assert UserProgrammaticAccess.exists?(pending_pat.id)

        refute OrganizationProgrammaticAccessGrant.exists?(grant.id)
        refute OrganizationProgrammaticAccessGrantRequest.exists?(request.id)
      end
    end

    test "deletes custom property definitions" do
      org = create(:organization)
      CustomPropertyDefinition.create(source: org, property_name: "environment", value_type: "string")
      assert_equal CustomPropertyDefinition.for(org).count, 1

      org_to_keep = create(:organization)
      CustomPropertyDefinition.create(source: org_to_keep, property_name: "environment", value_type: "string")
      assert_equal CustomPropertyDefinition.for(org_to_keep).count, 1

      org.destroy!

      assert_equal CustomPropertyDefinition.for(org).count, 0
      assert_equal CustomPropertyDefinition.for(org_to_keep).count, 1
    end

    test "instruments org.destroy event for soft deleted org" do
      @org.soft_delete!(@org_admin)
      assert_predicate @org, :soft_deleted?

      events = assert_performed_audit_entries(count: 1, only: "org.destroy") do
        @org.destroy!
      end

      plan = GitHub.enterprise? ? "enterprise" : "free"
      expected_payload = {
        action: "org.destroy",
        org: @org.login,
        org_id: @org.id,
        email: @org.billing_email,
        plan: plan
      }

      assert_subset_hash expected_payload, events.first
    end

    test "instruments org.delete event for org not soft deleted" do
      refute_predicate @org, :soft_deleted?

      events = assert_performed_audit_entries(count: 1, only: "org.delete") do
        @org.destroy!
      end

      plan = GitHub.enterprise? ? "enterprise" : "free"
      expected_payload = {
        action: "org.delete",
        org: @org.login,
        org_id: @org.id,
        email: @org.billing_email,
        plan: plan,
        admin_ids: @org.admins.map(&:id),
        admins: @org.admins.map(&:login)
      }

      assert_subset_hash expected_payload, events.first
    end

    unless GitHub.enterprise?
      test "destroying a organisation sends deletion confirmation email" do
        organisation = create(:free_org)

        perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
          ActionMailer::Base.deliveries.clear
          organisation.destroy

          # Should send one email to the user and another to the logging address
          assert_equal 2, ActionMailer::Base.deliveries.size

          subject = ActionMailer::Base.deliveries[0].subject
          assert_match "Organization deletion", subject
        end
      end

      test "destroying a organisation sends deletion confirmation email to correct bcc list" do
        organisation = create(:free_org)
        email = organisation.admin.email
        logs_email = "logs@github.com"

        perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
          ActionMailer::Base.deliveries.clear
          organisation.destroy

          bcc_list = ActionMailer::Base.deliveries[0].bcc
          assert_equal 2, bcc_list.size
          assert_includes bcc_list, email
          assert_includes bcc_list, logs_email
        end
      end

      test "destroying a organisation sends deletion confirmation email to all admins" do
        organisation = create(:free_org)

        admin_member_one = create(:user)
        admin_member_two = create(:user)
        organisation.add_admin admin_member_one
        organisation.add_admin admin_member_two
        organisation.reload

        perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
          ActionMailer::Base.deliveries.clear
          organisation.destroy

          bcc_list = ActionMailer::Base.deliveries[0].bcc
          assert_equal 4, bcc_list.size
          assert_includes bcc_list, admin_member_one.email
          assert_includes bcc_list, admin_member_two.email
        end
      end

      test "destroying a soft-deleted organization does not send a confirmation email" do
        organisation = create(:free_org)
        organisation.soft_delete!(organisation.admin)

        perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
          ActionMailer::Base.deliveries.clear
          organisation.destroy

          assert_equal 0, ActionMailer::Base.deliveries.size
        end
      end
    end
  end

  context "#soft_delete!" do
    test "marks standalone org as soft deleted" do
      org = create :organization
      refute_predicate org, :soft_deleted?
      assert_nil org.soft_deleted_at

      org.soft_delete!

      assert_predicate org, :soft_deleted?
      refute_nil org.soft_deleted_at
    end

    test "marks business-owned org as soft deleted" do
      org = create :organization, business: @business
      refute_predicate org, :soft_deleted?
      assert_nil org.soft_deleted_at

      org.soft_delete!

      assert_predicate org, :soft_deleted?
      refute_nil org.soft_deleted_at
    end

    test "removes all repos when soft deleted" do
      org = create :organization
      pub_repo = create :public_repository, owner: org
      priv_repo = create :private_repository, owner: org

      assert_equal 2, org.repositories.count
      assert_equal 0, org.deleted_repositories.count

      perform_enqueued_jobs only: [SoftDeleteOrganizationRepositoriesJob] do
        org.soft_delete!
      end

      assert_equal 0, org.repositories.count
      assert_equal 2, org.deleted_repositories.count
    end

    test "removes all projects when soft deleted" do
      user = create :verified_user
      org = create :organization, admin: user
      org_memex1 = create :memex_project, owner: org, creator: user
      org_memex2 = create :memex_project, owner: org, creator: user

      assert_difference({
        "org.memex_projects.active_projects.count" => -2,
        "org.memex_projects.deleted_projects.count" => 2
        }) do
          perform_enqueued_jobs only: [SoftDeleteOrganizationProjectsJob] do
            org.soft_delete!(user)
          end
        end
    end

    test "instruments org.delete event" do
      events = assert_performed_audit_entries(count: 1, only: "org.delete") do
        @org.soft_delete!(@org_admin)
      end

      expected_payload = {
        action: "org.delete",
        email: @org.billing_email,
        org: @org.login,
        org_id: @org.id,
        actor: @org_admin.login,
        actor_id: @org_admin.id,
        admin_ids: @org.admins.map(&:id),
        admins: @org.admins.map(&:login)
      }

      assert_subset_hash expected_payload, events.first
    end

    test "delivers enterprise installed webhook when org is soft-deleted" do
      hook = create :hook, :org, installation_target: @business, events: %w(organization)
      deliveries = subscribe_to_hook_delivery "organization"
      org_login = @business_org.login
      assert_equal 0, deliveries.count

      perform_enqueued_jobs(only: [DeliverHookEventJob]) do
        @business_org.soft_delete!(@org_admin)
      end

      assert_equal 1, deliveries.count
      payload = deliveries.payload_for_hook(hook)

      assert_equal "deleted", payload[:action]
      assert_equal @org_admin.login, payload[:sender][:login]
      assert_equal org_login, payload[:organization][:login]
      assert_equal @business.slug, payload[:enterprise][:slug]
      assert_nil payload[:triggered_at]
    end

    test "delivers org installed webhook when org is soft-deleted" do
      hook = create :hook, :org, installation_target: @org, events: %w(organization)
      deliveries = subscribe_to_hook_delivery "organization"
      org_login = @org.login
      assert_equal 0, deliveries.count

      perform_enqueued_jobs(only: [DeliverHookEventJob]) do
        @org.soft_delete!(@org_admin)
      end

      assert_equal 1, deliveries.count
      payload = deliveries.payload_for_hook(hook)

      assert_equal "deleted", payload[:action]
      assert_equal @org_admin.login, payload[:sender][:login]
      assert_equal org_login, payload[:organization][:login]
      assert_nil payload[:triggered_at]
    end

    test "resets billing attempts and disables auto-pay for standalone org", skip_enterprise: true do
      @credit_card_org.update(billing_attempts: 3)
      @credit_card_org.soft_delete!

      assert @credit_card_org.reload.billing_attempts.zero?
      assert_includes @credit_card_org.auto_pay_reasons, :customer_initiated
    end

    test "cancels pending plan changes for standalone org", skip_enterprise: true do
      create :billing_pending_plan_change, user: @credit_card_org, plan_duration: "month", plan: "business"

      assert_equal 1, @credit_card_org.incomplete_pending_plan_changes.count
      @credit_card_org.soft_delete!
      assert_empty @credit_card_org.reload.incomplete_pending_plan_changes
    end

    test "doesn't disable auto-pay for orgs already disabled due to RBI", skip_enterprise: true do
      @credit_card_org.disable_auto_pay!(:india_rbi)
      @credit_card_org.soft_delete!
      refute_includes @credit_card_org.reload.auto_pay_reasons, :customer_initiated
    end

    test "enqueues job to suspend org billing", skip_enterprise: true do
      create :billing_plan_subscription, user: @org
      refute_predicate @org, :delegate_billing_to_business?

      assert_enqueued_with job: SuspendPlanSubscriptionJob, args: [@org.plan_subscription] do
        @org.soft_delete!(@org_admin)
      end
    end

    test "removes Business::OrganizationMembership when owned by an enterprise account" do
      @business_org.soft_delete!

      refute Business::OrganizationMembership.find_by(organization_id: @business_org.id)
      refute_includes @business.reload.organizations, @business_org
      assert_includes @business.soft_deleted_organizations, @business_org
    end

    test "does not remove Business::OrganizationMembership when remove_from_business is used", skip_enterprise: true do
      @business_org.soft_delete!(remove_from_business: false)

      assert Business::OrganizationMembership.find_by(organization_id: @business_org.id)
      refute_includes @business.reload.organizations, @business_org
      assert_includes @business.soft_deleted_organizations, @business_org
    end

    test "does not remove Business::OrganizationMembership for EMU owned soft-deleted orgs", skip_enterprise: true, skip_emu: true do
      emu = create :emu
      emu_business = emu.enterprise_managed_business
      emu_org = create :enterprise_linked_organization, business: emu_business, admin: emu

      emu_org.soft_delete!

      assert Business::OrganizationMembership.find_by(organization_id: emu_org.id, business_id: emu_business.id)
      refute_includes emu_business.reload.organizations, emu_org
      assert_includes emu_business.soft_deleted_organizations, emu_org
    end

    unless GitHub.single_business_environment?
      test "soft-deleting an organisation sends deletion confirmation email" do
        ano_admin = create(:user, login: "another-admin")
        @org.add_admin ano_admin

        perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
          ActionMailer::Base.deliveries.clear
          @org.soft_delete!(@org_admin)

          # Should send one email to the user and another to the logging address
          assert_equal 2, ActionMailer::Base.deliveries.size

          subject = ActionMailer::Base.deliveries[0].subject
          assert_match "Organization deletion", subject
          bcc_list = ActionMailer::Base.deliveries[0].bcc
          assert_equal 3, bcc_list.size
          assert_includes bcc_list, ano_admin.email
        end
      end

      test "soft-deleting an organization as site admin does not send deletion confirmation email" do
        ano_admin = create(:user, login: "another-admin")
        @org.add_admin ano_admin

        assert_no_difference "ActionMailer::Base.deliveries.size" do
          @org.soft_delete!(@org_admin, site_admin_deletion: true)
        end
      end
    end

    context "#soft_deleted?" do
      test "returns false when not soft deleted" do
        refute_predicate @org, :soft_deleted?
      end

      test "returns true when soft deleted" do
        SoftDeletedOrganization.create!(organization: @org)
        assert_predicate @org, :soft_deleted?
      end

      test "avoids n+1 when checking for soft_deleted?" do
        create(:organization, :soft_deleted, login: "org1")
        create(:organization, :soft_deleted, login: "org2")
        create(:organization, :soft_deleted, login: "org3")
        create(:organization, :soft_deleted, login: "org4")

        assert_query_count(2, ignore_feature_flags: true) do
          assert Organization
            .includes(:soft_deleted_organization)
            .where(login: %w[org1 org2 org3 org4])
            .all?(&:soft_deleted?)
        end
      end
    end

    context "#mark_not_deleted" do
      test "removes SoftDeletedOrganization when undeleting" do
        @org.soft_delete!
        assert_predicate @org, :soft_deleted?
        assert @org.mark_not_deleted
        refute_predicate @org.reload, :soft_deleted?
        assert_nil @org.soft_deleted_at
      end

      test "enables auto-pay when undeleting", skip_enterprise: true do
        @credit_card_org.soft_delete!
        assert_includes @credit_card_org.auto_pay_reasons, :customer_initiated
        @credit_card_org.mark_not_deleted
        refute_includes @credit_card_org.auto_pay_reasons, :customer_initiated
      end

      test "does not enable auto-pay when restoring if previously disabled due to RBI", skip_enterprise: true do
        @credit_card_org.disable_auto_pay!(:india_rbi)
        @credit_card_org.soft_delete!
        refute_includes @credit_card_org.reload.auto_pay_reasons, :customer_initiated
        @credit_card_org.mark_not_deleted
        refute_includes @credit_card_org.reload.auto_pay_reasons, :customer_initiated
        assert_includes @credit_card_org.auto_pay_reasons, :india_rbi
      end

      test "emits `organization.restore` Hydro event when restoring a soft-deleted org" do
        SoftDeletedOrganization.create!(organization: @org, created_at: 10.minutes.ago)
        @org.mark_not_deleted(actor: @org_admin)

        assert_hydro_published({
          actor: Hydro::EntitySerializer.user(@org_admin),
          organization: Hydro::EntitySerializer.organization(@org),
          customer_id: Licensing::Customer.id_for(@org),
        }, schema: "github.v1.OrganizationRestore")
      end

      test "restores repos removed from org when soft-deleted" do
        SoftDeletedOrganization.create!(organization: @org, created_at: 10.minutes.ago)
        pub_repo = create :public_repository, owner: @org
        priv_repo = create :private_repository, owner: @org
        pub_repo.remove(@actor, synchronous: true)
        priv_repo.remove(@actor, synchronous: true)

        assert_equal 0, @org.repositories.count
        assert_equal 2, @org.deleted_repositories.count

        perform_enqueued_jobs only: [RestoreSoftDeletedOrganizationRepositoriesJob] do
          @org.mark_not_deleted
        end

        assert_equal 2, @org.reload.repositories.count
        assert_equal 0, @org.reload.deleted_repositories.count
      end

      test "does not restore repos removed prior to the soft-deletion" do
        pub_repo = create :public_repository, owner: @org
        pub_repo.remove(@actor, synchronous: true)
        pub_repo.update!(deleted_at: 15.minutes.ago)

        SoftDeletedOrganization.create!(organization: @org)

        priv_repo = create :private_repository, owner: @org
        priv_repo.remove(@actor, synchronous: true)

        assert_equal 0, @org.repositories.count
        assert_equal 2, @org.deleted_repositories.count

        perform_enqueued_jobs only: [RestoreSoftDeletedOrganizationRepositoriesJob] do
          @org.mark_not_deleted
        end

        assert_equal 1, @org.repositories.count
        assert_equal 1, @org.deleted_repositories.count
      end

      test "does not run restore repo job if org was not soft-deleted" do
        @org.update!(deleted_at: Time.now)

        assert_no_enqueued_jobs only: RestoreSoftDeletedOrganizationRepositoriesJob do
          @org.mark_not_deleted
        end
      end

      test "restores projects removed from org when soft-deleted" do
        SoftDeletedOrganization.create!(organization: @org, created_at: 6.minutes.ago)
        user = create :verified_user
        org_memex1 = create :memex_project, owner: @org, creator: user, deleted_at: 5.minutes.ago, deleted_by: user
        org_memex2 = create :memex_project, owner: @org, creator: user, deleted_at: 5.minutes.ago, deleted_by: user

        assert_difference({
          "@org.memex_projects.active_projects.count" => 2,
          "@org.memex_projects.deleted_projects.count" => -2
          }) do
            perform_enqueued_jobs only: [RestoreSoftDeletedOrganizationProjectsJob] do
              @org.mark_not_deleted
            end
          end
      end

      test "does not restore projects removed prior to the soft-deletion" do
        SoftDeletedOrganization.create!(organization: @org, created_at: 6.minutes.ago)
        user = create :verified_user
        org_memex1 = create :memex_project, owner: @org, creator: user, deleted_at: 5.minutes.ago, deleted_by: user
        org_memex2 = create :memex_project, owner: @org, creator: user, deleted_at: 20.minutes.ago, deleted_by: user

        assert_difference({
          "@org.memex_projects.active_projects.count" => 1,
          "@org.memex_projects.deleted_projects.count" => -1
          }) do
            perform_enqueued_jobs only: [RestoreSoftDeletedOrganizationProjectsJob] do
              @org.mark_not_deleted
            end
          end
      end

      test "does not run restore project job if org was not soft-deleted" do
        @org.update!(deleted_at: Time.now)

        assert_no_enqueued_jobs only: RestoreSoftDeletedOrganizationProjectsJob do
          @org.mark_not_deleted
        end
      end

      if GitHub.billing_enabled?
        test "enqueues job to resume billing for soft deleted standalone org" do
          plan_subscription = create :billing_plan_subscription, user: @credit_card_org
          @credit_card_org.create_soft_deleted_organization(
            organization: @credit_card_org,
            created_at: Organization::RESTORABLE_PERIOD.ago
          )
          assert_predicate @credit_card_org.reload, :soft_deleted?
          refute_predicate @credit_card_org, :delegate_billing_to_business?

          assert_enqueued_with job: ResumePlanSubscriptionJob, args: [plan_subscription] do
            @credit_card_org.mark_not_deleted
          end
        end

        test "does not enqueue job to resume billing for standalone org not soft deleted" do
          plan_subscription = create :billing_plan_subscription, user: @credit_card_org
          refute_predicate @credit_card_org, :soft_deleted?
          refute_predicate @credit_card_org, :delegate_billing_to_business?

          assert_no_enqueued_jobs only: ResumePlanSubscriptionJob do
            @credit_card_org.mark_not_deleted
          end
        end

        test "does not enqueue job to resume billing for soft deleted business owned org" do
          @business_org.create_soft_deleted_organization(
            organization: @business_org,
            created_at: Organization::RESTORABLE_PERIOD.ago
          )
          assert_predicate @business_org.reload, :soft_deleted?
          assert_predicate @business_org, :delegate_billing_to_business?

          assert_no_enqueued_jobs only: ResumePlanSubscriptionJob do
            @business_org.mark_not_deleted
          end
        end

        test "restores business org to the business" do
          @business_org.soft_delete!
          assert_predicate @business_org.reload, :soft_deleted?

          refute_includes @business.organizations, @business_org

          @business_org.mark_not_deleted

          refute_predicate @business_org.reload, :soft_deleted?
          assert_includes @business.organizations, @business_org
        end

        test "does not restore org if business does not have enough licenses" do
          @business_org.soft_delete!
          assert_predicate @business_org.reload, :soft_deleted?

          @business.update! seats: 1
          refute_includes @business.organizations, @business_org
          refute @business.has_sufficient_licenses_for_organization?(@business_org)

          error_message_seat_count = @business.additional_licenses_required_for_organization(@business_org)
          assert_raises_with_message(
            Organization::OrganizationRestorationError,
            "Insufficient seats to add this organization (#{error_message_seat_count} seats required to add #{@business_org.display_login}, #{error_message_seat_count} more must be purchased for the enterprise account)") do
            @business_org.mark_not_deleted
          end

          assert_predicate @business_org.reload, :soft_deleted?
          refute_includes @business.organizations, @business_org
        end

        test "restores business org to the business when soft-delete has business ID" do
          new_business_org = create(:organization)
          # Org wasn't part of the business but SoftDeletedOrganization.create! sets the business ID
          # This simulates the org was removed from the business during deletion
          SoftDeletedOrganization.create!(organization: new_business_org, business: @business)
          assert_predicate new_business_org, :soft_deleted?

          refute_includes @business.organizations, new_business_org

          new_business_org.mark_not_deleted

          refute_predicate new_business_org.reload, :soft_deleted?
          assert_includes @business.organizations, new_business_org
        end

        test "raises error if the business cannot restore a soft-deleted org" do
          new_business_org = create(:organization)
          # Org wasn't part of the business but SoftDeletedOrganization.create! sets the business ID
          # This simulates the org was removed from the business during deletion
          SoftDeletedOrganization.create!(organization: new_business_org, business: @business)
          assert_predicate new_business_org, :soft_deleted?

          refute_includes @business.organizations, new_business_org

          Business.any_instance.stubs(:has_sufficient_licenses_for_organization?).returns(false)

          exception = assert_raises Organization::OrganizationRestorationError do
            new_business_org.mark_not_deleted
          end

          assert_includes exception.message, "Insufficient seats to add this organization"
        end

        test "does not enqueue job to resume billing for business owned org not soft deleted" do
          refute_predicate @business_org.reload, :soft_deleted?
          assert_predicate @business_org, :delegate_billing_to_business?

          assert_no_enqueued_jobs only: ResumePlanSubscriptionJob do
            @business_org.mark_not_deleted
          end
        end
      end
    end

    context "active scope" do
      test "only returns active orgs" do
        soft_deleted_org = create :organization, login: "soft-deleted-org"
        SoftDeletedOrganization.create!(organization: soft_deleted_org)

        assert_includes Organization.active, @org
        refute_includes Organization.active, soft_deleted_org
      end
    end

    context "soft_deleted scope" do
      test "only returns soft deleted orgs" do
        SoftDeletedOrganization.create!(organization: @org)
        assert_predicate @org, :soft_deleted?
        refute_predicate @business_org, :soft_deleted?
        assert_includes Organization.soft_deleted, @org
        refute_includes Organization.soft_deleted, @business_org
      end
    end

    context "purgeable scope" do
      test "only returns users with soft_deleted_at value earlier than restorable period ago" do
        refute_includes Organization.purgeable, @org
        soft_deleted = SoftDeletedOrganization.create!(organization: @org)
        refute_includes Organization.purgeable, @org

        soft_deleted.update! created_at: (Organization::RESTORABLE_PERIOD + 2.days).ago
        assert_includes Organization.purgeable, @org
      end
    end
  end
end
