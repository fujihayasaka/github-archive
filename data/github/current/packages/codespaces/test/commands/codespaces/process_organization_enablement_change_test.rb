# typed: true
# frozen_string_literal: true

require "test_helper"

module Codespaces
  class ProcessOrganizationEnablementChangeTest < GitHub::TestCase
    fixtures do
      @org = create(:codespaces_organization, name: "test-billable-org", plan: GitHub::Plan.business)
      @user = @org.admin
      @org_repo = create(:private_repository, owner: @org)
      @org_public_repo = create(:public_repository, owner: @org)
      @collaborator = create(:user, login: "collaborator")
      @org_member = create(:user, login: "org-member")
      @org.add_member(@org_member, action: :admin)

      Codespaces::OrgPolicy.grant_billing_permission!(@user, @org)

      @user_owned_codespace = create(:codespace, billable_owner: @org, repository: @org_repo, owner: @user)
      @collaborator_owned_codespace = create(:codespace, repository: @org_repo, owner: @collaborator, enable_org_access: false, make_collaborator: true)

      @jobs = [
        Codespaces::OrgSettingsChangedJob,
        CodespacesProcessSystemEventJob
      ]
    end

    context "updating setting to disabled", skip_enterprise: true do
      test "from selected members - does not transfer to user ownership" do
        ::Codespaces::ScheduleEnvironmentSuspension.expects(:call).at_least(1).returns(true)
        @org.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::SELECTED_USERS, actor: @user)
        Codespaces::OrgPolicy.grant_billing_permission!(@org_member, @org)
        member_codespace = create(:codespace, repository: @org_repo, owner: @org_member, enable_org_access: true)
        assert_equal @org, member_codespace.reload.billable_owner
        perform_enqueued_jobs(only: @jobs) do
          ::Codespaces::ProcessOrganizationEnablementChange.new(
            organization: @org,
            actor: @user,
            enablement: Configurable::OrganizationCodespacesUserLimit::DISABLED,
            users_to_update: [],
          ).call
        end
        assert_equal Configurable::OrganizationCodespacesUserLimit::DISABLED, @org.reload.organization_codespaces_user_limit
        assert_equal @org, member_codespace.reload.billable_owner
      end

      test "from all members - does not transfer out of org" do
        ::Codespaces::ScheduleEnvironmentSuspension.expects(:call).at_least(1).returns(true)
        @org.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::ALL_USERS, actor: @user)
        member_codespace = create(:codespace, repository: @org_repo, owner: @org_member, enable_org_access: false)
        assert_equal @org, member_codespace.reload.billable_owner
        perform_enqueued_jobs(only: @jobs) do
          ::Codespaces::ProcessOrganizationEnablementChange.new(
            organization: @org,
            actor: @user,
            enablement: Configurable::OrganizationCodespacesUserLimit::DISABLED,
            users_to_update: [],
          ).call
        end
        assert_equal Configurable::OrganizationCodespacesUserLimit::DISABLED, @org.reload.organization_codespaces_user_limit
        assert_equal @org, member_codespace.reload.billable_owner
      end

      test "from all members and outside collaborators - does not transfer out of org" do
        ::Codespaces::ScheduleEnvironmentSuspension.expects(:call).at_least(2).returns(true)
        @org.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::ALL_USERS_AND_OUTSIDE_COLLABORATORS, actor: @user)
        collaborator_org_owned_codespace = create(:codespace, repository: @org_repo, owner: @collaborator, enable_org_access: false, make_collaborator: true)
        assert_equal @org, collaborator_org_owned_codespace.reload.billable_owner
        member_codespace = create(:codespace, repository: @org_repo, owner: @org_member, enable_org_access: false)
        assert_equal @org, member_codespace.reload.billable_owner
        perform_enqueued_jobs(only: @jobs) do
          ::Codespaces::ProcessOrganizationEnablementChange.new(
            organization: @org,
            actor: @user,
            enablement: Configurable::OrganizationCodespacesUserLimit::DISABLED,
            users_to_update: [],
          ).call
        end
        assert_equal Configurable::OrganizationCodespacesUserLimit::DISABLED, @org.reload.organization_codespaces_user_limit
        assert_equal @org, collaborator_org_owned_codespace.reload.billable_owner
        assert_equal @org, member_codespace.reload.billable_owner
      end
    end

    context "updating setting to selected members", skip_enterprise: true do
      test "from disabled - will transfer codespace ownership to org" do
        @org.update_organization_codespaces_ownership_setting(Configurable::OrganizationCodespacesOwnershipSetting::USER, actor: @user)
        ::Codespaces::ScheduleEnvironmentSuspension.expects(:call).at_least(1).returns(true)
        member_codespace = create(:codespace, repository: @org_repo, owner: @org_member, enable_org_access: false)
        assert_equal @org_member, member_codespace.reload.billable_owner
        @org.update_organization_codespaces_ownership_setting(Configurable::OrganizationCodespacesOwnershipSetting::ORGANIZATION, actor: @user)
        @org.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::DISABLED, actor: @user)
        perform_enqueued_jobs(only: @jobs) do
          ::Codespaces::ProcessOrganizationEnablementChange.new(
            organization: @org,
            actor: @user,
            enablement: Configurable::OrganizationCodespacesUserLimit::SELECTED_USERS,
            users_to_update: [@org_member.login],
          ).call
        end

        assert_equal Configurable::OrganizationCodespacesUserLimit::SELECTED_USERS, @org.reload.organization_codespaces_user_limit
        assert_equal @org, member_codespace.reload.billable_owner
      end

      test "selected members remove - does not transfer out of org" do
        ::Codespaces::ScheduleEnvironmentSuspension.expects(:call).at_least(1).returns(true)
        @org.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::SELECTED_USERS, actor: @user)
        Codespaces::OrgPolicy.grant_billing_permission!(@org_member, @org)
        member_codespace = create(:codespace, repository: @org_repo, owner: @org_member, enable_org_access: true)
        assert_equal @org, member_codespace.reload.billable_owner
        perform_enqueued_jobs(only: @jobs) do
          ::Codespaces::ProcessOrganizationEnablementChange.new(
            organization: @org,
            actor: @user,
            enablement: Configurable::OrganizationCodespacesUserLimit::SELECTED_USERS,
            users_to_update: [],
          ).call
        end
        assert_equal @org, member_codespace.reload.billable_owner
      end

      test "from all members - non selected members codespaces will not transfer from org to self" do
        # This should suspend the non-selected org_member's codespace
        ::Codespaces::ScheduleEnvironmentSuspension.expects(:call).at_least(1).returns(true)
        @org.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::ALL_USERS, actor: @user)
        member_codespace = create(:codespace, repository: @org_repo, owner: @org_member, enable_org_access: false)
        assert_equal @org, member_codespace.reload.billable_owner
        perform_enqueued_jobs(only: @jobs) do
          ::Codespaces::ProcessOrganizationEnablementChange.new(
            organization: @org,
            actor: @user,
            enablement: Configurable::OrganizationCodespacesUserLimit::SELECTED_USERS,
            users_to_update: [@user.login],
          ).call
        end
        assert_equal Configurable::OrganizationCodespacesUserLimit::SELECTED_USERS, @org.reload.organization_codespaces_user_limit
        assert_equal @org, member_codespace.reload.billable_owner
      end

      test "from all members and outside collaborators - will not transfer to outside collaborators and users not selected" do
        # This should suspend the non-selected org_member's codespace
        ::Codespaces::ScheduleEnvironmentSuspension.expects(:call).at_least(1).returns(true)
        @org.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::ALL_USERS_AND_OUTSIDE_COLLABORATORS, actor: @user)
        collaborator_org_owned_codespace = create(:codespace, repository: @org_repo, owner: @collaborator, enable_org_access: false, make_collaborator: true)
        assert_equal @org, collaborator_org_owned_codespace.reload.billable_owner
        member_codespace = create(:codespace, repository: @org_repo, owner: @org_member, enable_org_access: false)
        assert_equal @org, member_codespace.reload.billable_owner
        perform_enqueued_jobs(only: @jobs) do
          ::Codespaces::ProcessOrganizationEnablementChange.new(
            organization: @org,
            actor: @user,
            enablement: Configurable::OrganizationCodespacesUserLimit::SELECTED_USERS,
            users_to_update: [@user.login],
          ).call
        end
        assert_equal Configurable::OrganizationCodespacesUserLimit::SELECTED_USERS, @org.reload.organization_codespaces_user_limit
        assert_equal @org, collaborator_org_owned_codespace.reload.billable_owner
        assert_equal @org, member_codespace.reload.billable_owner
      end
    end

    context "updating setting to selected teams", skip_enterprise: true do
      test "from disabled - will transfer codespace ownership to org" do
        @org.update_organization_codespaces_ownership_setting(Configurable::OrganizationCodespacesOwnershipSetting::USER, actor: @user)
        ::Codespaces::ScheduleEnvironmentSuspension.expects(:call).at_least(1).returns(true)
        member_codespace = create(:codespace, repository: @org_repo, owner: @org_member, enable_org_access: false)
        assert_equal @org_member, member_codespace.reload.billable_owner
        @org.update_organization_codespaces_ownership_setting(Configurable::OrganizationCodespacesOwnershipSetting::ORGANIZATION, actor: @user)
        @org.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::DISABLED, actor: @user)
        team = create(:team, organization: @org)
        team.add_member(@org_member)
        perform_enqueued_jobs(only: @jobs) do
          ::Codespaces::ProcessOrganizationEnablementChange.new(
            organization: @org,
            actor: @user,
            enablement: Configurable::OrganizationCodespacesUserLimit::SELECTED_USERS,
            teams_to_update: [team.slug],
          ).call
        end

        assert_equal Configurable::OrganizationCodespacesUserLimit::SELECTED_USERS, @org.reload.organization_codespaces_user_limit
        assert_equal @org, member_codespace.reload.billable_owner
      end

      test "selected team remove - does not transfer out of org" do
        ::Codespaces::ScheduleEnvironmentSuspension.expects(:call).at_least(1).returns(true)
        @org.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::SELECTED_USERS, actor: @user)
        team = create(:team, organization: @org)
        team.add_member(@org_member)
        Codespaces::OrgPolicy.grant_billing_permission!(team, @org)
        member_codespace = create(:codespace, repository: @org_repo, owner: @org_member, enable_org_access: true)
        assert_equal @org, member_codespace.reload.billable_owner
        perform_enqueued_jobs(only: @jobs) do
          ::Codespaces::ProcessOrganizationEnablementChange.new(
            organization: @org,
            actor: @user,
            enablement: Configurable::OrganizationCodespacesUserLimit::SELECTED_USERS,
            teams_to_update: [],
          ).call
        end
        assert_equal @org, member_codespace.reload.billable_owner
      end

      test "from all members - to specific team" do
        # This should suspend the non-selected org_member's codespace
        ::Codespaces::ScheduleEnvironmentSuspension.expects(:call).at_least(1).returns(true)
        @org.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::ALL_USERS, actor: @user)
        member_codespace = create(:codespace, repository: @org_repo, owner: @org_member, enable_org_access: false)
        assert_equal @org, member_codespace.reload.billable_owner
        team = create(:team, organization: @org)

        perform_enqueued_jobs(only: @jobs) do
          ::Codespaces::ProcessOrganizationEnablementChange.new(
            organization: @org,
            actor: @user,
            enablement: Configurable::OrganizationCodespacesUserLimit::SELECTED_USERS,
            teams_to_update: [team.slug],
          ).call
        end
        assert_equal Configurable::OrganizationCodespacesUserLimit::SELECTED_USERS, @org.reload.organization_codespaces_user_limit
        assert_equal @org, member_codespace.reload.billable_owner
      end
    end

    context "updating setting to all members", skip_enterprise: true do
      test "from disabled - will transfer to org ownership if member of org" do
        @org.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::DISABLED, actor: @user)
        member_codespace = create(:codespace, repository: @org_public_repo, owner: @org_member, enable_org_access: false)
        collaborator_org_owned_codespace = create(:codespace, repository: @org_public_repo, owner: @collaborator, enable_org_access: false, make_collaborator: true)
        assert_equal @org_member, member_codespace.reload.billable_owner
        perform_enqueued_jobs(only: @jobs) do
          ::Codespaces::ProcessOrganizationEnablementChange.new(
            organization: @org,
            actor: @user,
            enablement: Configurable::OrganizationCodespacesUserLimit::ALL_USERS,
            users_to_update: [],
          ).call
        end
        assert_equal Configurable::OrganizationCodespacesUserLimit::ALL_USERS, @org.reload.organization_codespaces_user_limit
        assert_equal @org, member_codespace.reload.billable_owner
        assert_equal @collaborator, collaborator_org_owned_codespace.reload.billable_owner #does not transfer to org
      end

      test "from selected members - pubclic repo - ownership will transfer to user for non org members" do
        ::Codespaces::ScheduleEnvironmentSuspension.expects(:call).at_least(1).returns(true)
        perform_enqueued_jobs(only: @jobs) do
          ::Codespaces::ProcessOrganizationEnablementChange.new(
            organization: @org,
            actor: @user,
            enablement: Configurable::OrganizationCodespacesUserLimit::SELECTED_USERS,
            users_to_update: [@org_member.display_login, @collaborator.display_login],
          ).call
        end
        not_selected_member_codespace = create(:codespace, repository: @org_public_repo, owner: @org_member, enable_org_access: false)
        collaborator_org_owned_codespace = create(:codespace, repository: @org_public_repo, owner: @collaborator, enable_org_access: false, make_collaborator: true)

        assert_equal @org, not_selected_member_codespace.reload.billable_owner
        assert_equal @org, collaborator_org_owned_codespace.reload.billable_owner
        perform_enqueued_jobs(only: @jobs) do
          ::Codespaces::ProcessOrganizationEnablementChange.new(
            organization: @org,
            actor: @user,
            enablement: Configurable::OrganizationCodespacesUserLimit::ALL_USERS,
            users_to_update: [],
          ).call
        end
        assert_equal Configurable::OrganizationCodespacesUserLimit::ALL_USERS, @org.reload.organization_codespaces_user_limit
        assert_equal @org, not_selected_member_codespace.reload.billable_owner
        assert_equal @collaborator, collaborator_org_owned_codespace.reload.billable_owner
      end

      test "from all members and outside collaborators - will not transfer to outside collaborators" do
        @org.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::ALL_USERS_AND_OUTSIDE_COLLABORATORS, actor: @user)
        collaborator_org_owned_codespace = create(:codespace, repository: @org_repo, owner: @collaborator, enable_org_access: false, make_collaborator: true)

        assert_equal @org, collaborator_org_owned_codespace.reload.billable_owner
        perform_enqueued_jobs(only: @jobs) do
          ::Codespaces::ProcessOrganizationEnablementChange.new(
            organization: @org,
            actor: @user,
            enablement: Configurable::OrganizationCodespacesUserLimit::ALL_USERS,
            users_to_update: [],
          ).call
        end
        assert_equal Configurable::OrganizationCodespacesUserLimit::ALL_USERS, @org.reload.organization_codespaces_user_limit
        refute collaborator_org_owned_codespace.reload.accessible?
        assert_equal @org, collaborator_org_owned_codespace.reload.billable_owner
      end
    end

    context "updating setting to all members and outside collaborators", skip_enterprise: true do
      test "from disabled - setting is update and ownership of all is updated to org" do
        @org.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::DISABLED, actor: @user)
        not_selected_member_codespace = create(:codespace, repository: @org_public_repo, owner: @org_member, enable_org_access: false)
        collaborator_owned_codespace = create(:codespace, repository: @org_public_repo, owner: @collaborator, enable_org_access: false)
        assert_equal @org_member, not_selected_member_codespace.reload.billable_owner
        assert_equal @collaborator, collaborator_owned_codespace.reload.billable_owner
        perform_enqueued_jobs(only: @jobs) do
          ::Codespaces::ProcessOrganizationEnablementChange.new(
            organization: @org,
            actor: @user,
            enablement: Configurable::OrganizationCodespacesUserLimit::ALL_USERS_AND_OUTSIDE_COLLABORATORS,
            users_to_update: [],
          ).call
        end
        assert_equal Configurable::OrganizationCodespacesUserLimit::ALL_USERS_AND_OUTSIDE_COLLABORATORS, @org.reload.organization_codespaces_user_limit
        assert_equal @org, collaborator_owned_codespace.reload.billable_owner
        assert_equal @org, not_selected_member_codespace.reload.billable_owner
      end

      test "from selected members - setting is updated and ownership of all is updated to org" do
        @org.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::SELECTED_USERS, actor: @user)
        not_selected_member_codespace = create(:codespace, repository: @org_public_repo, owner: @org_member, enable_org_access: false)
        collaborator_owned_codespace = create(:codespace, repository: @org_public_repo, owner: @collaborator, enable_org_access: false)
        assert_equal @org_member, not_selected_member_codespace.reload.billable_owner
        assert_equal @collaborator, collaborator_owned_codespace.reload.billable_owner
        perform_enqueued_jobs(only: @jobs) do
          ::Codespaces::ProcessOrganizationEnablementChange.new(
            organization: @org,
            actor: @user,
            enablement: Configurable::OrganizationCodespacesUserLimit::ALL_USERS_AND_OUTSIDE_COLLABORATORS,
            users_to_update: [],
          ).call
        end
        assert_equal Configurable::OrganizationCodespacesUserLimit::ALL_USERS_AND_OUTSIDE_COLLABORATORS, @org.reload.organization_codespaces_user_limit
        assert_equal @org, collaborator_owned_codespace.reload.billable_owner
        assert_equal @org, not_selected_member_codespace.reload.billable_owner
      end

      test "from all members - setting is updated and ownership of outside collaborator codespaces are transferred to org" do
        @org.update_organization_codespaces_ownership_setting(Configurable::OrganizationCodespacesOwnershipSetting::USER, actor: @user)
        @org.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::ALL_USERS, actor: @user)
        collaborator_owned_codespace = create(:codespace, repository: @org_public_repo, owner: @collaborator, enable_org_access: false)
        assert_equal @collaborator, collaborator_owned_codespace.reload.billable_owner
        @org.update_organization_codespaces_ownership_setting(Configurable::OrganizationCodespacesOwnershipSetting::ORGANIZATION, actor: @user)
        perform_enqueued_jobs(only: @jobs) do
          ::Codespaces::ProcessOrganizationEnablementChange.new(
            organization: @org,
            actor: @user,
            enablement: Configurable::OrganizationCodespacesUserLimit::ALL_USERS_AND_OUTSIDE_COLLABORATORS,
            users_to_update: [],
          ).call
        end
        assert_equal Configurable::OrganizationCodespacesUserLimit::ALL_USERS_AND_OUTSIDE_COLLABORATORS, @org.reload.organization_codespaces_user_limit
        assert_equal @org, collaborator_owned_codespace.reload.billable_owner
      end
    end
  end
end
