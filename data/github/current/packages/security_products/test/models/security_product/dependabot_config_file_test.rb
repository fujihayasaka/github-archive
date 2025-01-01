# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dependabot_github_app_helper"

class SecurityProduct::DependabotConfigFileTest < GitHub::TestCase
  include DependabotGithubAppHelper

  SUPPORTING_JOBS = [
    InstallAutomaticIntegrationsJob,
    Dependabot::RepositoryForkConfigFileEnabledJob,
    Dependabot::RepositoryForkConfigFileDisabledJob
  ]

  fixtures do
    @user = create(:verified_user)
    @org  = create(:organization, admin: @user)
    @repo = create(:repository, owner: @org)
    @fork = create(:fork_repository, forker: @user, fork_repo: @repo)

    make_trusted_oauth_apps_owner
    @dependabot = create(:dependabot_integration)
    create(:dependabot_button_clicked_trigger, integration: @dependabot)
  end

  setup do
    GitHub.stubs(dependabot_enabled?: true) if GitHub.enterprise?
    reset_dependabot_github_app_memoization
  end

  context "#enabled?" do
    test "returns true when the repository is not a fork" do
      refute @repo.fork?

      config_file_service = SecurityProduct::DependabotConfigFile.new(@repo)

      assert config_file_service.enabled?
    end

    test "returns false when version updates have not been enabled on a fork" do
      config_file_service = SecurityProduct::DependabotConfigFile.new(@fork)

      refute config_file_service.enabled?
    end

    test "returns true when version updates have been enabled on a fork" do
      config_file_service = SecurityProduct::DependabotConfigFile.new(@fork)

      _, err = config_file_service.enable(actor: @user)
      refute err

      assert config_file_service.enabled?
    end
  end

  context "#disabled?" do
    test "returns false when the repository is not a fork" do
      refute @repo.fork?

      config_file_service = SecurityProduct::DependabotConfigFile.new(@repo)

      refute config_file_service.disabled?
    end

    test "returns true when version updates have not been enabled on a fork" do
      config_file_service = SecurityProduct::DependabotConfigFile.new(@fork)

      assert config_file_service.disabled?
    end

    test "returns false when version updates have been enabled on a fork" do
      config_file_service = SecurityProduct::DependabotConfigFile.new(@fork)

      _, err = config_file_service.enable(actor: @user)
      refute err

      refute config_file_service.disabled?
    end
  end

  context "installation on enablement" do
    test "Dependabot is installed during the enablement process" do
      config_file_service = SecurityProduct::DependabotConfigFile.new(@fork)
      refute config_file_service.enabled?
      refute dependabot_installed?(@fork)

      perform_enqueued_jobs(only: SUPPORTING_JOBS) do
        _, err = config_file_service.enable(actor: @user)
        refute err
      end

      assert config_file_service.enabled?
      assert dependabot_installed?(@fork)
    end
  end

  def dependabot_installed?(repository)
    # clear Dependabot installation memoization
    repository.reload_dependabot_install
    repository.dependabot_installed?
  end

  context "#enable" do
    context "a Dependabot install already exists" do
      test "notifies Dependabot API to resync the configuration when enabled on a fork" do
        @dependabot.install_on(@fork.owner, repositories: [@fork], installer: @fork.owner, entry_point: :test_case)
        assert @fork.dependabot_installed?

        config_file_service = SecurityProduct::DependabotConfigFile.new(@fork)

        perform_enqueued_jobs(only: SUPPORTING_JOBS) do
          _, err = config_file_service.enable(actor: @user)
          refute err
        end

        assert_equal FakeDependabotServer.requests, 1
        assert_equal FakeDependabotServer.rpc_calls, ["ResyncConfigFile"]
      end

      test "does not notify Dependabot API when enabled on a non-fork" do
        @dependabot.install_on(@repo.owner, repositories: [@repo], installer: @user, entry_point: :test_case)
        assert @repo.dependabot_installed?

        config_file_service = SecurityProduct::DependabotConfigFile.new(@repo)

        perform_enqueued_jobs(only: SUPPORTING_JOBS) do
          _, err = config_file_service.enable(actor: @user)
          refute err
        end

        assert_equal FakeDependabotServer.requests, 0
      end
    end

    context "a Dependabot install does not exist" do
      test "does not notify Dependabot API to resync the configuration on a fork" do
        refute @fork.dependabot_installed?

        config_file_service = SecurityProduct::DependabotConfigFile.new(@fork)

        perform_enqueued_jobs(only: SUPPORTING_JOBS) do
          _, err = config_file_service.enable(actor: @user)
          refute err
        end

        assert_equal FakeDependabotServer.requests, 0
      end
    end
  end

  context "#disable" do
    context "a Dependabot install already exists" do
      test "notifies Dependabot API to deactivate any configuration when disabled on a fork" do
        @dependabot.install_on(@fork.owner, repositories: [@fork], installer: @fork.owner, entry_point: :test_case)
        assert @fork.dependabot_installed?

        config_file_service = SecurityProduct::DependabotConfigFile.new(@fork)

        perform_enqueued_jobs(only: SUPPORTING_JOBS) do
          _, err = config_file_service.disable(actor: @user)
          refute err
        end

        assert_equal FakeDependabotServer.requests, 1
        assert_equal FakeDependabotServer.rpc_calls, ["DeactivateUpdateConfigs"]
      end

      test "does not notify Dependabot API when disabled on a non-fork" do
        @dependabot.install_on(@repo.owner, repositories: [@repo], installer: @user, entry_point: :test_case)
        assert @repo.dependabot_installed?

        config_file_service = SecurityProduct::DependabotConfigFile.new(@repo)

        perform_enqueued_jobs(only: SUPPORTING_JOBS) do
          _, err = config_file_service.disable(actor: @user)
          refute err
        end

        assert_equal FakeDependabotServer.requests, 0
      end
    end

    context "a Dependabot install does not exist" do
      test "does not notify Dependabot API to deactivate configuration on a fork" do
        refute @fork.dependabot_installed?

        config_file_service = SecurityProduct::DependabotConfigFile.new(@fork)

        perform_enqueued_jobs(only: SUPPORTING_JOBS) do
          _, err = config_file_service.disable(actor: @user)
          refute err
        end

        assert_equal FakeDependabotServer.requests, 0
      end
    end
  end
end
