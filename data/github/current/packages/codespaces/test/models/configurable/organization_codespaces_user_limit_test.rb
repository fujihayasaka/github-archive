# typed: true
# frozen_string_literal: true

require "test_helper"

class Configurable::OrganizationCodespacesUserLimitTest < GitHub::TestCase
  fixtures do
    @organization = create(:organization)
    @setting_user = create(:user)
    @organization.config.set(Configurable::OrganizationCodespacesOwnershipSetting::KEY, Configurable::OrganizationCodespacesOwnershipSetting::USER, @setting_user)
  end

  context "managing the user limit" do
    test "raises error when limit is invalid" do
      assert_raises ArgumentError, /invalid organization codespaces user limit/ do
        @organization.update_organization_codespaces_user_limit("invalid limit", actor: @setting_user)
      end
    end

    test "defaults to disabled" do
      @organization.config.delete(Configurable::OrganizationCodespacesUserLimit::KEY)
      assert_equal Configurable::OrganizationCodespacesUserLimit::DISABLED, @organization.organization_codespaces_user_limit
    end

    test "always reflects the stored value otherwise" do

      @organization.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::ALL_USERS, actor: @setting_user)
      assert_equal Configurable::OrganizationCodespacesUserLimit::ALL_USERS, @organization.organization_codespaces_user_limit

      @organization.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::ALL_USERS_AND_OUTSIDE_COLLABORATORS, actor: @setting_user)
      assert_equal Configurable::OrganizationCodespacesUserLimit::ALL_USERS_AND_OUTSIDE_COLLABORATORS, @organization.organization_codespaces_user_limit

      @organization.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::SELECTED_USERS, actor: @setting_user)
      assert_equal Configurable::OrganizationCodespacesUserLimit::SELECTED_USERS, @organization.organization_codespaces_user_limit

      @organization.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::DISABLED, actor: @setting_user)
      assert_equal Configurable::OrganizationCodespacesUserLimit::DISABLED, @organization.organization_codespaces_user_limit
    end
  end

  context "#limits_organizations_codespaces_to_selected_users?" do
    test "returns true if SELECTED_USERS is the user limit for the organizations" do
      @organization.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::SELECTED_USERS, actor: @setting_user)

      assert @organization.limits_organizations_codespaces_to_selected_users?
    end

    test "returns false if SELECTED_USERS is not the user limit for the organizations" do
      @organization.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::ALL_USERS, actor: @setting_user)

      refute @organization.limits_organizations_codespaces_to_selected_users?
    end
  end

  context "#limit_organization_codespaces_to_users?" do
    test "returns true if ALL_USERS is the user limit for the organizations" do
      @organization.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::ALL_USERS, actor: @setting_user)

      assert @organization.limit_organization_codespaces_to_users?
    end

    test "returns false if ALL_USERS is not the user limit for the organizations" do
      @organization.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::ALL_USERS_AND_OUTSIDE_COLLABORATORS, actor: @setting_user)

      refute @organization.limit_organization_codespaces_to_users?
    end
  end

  context "#limit_organization_codespaces_to_users_and_collaborators?" do
    test "returns true if ALL_USERS_AND_OUTSIDE_COLLABORATORS is the user limit for the organizations" do
      @organization.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::ALL_USERS_AND_OUTSIDE_COLLABORATORS, actor: @setting_user)

      assert @organization.limit_organization_codespaces_to_users_and_collaborators?
    end

    test "returns false if ALL_USERS_AND_OUTSIDE_COLLABORATORS is not the user limit for the organizations" do
      @organization.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::ALL_USERS, actor: @setting_user)

      refute @organization.limit_organization_codespaces_to_users_and_collaborators?
    end
  end
end
