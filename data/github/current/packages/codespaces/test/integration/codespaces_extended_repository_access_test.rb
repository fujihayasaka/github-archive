# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

class CodespacesExtendedRepositoryAccessTest < GitHub::IntegrationTestCase
  include PermissionsHelper

  fixtures do
    make_trusted_oauth_apps_owner
    create(:codespaces_integration)

    @user = create(:user)
    @org = create(:codespaces_credit_card_organization, plan: GitHub::Plan.business, admin: @user)
    Codespaces::OrgPolicy.grant_billing_permission!(@user, @org)

    @user_repo = create(:repository, owner: @user)
    @user_repo2 = create(:repository, owner: @user)
    @org_repo = create(:repository, owner: @org)
    @org_repo2 = create(:repository, owner: @org)

    @user_repo_codespace = create(:codespace, repository: @user_repo, owner: @user)
    @org_repo_codespace = create(:codespace, repository: @org_repo, owner: @user)
  end

  context "user trusted repositories", skip_with_all_emus: true do
    # Skipping EMU since this is a deprecated feature
    test "extended repository access isn't granted when the repo owner trusts no repositories" do
      Codespaces::UpdateTrustedRepositoryAccess.call(actor: @user, target: @user, trusted_repo_setting: Configurable::CodespaceTrustedRepositories::DISABLED, entry_point: :test_case)
      _, installation = Codespaces::Tokens.grant_repository_access(@user, @user_repo_codespace)

      assert_specific_repo_access(installation, @user_repo)
      refute_specific_repo_access(installation, @user_repo2)
      refute_access_to_all_repos(installation, @user)
    end

    test "extended repository access is granted when the repo owner trusts all repositories" do
      Codespaces::UpdateTrustedRepositoryAccess.call(actor: @user, target: @user, trusted_repo_setting: Configurable::CodespaceTrustedRepositories::ALL_REPOS, entry_point: :test_case)
      _, installation = Codespaces::Tokens.grant_repository_access(@user, @user_repo_codespace)

      refute_specific_repo_access(installation, @user_repo)
      refute_specific_repo_access(installation, @user_repo2)
      assert_access_to_all_repos(installation, @user)
    end

    test "extended repository access is granted when the repo owner trusts the codespace's repository" do
      Codespaces::UpdateTrustedRepositoryAccess.call(actor: @user, target: @user, trusted_repo_setting: Configurable::CodespaceTrustedRepositories::SELECTED_REPOS, repo: @user_repo, entry_point: :test_case)
      _, installation = Codespaces::Tokens.grant_repository_access(@user, @user_repo_codespace)

      refute_specific_repo_access(installation, @user_repo)
      refute_specific_repo_access(installation, @user_repo2)
      assert_access_to_all_repos(installation, @user)
    end
  end

  context "organization trusted repositories", skip_with_all_emus: true do
    # Skipping EMU tests since this is a deprecated feature
    test "extended repository access isn't granted when an org trusts none of its repositories" do
      Codespaces::UpdateTrustedRepositoryAccess.call(actor: @user, target: @org, trusted_repo_setting: Configurable::CodespaceTrustedRepositories::DISABLED, entry_point: :test_case)
      _, installation = Codespaces::Tokens.grant_repository_access(@user, @org_repo_codespace)

      assert_specific_repo_access(installation, @org_repo)
      refute_specific_repo_access(installation, @org_repo2)
      refute_access_to_all_repos(installation, @org)
    end

    test "extended repository access is granted when an org trusts all of its repositories" do
      Codespaces::UpdateTrustedRepositoryAccess.call(actor: @user, target: @org, trusted_repo_setting: Configurable::CodespaceTrustedRepositories::ALL_REPOS, entry_point: :test_case)
      _, installation = Codespaces::Tokens.grant_repository_access(@user, @org_repo_codespace)
      refute_specific_repo_access(installation, @org_repo)
      refute_specific_repo_access(installation, @org_repo2)
      assert_access_to_all_repos(installation, @org)
    end

    test "extended repository access is granted when an org trusts the codespace's repository" do
      Codespaces::UpdateTrustedRepositoryAccess.call(actor: @user, target: @org, trusted_repo_setting: Configurable::CodespaceTrustedRepositories::SELECTED_REPOS, repo: @org_repo, entry_point: :test_case)
      _, installation = Codespaces::Tokens.grant_repository_access(@user, @org_repo_codespace)

      refute_specific_repo_access(installation, @org_repo)
      refute_specific_repo_access(installation, @org_repo2)
      assert_access_to_all_repos(installation, @org)
    end

    test "extended repository access isn't granted when an org disallows codespaces entirely" do
      Codespaces::UpdateTrustedRepositoryAccess.call(actor: @user, target: @org, trusted_repo_setting: Configurable::CodespaceTrustedRepositories::SELECTED_REPOS, repo: @org_repo, entry_point: :test_case)
      @org.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::DISABLED, actor: @user)
      new_org_repo_codespace = create(:codespace, repository: @org_repo, owner: @user, enable_org_access: false)
      _, installation = Codespaces::Tokens.grant_repository_access(@user, new_org_repo_codespace)

      assert_specific_repo_access(installation, @org_repo)
      refute_specific_repo_access(installation, @org_repo2)
      refute_access_to_all_repos(installation, @org)
    end

    test "extended repository access isn't granted when an org disallows codespaces for the user" do
      Codespaces::UpdateTrustedRepositoryAccess.call(actor: @user, target: @org, trusted_repo_setting: Configurable::CodespaceTrustedRepositories::SELECTED_REPOS, repo: @org_repo, entry_point: :test_case)
      Codespaces::OrgPolicy.revoke_billing_permission!(@user, @org)
      @org.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::DISABLED, actor: @user)
      new_org_repo_codespace = create(:codespace, repository: @org_repo, owner: @user, enable_org_access: false)
      _, installation = Codespaces::Tokens.grant_repository_access(@user, new_org_repo_codespace)

      assert_specific_repo_access(installation, @org_repo)
      refute_specific_repo_access(installation, @org_repo2)
      refute_access_to_all_repos(installation, @org)
    end
  end

  def assert_specific_repo_access(installation, repo)
    assert_actor_and_subject_granted_in_permissions_table(
      actor:   installation,
      subject: repo.resources.metadata,
      action:  :read,
    )
  end

  def refute_specific_repo_access(installation, repo)
    refute_actor_and_subject_granted_in_permissions_table(
      actor:   installation,
      subject: repo.resources.metadata,
      action:  :read,
    )
  end

  def assert_access_to_all_repos(installation, owner)
    assert_actor_and_subject_granted_in_permissions_table(
      actor:   installation,
      subject: owner.repository_resources.metadata,
      action:  :read,
    )
  end

  def refute_access_to_all_repos(installation, owner)
    refute_actor_and_subject_granted_in_permissions_table(
      actor:   installation,
      subject: owner.repository_resources.metadata,
      action:  :read,
    )
  end
end unless GitHub.enterprise?
