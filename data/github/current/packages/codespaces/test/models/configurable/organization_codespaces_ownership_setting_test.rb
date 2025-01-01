# typed: true
# frozen_string_literal: true

require "test_helper"

class Configurable::OrganizationCodespacesOwnershipSettingTest < GitHub::TestCase
  fixtures do
    @organization = create(:codespaces_credit_card_organization)
    @setting_user = create(:user)
    @organization.add_member(@setting_user)
    @jobs = [
      Codespaces::OrgSettingsChangedJob,
      CodespacesProcessSystemEventJob
    ]
  end

  context "managing the ownership setting" do
    test "raises error when setting is invalid" do
      assert_raises ArgumentError, /invalid organization codespaces ownership setting/ do
        @organization.update_organization_codespaces_ownership_setting("invalid limit", actor: @setting_user)
      end
    end

    test "raises error when setting is USER for emu org", skip_enterprise: true do
      emu = create(:emu)
      emu_business = emu.enterprise_managed_business
      emu_business_org = create :enterprise_linked_organization, business: emu_business, admin: emu

      assert_raises ArgumentError, /EMU enabled organizations cannot set ownership setting to User/ do
        emu_business_org.update_organization_codespaces_ownership_setting(
          Configurable::OrganizationCodespacesOwnershipSetting::USER,
          actor: emu
        )
      end
    end

    test "raises error when setting is ORGANIZATION for free org" do
      GitHub.flipper[:codespaces_billing_free].disable
      free_org = create(:organization, plan: GitHub::Plan.free)

      assert_raises ArgumentError, /Organizations on a free plan cannot set ownership setting to Organization/ do
        free_org.update_organization_codespaces_ownership_setting(
          Configurable::OrganizationCodespacesOwnershipSetting::ORGANIZATION,
          actor: free_org.owner
        )
      end
    end

    test "does not raise error when setting is ORGANIZATION for free org if they are billing free" do
      free_org = create(:organization, plan: GitHub::Plan.free)
      GitHub.flipper[:codespaces_billing_free].enable(free_org)

      free_org.update_organization_codespaces_ownership_setting(
        Configurable::OrganizationCodespacesOwnershipSetting::ORGANIZATION,
        actor: free_org.owner
      )

      assert_equal Configurable::OrganizationCodespacesOwnershipSetting::ORGANIZATION, free_org.organization_codespaces_ownership_setting
    end

    test "defaults to user when never been set if part of free org" do
      free_org = create(:organization, plan: GitHub::Plan.free, admin: @user)
      refute free_org.config.get(Configurable::OrganizationCodespacesOwnershipSetting::KEY)

      assert_equal Configurable::OrganizationCodespacesOwnershipSetting::USER, free_org.organization_codespaces_ownership_setting
    end

    test "defaults to user when would be put into user and outside collaborators from transition" do
      paid_org = create(:credit_card_organization, admin: @user)
      private_repo = create(:private_repository, owner: paid_org)
      refute paid_org.config.get(Configurable::OrganizationCodespacesOwnershipSetting::KEY)
      codespace = create(:codespace, repository: private_repo, billable_owner: @setting_user, owner: @setting_user, enable_org_access: false)

      assert_equal Configurable::OrganizationCodespacesUserLimit::ALL_USERS_AND_OUTSIDE_COLLABORATORS, paid_org.organization_codespaces_user_limit
      assert_equal Configurable::OrganizationCodespacesOwnershipSetting::USER, paid_org.organization_codespaces_ownership_setting
    end

    test "forces to organization when emu org", skip_enterprise: true do
      emu = create(:emu)
      emu_business = emu.enterprise_managed_business
      emu_business_org = create :enterprise_linked_organization, business: emu_business, admin: emu
      emu_business_org.config.set(
        Configurable::OrganizationCodespacesOwnershipSetting::KEY,
        Configurable::OrganizationCodespacesOwnershipSetting::USER,
        @setting_user
      )

      assert_equal Configurable::OrganizationCodespacesOwnershipSetting::ORGANIZATION, emu_business_org.organization_codespaces_ownership_setting
    end

    test "forces to user when enterprise disables org codespaces" do
      business = create(:business)
      Codespaces::BusinessDelegator.new(business).disable_codespaces!
      org = create(:organization, business:)
      org.config.set(
        Configurable::OrganizationCodespacesOwnershipSetting::KEY,
        Configurable::OrganizationCodespacesOwnershipSetting::ORGANIZATION,
        @setting_user
      )
      assert_equal Configurable::OrganizationCodespacesOwnershipSetting::USER, org.organization_codespaces_ownership_setting
    end

    test "updates properly" do
      @organization.update_organization_codespaces_ownership_setting(
        Configurable::OrganizationCodespacesOwnershipSetting::USER,
        actor: @setting_user
      )
      assert_equal Configurable::OrganizationCodespacesOwnershipSetting::USER, @organization.organization_codespaces_ownership_setting

      @organization.update_organization_codespaces_ownership_setting(
        Configurable::OrganizationCodespacesOwnershipSetting::ORGANIZATION,
        actor: @setting_user
      )
      assert_equal Configurable::OrganizationCodespacesOwnershipSetting::ORGANIZATION, @organization.organization_codespaces_ownership_setting
    end
  end

  context "Organization to User - transfers", skip_enterprise: true do
    test "it does transfer internal repositories to user" do
      perform_enqueued_jobs(only: @jobs) do
        @organization.update_organization_codespaces_ownership_setting(
          Configurable::OrganizationCodespacesOwnershipSetting::ORGANIZATION,
          actor: @setting_user
        )
      end
      private_repo = create(:private_repository, owner: @organization)
      codespace = create(:codespace, repository: private_repo, owner: @setting_user)
      assert_equal @organization, codespace.reload.billable_owner

      perform_enqueued_jobs(only: @jobs) do
        @organization.update_organization_codespaces_ownership_setting(
          Configurable::OrganizationCodespacesOwnershipSetting::USER,
          actor: @setting_user
        )
      end

      assert_equal @setting_user, codespace.reload.billable_owner
    end

    test "it does transfer public repositories to user" do
      perform_enqueued_jobs(only: @jobs) do
        @organization.update_organization_codespaces_ownership_setting(
          Configurable::OrganizationCodespacesOwnershipSetting::ORGANIZATION,
          actor: @setting_user
        )
      end
      public_repo = create(:public_repository, owner: @organization)
      codespace = create(:codespace, repository: public_repo, owner: @setting_user)
      assert_equal @organization, codespace.reload.billable_owner
      perform_enqueued_jobs(only: @jobs) do
        @organization.update_organization_codespaces_ownership_setting(
          Configurable::OrganizationCodespacesOwnershipSetting::USER,
          actor: @setting_user
        )
      end

      assert_equal @setting_user, codespace.reload.billable_owner
    end
  end

  context "User to Organization - transfers", skip_enterprise: true do
    test "it transfers codespaces to organization if org member" do
      @organization.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::ALL_USERS, actor: @setting_user)

      perform_enqueued_jobs(only: @jobs) do
        @organization.update_organization_codespaces_ownership_setting(
          Configurable::OrganizationCodespacesOwnershipSetting::USER,
          actor: @setting_user
        )
      end
      public_repo = create(:public_repository, owner: @organization)
      codespace = create(:codespace, repository: public_repo, owner: @setting_user, enable_org_access: false)
      assert_equal @setting_user, codespace.reload.billable_owner

      perform_enqueued_jobs(only: @jobs) do
        @organization.update_organization_codespaces_ownership_setting(
          Configurable::OrganizationCodespacesOwnershipSetting::ORGANIZATION,
          actor: @setting_user
        )
      end

      assert_equal @organization, codespace.reload.billable_owner
    end

    test "it transfers codespaces to organization if outside collaborator" do
      @organization.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::ALL_USERS_AND_OUTSIDE_COLLABORATORS, actor: @setting_user)

      perform_enqueued_jobs(only: @jobs) do
        @organization.update_organization_codespaces_ownership_setting(
          Configurable::OrganizationCodespacesOwnershipSetting::USER,
          actor: @setting_user
        )
      end
      public_repo = create(:public_repository, owner: @organization)
      collaborator = create(:user)
      codespace = create(:codespace, repository: public_repo, owner: collaborator, enable_org_access: false, make_collaborator: true)
      assert_equal collaborator, codespace.reload.billable_owner

      perform_enqueued_jobs(only: @jobs) do
        @organization.update_organization_codespaces_ownership_setting(
          Configurable::OrganizationCodespacesOwnershipSetting::ORGANIZATION,
          actor: @setting_user
        )
      end

      assert_equal @organization, codespace.reload.billable_owner
    end

    test "it does not transfer codespaces to organization if not part of org" do
      # Note: in reality they would not be able to create a codespace in the first place
      @organization.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::ALL_USERS_AND_OUTSIDE_COLLABORATORS, actor: @setting_user)

      perform_enqueued_jobs(only: @jobs) do
        @organization.update_organization_codespaces_ownership_setting(
          Configurable::OrganizationCodespacesOwnershipSetting::USER,
          actor: @setting_user
        )
      end
      public_repo = create(:public_repository, owner: @organization)
      collaborator = create(:user)
      codespace = create(:codespace, repository: public_repo, owner: collaborator, enable_org_access: false, make_collaborator: false)
      assert_equal collaborator, codespace.reload.billable_owner

      perform_enqueued_jobs(only: @jobs) do
        @organization.update_organization_codespaces_ownership_setting(
          Configurable::OrganizationCodespacesOwnershipSetting::ORGANIZATION,
          actor: @setting_user
        )
      end

      assert_equal collaborator, codespace.reload.billable_owner
    end
  end
end
