# typed: true
# frozen_string_literal: true

require "test_helper"

class UpdatedTrustedRepositoryAccessTest < GitHub::TestCase
  fixtures do
    make_trusted_oauth_apps_owner
    create(:codespaces_integration)

    @user = create(:user, login: "codespace-owner")
    @user_repo1 = create(:repository, owner: @user)
    @user_repo2 = create(:repository, owner: @user)
  end

  context ".call" do
    test "does nothing if the configuration has not been set (default is DISABLED)" do
      Codespaces::UpdateTrustedRepositoryAccess.call(actor: @user, target: @user, entry_point: :test_case)
      installation = find_installation(@user)

      refute installation
    end

    test "allows extended repo access to all of the target's repositories when ALL_REPOS is set" do
      assert_equal @user.codespace_trusted_repositories_access, Configurable::CodespaceTrustedRepositories::DISABLED

      Codespaces::UpdateTrustedRepositoryAccess.call(
        actor: @user,
        target: @user,
        trusted_repo_setting: Configurable::CodespaceTrustedRepositories::ALL_REPOS,
        entry_point: :test_case
      )
      installation = find_installation(@user)

      assert_equal "all", installation.repository_selection
      assert_same_elements [@user_repo1.id, @user_repo2.id], installation.repository_ids
    end

    test "allows extended repo access to the chosen repositories when SELECTED_REPOS is set" do
      assert_equal @user.codespace_trusted_repositories_access, Configurable::CodespaceTrustedRepositories::DISABLED

      Codespaces::UpdateTrustedRepositoryAccess.call(
        actor: @user,
        target: @user,
        trusted_repo_setting: Configurable::CodespaceTrustedRepositories::SELECTED_REPOS,
        repo: @user_repo1.id,
        entry_point: :test_case
      )
      installation = find_installation(@user)

      assert_equal "selected", installation.repository_selection
      assert_same_elements [@user_repo1.id], installation.repository_ids
    end

    test "when SELECTED_REPOS chosen with no `repo`, creates an installation but grants no additional access" do
      Codespaces::UpdateTrustedRepositoryAccess.call(
        actor: @user,
        target: @user,
        trusted_repo_setting: Configurable::CodespaceTrustedRepositories::SELECTED_REPOS,
        entry_point: :test_case
      )
      installation = find_installation(@user)

      assert_equal "selected", installation.repository_selection
      assert_empty installation.repository_ids
    end

    test "updates an existing installation with the new repos" do
      Codespaces::UpdateTrustedRepositoryAccess.call(
        actor: @user,
        target: @user,
        trusted_repo_setting: Configurable::CodespaceTrustedRepositories::SELECTED_REPOS,
        repo: @user_repo1.id,
        entry_point: :test_case
      )
      installation = find_installation(@user)

      assert_same_elements [@user_repo1.id], installation.repository_ids

      Codespaces::UpdateTrustedRepositoryAccess.call(actor: @user, target: @user, repo: @user_repo2.id, entry_point: :test_case)
      assert_same_elements [@user_repo1.id, @user_repo2.id], installation.repository_ids
    end

    test "removes a repo from an existing installation" do
      Codespaces::UpdateTrustedRepositoryAccess.call(
        actor: @user,
        target: @user,
        trusted_repo_setting: Configurable::CodespaceTrustedRepositories::SELECTED_REPOS,
        repo: @user_repo1.id,
        entry_point: :test_case
      )
      Codespaces::UpdateTrustedRepositoryAccess.call(actor: @user, target: @user, repo: @user_repo2.id, entry_point: :test_case)
      installation = find_installation(@user)
      assert_same_elements [@user_repo1.id, @user_repo2.id], installation.repository_ids

      Codespaces::UpdateTrustedRepositoryAccess.call(actor: @user, target: @user, repo: @user_repo2.id, entry_point: :test_case)
      assert_same_elements [@user_repo1.id], installation.repository_ids
    end

    test "does nothing (and raises no exception) if the repo is nil" do
      # first add `@user_repo1` so there's an IntegrationInstallation
      Codespaces::UpdateTrustedRepositoryAccess.call(
        actor: @user,
        target: @user,
        trusted_repo_setting: Configurable::CodespaceTrustedRepositories::SELECTED_REPOS,
        repo: @user_repo1.id,
        entry_point: :test_case
      )

      assert_nothing_raised do
        Codespaces::UpdateTrustedRepositoryAccess.call(
          actor: @user,
          target: @user,
          trusted_repo_setting: Configurable::CodespaceTrustedRepositories::SELECTED_REPOS,
          repo: nil,
          entry_point: :test_case
        )
      end
    end

    test "raises RepositoryNotOwned if the repo passed isn't owned by the `target`" do
      repo = create(:repository)
      refute_equal @user, repo.owner

      assert_raises Codespaces::UpdateTrustedRepositoryAccess::RepositoryNotOwned do
        Codespaces::UpdateTrustedRepositoryAccess.call(
          actor: @user,
          target: @user,
          trusted_repo_setting: Configurable::CodespaceTrustedRepositories::SELECTED_REPOS,
          repo: repo.id,
          entry_point: :test_case
        )
      end
    end

    context "access configuration transitions" do
      test "DISABLED to ALL_REPOS" do
        Codespaces::UpdateTrustedRepositoryAccess.call(
          actor: @user,
          target: @user,
          trusted_repo_setting: Configurable::CodespaceTrustedRepositories::DISABLED,
          entry_point: :test_case
        )
        installation = find_installation(@user)
        refute installation

        # all
        Codespaces::UpdateTrustedRepositoryAccess.call(
          actor: @user,
          target: @user,
          trusted_repo_setting: Configurable::CodespaceTrustedRepositories::ALL_REPOS,
          entry_point: :test_case
        )
        installation = find_installation(@user)
        assert_equal "all", installation.repository_selection
        assert_same_elements [@user_repo1.id, @user_repo2.id], installation.repository_ids
      end

      test "DISABLED to SELECTED_REPOS" do
        Codespaces::UpdateTrustedRepositoryAccess.call(
          actor: @user,
          target: @user,
          trusted_repo_setting: Configurable::CodespaceTrustedRepositories::DISABLED,
          entry_point: :test_case
        )
        installation = find_installation(@user)
        refute installation

        # selected
        Codespaces::UpdateTrustedRepositoryAccess.call(
          actor: @user,
          target: @user,
          trusted_repo_setting: Configurable::CodespaceTrustedRepositories::SELECTED_REPOS,
          repo: @user_repo1.id,
          entry_point: :test_case
        )
        installation = find_installation(@user)
        assert_same_elements [@user_repo1.id], installation.repository_ids
      end

      test "ALL_REPOS do DISABLED" do
        Codespaces::UpdateTrustedRepositoryAccess.call(
          actor: @user,
          target: @user,
          trusted_repo_setting: Configurable::CodespaceTrustedRepositories::ALL_REPOS,
          entry_point: :test_case
        )
        installation = find_installation(@user)
        assert_equal "all", installation.repository_selection
        assert_same_elements [@user_repo1.id, @user_repo2.id], installation.repository_ids

        # disabled
        Codespaces::UpdateTrustedRepositoryAccess.call(
          actor: @user,
          target: @user,
          trusted_repo_setting: Configurable::CodespaceTrustedRepositories::DISABLED,
          entry_point: :test_case
        )
        installation = find_installation(@user)
        refute installation
      end

      test "ALL_REPOS to SELECTED_REPOS" do
        Codespaces::UpdateTrustedRepositoryAccess.call(
          actor: @user,
          target: @user,
          trusted_repo_setting: Configurable::CodespaceTrustedRepositories::ALL_REPOS,
          entry_point: :test_case
        )
        installation = find_installation(@user)
        assert_equal "all", installation.repository_selection
        assert_same_elements [@user_repo1.id, @user_repo2.id], installation.repository_ids

        # selected
        Codespaces::UpdateTrustedRepositoryAccess.call(
          actor: @user,
          target: @user,
          trusted_repo_setting: Configurable::CodespaceTrustedRepositories::SELECTED_REPOS,
          repo: @user_repo1.id,
          entry_point: :test_case
        )
        installation = find_installation(@user)
        assert_same_elements [@user_repo1.id], installation.repository_ids
      end

      test "SELECTED_REPOS to DISABLED" do
        Codespaces::UpdateTrustedRepositoryAccess.call(
          actor: @user,
          target: @user,
          trusted_repo_setting: Configurable::CodespaceTrustedRepositories::SELECTED_REPOS,
          repo: @user_repo1.id,
          entry_point: :test_case
        )
        installation = find_installation(@user)
        assert_same_elements [@user_repo1.id], installation.repository_ids

        # disabled
        Codespaces::UpdateTrustedRepositoryAccess.call(
          actor: @user,
          target: @user,
          trusted_repo_setting: Configurable::CodespaceTrustedRepositories::DISABLED,
          entry_point: :test_case
        )
        installation = find_installation(@user)
        refute installation
      end

      test "SELECTED_REPOS to ALL_REPOS" do
        Codespaces::UpdateTrustedRepositoryAccess.call(
          actor: @user,
          target: @user,
          trusted_repo_setting: Configurable::CodespaceTrustedRepositories::SELECTED_REPOS,
          repo: @user_repo1.id,
          entry_point: :test_case
        )
        installation = find_installation(@user)
        assert_same_elements [@user_repo1.id], installation.repository_ids

        Codespaces::UpdateTrustedRepositoryAccess.call(
          actor: @user,
          target: @user,
          trusted_repo_setting: Configurable::CodespaceTrustedRepositories::ALL_REPOS,
          entry_point: :test_case
        )
        installation = find_installation(@user)

        assert_equal "all", installation.repository_selection
        assert_same_elements [@user_repo1.id, @user_repo2.id], installation.repository_ids
      end
    end
  end

  def find_installation(target)
    target
      .integration_installations
      .find_by(integration: Apps::Internal.integration(:codespaces_production))
  end
end
