# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesOrgPolicyTest < GitHub::TestCase
  fixtures do
    # Set up a user with access to an org-owned private repo
    @admin_user = create(:user)
    @org_with_codespaces_enabled = create(:codespaces_organization, :selected_members, admin: @admin_user, plan: GitHub::Plan.business)
    @paid_org_with_codespaces_enabled = create(:credit_card_org, plan: GitHub::Plan.business, admin: @admin_user)

    @user_with_org_access = create(:user)
    @org_with_codespaces_enabled.add_member(@user_with_org_access)
    @paid_org_with_codespaces_enabled.add_member(@user_with_org_access)

    @user_with_org_but_not_org_creator_access = create(:user)
    @org_with_codespaces_enabled.add_member(@user_with_org_but_not_org_creator_access)
    Codespaces::OrgPolicy.grant_billing_permission!(@user_with_org_access, @org_with_codespaces_enabled)

    @collaborator = create(:user)
    @collaborator_repo = create(:private_repository, owner: @org_with_codespaces_enabled)
    @collaborator_repo.add_member_without_validation_or_notifications(@collaborator)
    GitHub.flipper[:codespaces_allow_trials].disable
    GitHub.flipper[:codespaces_billing_free].disable
  end

  test "does not allow settings on GHES", enterprise_only: true do
    refute Codespaces::OrgPolicy.new(org: create(:business_organization), user: nil).allow_org_setting?
  end

  context "when the org has codespaces enabled" do
    test "a user with codespace creation granted can bill" do
      policy = Codespaces::OrgPolicy.new(user: @user_with_org_access, org: @org_with_codespaces_enabled)
      assert policy.async_can_bill?.sync
    end

    test "a user without codespace creation granted cannot bill" do
      policy = Codespaces::OrgPolicy.new(user: @user_with_org_but_not_org_creator_access, org: @org_with_codespaces_enabled)
      refute policy.async_can_bill?.sync
    end

    test "a user who isn't a member of the org cannot bill" do
      rando = create(:user)
      policy = Codespaces::OrgPolicy.new(user: rando, org: @org_with_codespaces_enabled)
      refute policy.async_can_bill?.sync
    end

    test "a member can bill when user limit permissions is ALL_USERS" do
      @org_with_codespaces_enabled.update_organization_codespaces_user_limit(
        Configurable::OrganizationCodespacesUserLimit::ALL_USERS, actor: @admin_user)

      org_member = create(:user)
      @org_with_codespaces_enabled.add_member(org_member)

      policy = Codespaces::OrgPolicy.new(user: org_member, org: @org_with_codespaces_enabled)
      assert policy.async_can_bill?.sync
    end

    test "a member can bill when user limit permissions is ALL_USERS_AND_OUTSIDE_COLLABORATORS" do
      @org_with_codespaces_enabled.update_organization_codespaces_user_limit(
        Configurable::OrganizationCodespacesUserLimit::ALL_USERS_AND_OUTSIDE_COLLABORATORS, actor: @admin_user)

      org_member = create(:user)
      @org_with_codespaces_enabled.add_member(org_member)

      policy = Codespaces::OrgPolicy.new(user: org_member, org: @org_with_codespaces_enabled)
      assert policy.async_can_bill?.sync
    end

    context "a collaborator on an org repo can bill" do
      test "org settings allow collaborators" do
        @org_with_codespaces_enabled.update_organization_codespaces_user_limit(
          Configurable::OrganizationCodespacesUserLimit::ALL_USERS_AND_OUTSIDE_COLLABORATORS, actor: @admin_user)
        policy = Codespaces::OrgPolicy.new(user: @collaborator, org: @org_with_codespaces_enabled, repo: @collaborator_repo)

        assert policy.async_can_bill?.sync
      end

      test "org settings does not allow collaborators" do
        @org_with_codespaces_enabled.update_organization_codespaces_user_limit(
          Configurable::OrganizationCodespacesUserLimit::ALL_USERS, actor: @admin_user)
        policy = Codespaces::OrgPolicy.new(user: @collaborator, org: @org_with_codespaces_enabled, repo: @collaborator_repo)

        refute policy.async_can_bill?.sync
      end
    end

    context "known collaborator is honored without being checked" do
      test "org settings allow collaborators" do
        @org_with_codespaces_enabled.update_organization_codespaces_user_limit(
          Configurable::OrganizationCodespacesUserLimit::ALL_USERS_AND_OUTSIDE_COLLABORATORS, actor: @admin_user)
        rando = create(:user)
        policy = Codespaces::OrgPolicy.new(user: rando, org: @org_with_codespaces_enabled, known_org_relationship: :collaborator)

        assert policy.async_can_bill?.sync
      end

      test "org settings does not allow collaborators" do
        @org_with_codespaces_enabled.update_organization_codespaces_user_limit(
          Configurable::OrganizationCodespacesUserLimit::ALL_USERS, actor: @admin_user)
        rando = create(:user)
        policy = Codespaces::OrgPolicy.new(user: rando, org: @org_with_codespaces_enabled, known_org_relationship: :collaborator)

        refute policy.async_can_bill?.sync
      end
    end

    test "known membership is honored without being checked" do
      @org_with_codespaces_enabled.update_organization_codespaces_user_limit(
        Configurable::OrganizationCodespacesUserLimit::ALL_USERS, actor: @admin_user)
      rando = create(:user)
      policy = Codespaces::OrgPolicy.new(user: rando, org: @org_with_codespaces_enabled, known_org_relationship: :member)
      assert policy.async_can_bill?.sync
    end

    test "invalid known_org_relationship argument raises" do
      assert_raises ArgumentError do
        policy = Codespaces::OrgPolicy.new(user: @collaborator, org: @org_with_codespaces_enabled, known_org_relationship: :wut)
      end
    end

    test "known relationship can't be provided with a repo" do
      assert_raises ArgumentError do
        policy = Codespaces::OrgPolicy.new(user: @collaborator, org: @org_with_codespaces_enabled,
          repo: @collaborator_repo, known_org_relationship: :member)
      end
      assert_raises ArgumentError do
        policy = Codespaces::OrgPolicy.new(user: @collaborator, org: @org_with_codespaces_enabled,
          repo: @collaborator_repo, known_org_relationship: :collaborator)
      end
    end
  end

  context "when the org doesn't have codespaces enabled" do
    test "a member cannot bill" do
      admin = create(:user)
      org = create(:codespaces_organization, plan: GitHub::Plan.free, admin: admin)
      org.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::DISABLED, actor: admin)

      policy = Codespaces::OrgPolicy.new(user: admin, org: org)
      refute policy.async_can_bill?.sync
    end
  end
  context "when the org has user ownership enabled" do
    test "a user with org access cannot bill" do
      @org_with_codespaces_enabled.update_organization_codespaces_ownership_setting(Configurable::OrganizationCodespacesOwnershipSetting::USER, actor: @admin_user)
      policy = Codespaces::OrgPolicy.new(user: @user_with_org_access, org: @org_with_codespaces_enabled)
      refute policy.async_can_bill?.sync
    end

    test "a free org can enable/disable codespaces for users" do
      free_org = create(:free_organization, name: "free-org")
      user = create(:user)
      free_org.add_member(user)

      Codespaces::OrgPolicy.grant_billing_permission!(user, free_org)
      Codespaces::OrgPolicy.revoke_billing_permission!(user, free_org)
    end
  end
  context ".allow_org_setting?" do
    test "allows a free organization that's enabled by the feature flag" do
      free_org = create(:free_organization)
      GitHub.flipper[:codespaces_billing_free].enable(free_org)

      assert Codespaces::OrgPolicy.new(org: free_org, user: nil).allow_org_setting?
    end

    test "allows a Team/GHEC org that's enabled by the feature flag" do
      team_org = create(:business_organization)
      ghec_org = create(:business_plus_organization)

      assert Codespaces::OrgPolicy.new(org: team_org, user: nil).allow_org_setting?
      assert Codespaces::OrgPolicy.new(org: ghec_org, user: nil).allow_org_setting?
    end

    test "allows a Team or GHEC organization that's not enabled for the feature flag" do
      team_org = create(:business_organization)
      ghec_org = create(:business_plus_organization)

      assert Codespaces::OrgPolicy.new(org: team_org, user: nil).allow_org_setting?
      assert Codespaces::OrgPolicy.new(org: ghec_org, user: nil).allow_org_setting?
    end

    test "does not allow an org plan that disallows codespaces that's not enabled for codespaces" do
      free_org = create(:free_organization)

      refute Codespaces::OrgPolicy.new(org: free_org, user: nil).allow_org_setting?
    end
  end

  context ".allow_org_admin_update_ownership_setting?" do
    test "does not allow for EMU org", skip_unless: :proxima_emu_test_mode? do
      refute Codespaces::OrgPolicy.new(org: @org_with_codespaces_enabled, user: nil).allow_org_admin_update_ownership_setting?
    end
  end

  context "::billing_policy_members" do
    # disabled, selected_members, all_members, all_members_and_outside_collaborators
    test "when visibility is 'selected_members'" do
      visibility, members = Codespaces::OrgPolicy.billing_policy_members(@org_with_codespaces_enabled)
      assert_equal "selected_members", visibility
      assert_equal [@user_with_org_access.name], members
    end

    test "when visibility is 'disabled'" do
      Codespaces::OrgPolicy.revoke_billing_permission!(@user_with_org_access, @org_with_codespaces_enabled)
      Codespaces::OrgSettingsChangedJob.perform_now(
        context: @org_with_codespaces_enabled.id,
        event_type: Codespaces::Events::ORG_CODESPACES_DISABLED_USER,
        actor_id: @admin_user.id
      )
      @org_with_codespaces_enabled.update_organization_codespaces_user_limit("disabled", actor: @admin_user)

      visibility, members = Codespaces::OrgPolicy.billing_policy_members(@org_with_codespaces_enabled)
      assert_equal "disabled", visibility
      assert_equal [], members
    end

    test "when visibility is 'all_members'" do
      Codespaces::OrgSettingsChangedJob.perform_now(
        context: @org_with_codespaces_enabled.id,
        event_type: Codespaces::Events::ORG_CODESPACES_ENABLED,
        actor_id: @admin_user.id
      )
      @org_with_codespaces_enabled.update_organization_codespaces_user_limit("all_users", actor: @admin_user)

      visibility, members = Codespaces::OrgPolicy.billing_policy_members(@org_with_codespaces_enabled)
      assert_equal "all_members", visibility
      assert_equal [], members
    end

    test "when visibility is 'all_members_and_outside_collaborators'" do
      Codespaces::OrgSettingsChangedJob.perform_now(
        context: @org_with_codespaces_enabled.id,
        event_type: Codespaces::Events::ORG_CODESPACES_ENABLED,
        actor_id: @admin_user.id
      )
      @org_with_codespaces_enabled.update_organization_codespaces_user_limit("all_users_and_outside_collaborators", actor: @admin_user)

      visibility, members = Codespaces::OrgPolicy.billing_policy_members(@org_with_codespaces_enabled)
      assert_equal "all_members_and_outside_collaborators", visibility
      assert_equal [], members
    end
  end

  context "#async_can_use_codespaces?" do
    test "when the setting is disabled", skip_with_all_emus: true do
      @paid_org_with_codespaces_enabled.update_organization_codespaces_ownership_setting(
        Configurable::OrganizationCodespacesOwnershipSetting::ORGANIZATION, actor: @admin_user
      )
      @paid_org_with_codespaces_enabled.update_organization_codespaces_user_limit(
          Configurable::OrganizationCodespacesUserLimit::DISABLED, actor: @admin_user)

      # Says yes if provided a public repository
      public_repo = create(:repository, owner: @paid_org_with_codespaces_enabled)
      policy = Codespaces::OrgPolicy.new(user: @user_with_org_access, org: @paid_org_with_codespaces_enabled, repo: public_repo)
      assert policy.async_can_use_codespaces?.sync

      # Says no if not provided any repository context
      policy = Codespaces::OrgPolicy.new(user: @user_with_org_access, org: @paid_org_with_codespaces_enabled)
      refute policy.async_can_use_codespaces?.sync

      # Says no if provided a private repository
      policy = Codespaces::OrgPolicy.new(user: @user_with_org_access, org: @paid_org_with_codespaces_enabled, repo: @collaborator_repo)
      refute policy.async_can_use_codespaces?.sync
    end

    test "when the setting is set to all members" do
      @paid_org_with_codespaces_enabled.update_organization_codespaces_ownership_setting(
        Configurable::OrganizationCodespacesOwnershipSetting::ORGANIZATION, actor: @admin_user
      )
      @paid_org_with_codespaces_enabled.update_organization_codespaces_user_limit(
          Configurable::OrganizationCodespacesUserLimit::ALL_USERS, actor: @admin_user)

      # Says yes if the user is a member of the org
      policy = Codespaces::OrgPolicy.new(user: @user_with_org_access, org: @paid_org_with_codespaces_enabled)
      assert policy.async_can_use_codespaces?.sync

      # Says no if the user is a collaborator in the org
      policy = Codespaces::OrgPolicy.new(user: @collaborator, org: @paid_org_with_codespaces_enabled, repo: @collaborator_repo)
      refute policy.async_can_use_codespaces?.sync
    end

    test "when the setting is set to all members and outside collaborators" do
      @paid_org_with_codespaces_enabled.update_organization_codespaces_ownership_setting(
        Configurable::OrganizationCodespacesOwnershipSetting::ORGANIZATION, actor: @admin_user
      )
      @paid_org_with_codespaces_enabled.update_organization_codespaces_user_limit(
          Configurable::OrganizationCodespacesUserLimit::ALL_USERS_AND_OUTSIDE_COLLABORATORS, actor: @admin_user)

      # Says yes if the user is a member of the org
      policy = Codespaces::OrgPolicy.new(user: @user_with_org_access, org: @paid_org_with_codespaces_enabled)
      assert policy.async_can_use_codespaces?.sync

      # Says no if the user is a collaborator in the org
      policy = Codespaces::OrgPolicy.new(user: @collaborator, org: @paid_org_with_codespaces_enabled, repo: @collaborator_repo)
      assert policy.async_can_use_codespaces?.sync
    end

    test "when the setting is set to selected members" do

      @paid_org_with_codespaces_enabled.update_organization_codespaces_ownership_setting(
        Configurable::OrganizationCodespacesOwnershipSetting::ORGANIZATION, actor: @admin_user
      )
      @paid_org_with_codespaces_enabled.update_organization_codespaces_user_limit(
          Configurable::OrganizationCodespacesUserLimit::SELECTED_USERS, actor: @admin_user)

      # Says no if the user is not in the allow list
      Codespaces::OrgPolicy.prevent_org_access!(@user_with_org_access, @paid_org_with_codespaces_enabled)
      policy = Codespaces::OrgPolicy.new(user: @user_with_org_access, org: @paid_org_with_codespaces_enabled)
      refute policy.async_can_use_codespaces?.sync

      # Says yes if the user is added to the allow list
      Codespaces::OrgPolicy.allow_org_access!(@user_with_org_access, @paid_org_with_codespaces_enabled)
      policy = Codespaces::OrgPolicy.new(user: @user_with_org_access, org: @paid_org_with_codespaces_enabled)
      assert policy.async_can_use_codespaces?.sync
    end

    test "when the setting is set to selected members + teams - team member can use codespaces" do
      @paid_org_with_codespaces_enabled.update_organization_codespaces_ownership_setting(
        Configurable::OrganizationCodespacesOwnershipSetting::ORGANIZATION, actor: @admin_user
      )
      @paid_org_with_codespaces_enabled.update_organization_codespaces_user_limit(
          Configurable::OrganizationCodespacesUserLimit::SELECTED_USERS, actor: @admin_user)

      team = create(:team, organization: @paid_org_with_codespaces_enabled)
      team.add_member(@user_with_org_access)
      # Says no if the team is not in the allow list
      Codespaces::OrgPolicy.prevent_org_access!(@user_with_org_access, @paid_org_with_codespaces_enabled)
      Codespaces::OrgPolicy.prevent_org_access!(team, @paid_org_with_codespaces_enabled)
      policy = Codespaces::OrgPolicy.new(user: @user_with_org_access, org: @paid_org_with_codespaces_enabled)
      refute policy.async_can_use_codespaces?.sync

      # Says yes if the team is added to the allow list
      Codespaces::OrgPolicy.allow_org_access!(team, @paid_org_with_codespaces_enabled)

      policy = Codespaces::OrgPolicy.new(user: @user_with_org_access, org: @paid_org_with_codespaces_enabled)
      assert policy.async_can_use_codespaces?.sync
    end

    test "when the ownership setting is set to USER we preserve access" do
      @org_with_codespaces_enabled.update_organization_codespaces_ownership_setting(
        Configurable::OrganizationCodespacesOwnershipSetting::USER, actor: @admin_user
      )
      @org_with_codespaces_enabled.update_organization_codespaces_user_limit(
          Configurable::OrganizationCodespacesUserLimit::ALL_USERS, actor: @admin_user)

      # Says no even if the user is a member of the org
      policy = Codespaces::OrgPolicy.new(user: @user_with_org_access, org: @org_with_codespaces_enabled)
      assert policy.async_can_use_codespaces?.sync
    end
  end

  context "#enabled_by_organization?" do
    test "returns false if access setting is disabled" do
      free_org = create(:free_organization)
      free_org.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::DISABLED, actor: @admin_user)
      free_org.update_organization_codespaces_ownership_setting(Configurable::OrganizationCodespacesOwnershipSetting::USER, actor: @admin_user)
      refute Codespaces::OrgPolicy.enabled_by_organization?(free_org)
    end
  end

  context "#org_admin_can_configure_private_networking?" do
    test "returns true if org is under flagged enterprise" do
      enterprise = create(:business)
      GitHub.flipper[:codespaces_vnet_injection_beta].enable(enterprise)
      GitHub.flipper[:codespaces_salus_beta_customers].enable(enterprise)
      org = create(:team_org)
      enterprise.add_organization(org)

      policy = Codespaces::OrgPolicy.new(user: nil, org: org.reload)
      assert policy.org_admin_can_configure_private_networking?
    end

    test "returns false if org isn't part of an enterprise" do
      org = create(:team_org)

      policy = Codespaces::OrgPolicy.new(user: nil, org: org.reload)
      refute policy.org_admin_can_configure_private_networking?
    end

    test "returns false if org is under vnet-injection-beta-unflagged enterprise" do
      enterprise = create(:business)
      GitHub.flipper[:codespaces_vnet_injection_beta].disable(enterprise)
      GitHub.flipper[:codespaces_salus_beta_customers].enable(enterprise)

      org = create(:team_org)
      enterprise.add_organization(org)

      policy = Codespaces::OrgPolicy.new(user: nil, org: org.reload)
      refute policy.org_admin_can_configure_private_networking?
    end

    test "returns false if org is under salus-beta-unflagged enterprise" do
      enterprise = create(:business)
      GitHub.flipper[:codespaces_vnet_injection_beta].enable(enterprise)
      GitHub.flipper[:codespaces_salus_beta_customers].disable(enterprise)

      org = create(:team_org)
      enterprise.add_organization(org)

      policy = Codespaces::OrgPolicy.new(user: nil, org: org.reload)
      refute policy.org_admin_can_configure_private_networking?
    end
  end
end unless GitHub.enterprise?
