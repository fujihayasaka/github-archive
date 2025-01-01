# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesRemoveOrgMemberAccessJobTest < GitHub::TestCase
  fixtures do
    @org = create :codespaces_organization
    @user = create :user
  end

  test "does nothing for org member", skip_enterprise: true do
    @org.add_member(@user)
    @org.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::SELECTED_USERS, actor: @user)
    Codespaces::OrgPolicy.grant_billing_permission!(@user, @org)

    CodespacesRemoveOrgMemberAccessJob.perform_now(@org, @user)

    assert has_user_role?
  end

  test "does nothing for org outside collaborator", skip_enterprise: true do
    repo = create(:repository, owner: @org)
    repo.add_member(@user)
    @org.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::SELECTED_USERS, actor: @user)
    Codespaces::OrgPolicy.grant_billing_permission!(@user, @org)

    CodespacesRemoveOrgMemberAccessJob.perform_now(@org, @user)

    assert has_user_role?
  end

  test "revokes access to Codespaces if user isn't either", skip_enterprise: true do
    @org.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::SELECTED_USERS, actor: @user)
    Codespaces::OrgPolicy.grant_billing_permission!(@user, @org)
    assert has_user_role?

    CodespacesRemoveOrgMemberAccessJob.perform_now(@org, @user)

    refute has_user_role?
  end

  def has_user_role?
    UserRole.includes(:role).where(
      roles: { name: Codespaces::OrgPolicy::CODESPACE_ORG_CREATOR_ROLE },
      target_id: @org.id,
      target_type: "Organization",
      actor_type: "User",
      actor_id: @user.id,
    ).any?
  end
end
