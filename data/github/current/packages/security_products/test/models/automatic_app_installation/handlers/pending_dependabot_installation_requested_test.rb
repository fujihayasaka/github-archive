# typed: true
# frozen_string_literal: true

require "test_helper"

class AutomaticAppInstallation::Handlers::PendingDependabotInstallationRequestedTest < GitHub::TestCase
  fixtures do
    @user = create(:user)

    make_trusted_oauth_apps_owner
    @dependabot_app = create(:dependabot_integration)

    @trigger_type = :pending_dependabot_installation_requested
    @trigger = create(:integration_install_trigger, integration: @dependabot_app, install_type: @trigger_type)

    @pending_installation = make_pending_automatic_installation(
      target: @user, trigger_type: @trigger_type,
    )
  end

  setup do
    # If we are testing for Enterprise, ensure Dependency Graph is enabled
    # as it is a prerequisite of Repository#enable_vulnerability_updates
    GitHub.stubs(dependency_graph_enabled?: true)
  end

  context "#install_integration" do
    test "installs the integration on targeted users" do
      handler = build_handler(
        install_triggers: [@trigger],
        originator: @pending_installation,
        actor: @pending_installation,
      )

      refute @dependabot_app.installed_on?(@user)
      perform_enqueued_jobs(only: [MassInstallAutomaticIntegrationsJob]) do
        handler.install_integration
      end

      assert @dependabot_app.installed_on?(@user)
      user_installations = IntegrationInstallation.with_user(@user)
      assert_equal 1, user_installations.size
      assert user_installations.first.installed_on_all_repositories?
    end

    test "installs the integration on targeted repositories" do
      repo = create(:repository, owner: @user)
      repo.enable_vulnerability_updates(actor: @user, enroll: false)
      non_installable_repo = create(:repository, owner: @user)

      pending_repo_installation = make_pending_automatic_installation(
        target: repo, trigger_type: @trigger_type,
      )

      handler = build_handler(
        install_triggers: [@trigger],
        originator: pending_repo_installation,
        actor: pending_repo_installation,
      )

      perform_enqueued_jobs(only: [MassInstallAutomaticIntegrationsJob]) do
        handler.install_integration
      end

      user_installations = IntegrationInstallation.with_user(@user)
      assert_equal 1, user_installations.size
      refute_empty user_installations.with_repository(repo)
      assert_empty user_installations.with_repository(non_installable_repo)
    end

    test "sets the pending install to failed if the target repository does not have Security Updates enabled" do
      repo = create(:repository, owner: @user)
      repo.disable_vulnerability_updates(actor: @user)

      pending_repo_installation = make_pending_automatic_installation(
        target: repo, trigger_type: @trigger_type,
      )

      handler = build_handler(
        install_triggers: [@trigger],
        originator: pending_repo_installation,
        actor: pending_repo_installation,
      )

      perform_enqueued_jobs(only: [MassInstallAutomaticIntegrationsJob]) do
        handler.install_integration
      end

      user_installations = IntegrationInstallation.with_user(@user)
      assert_empty user_installations.with_repository(repo)
      assert_predicate pending_repo_installation.reload, :failed?
      assert_equal "canceled", pending_repo_installation.reason
    end

    test "does not attempt to install if the pending installation has already been installed" do
      @pending_installation.installed!

      handler = build_handler(
        install_triggers: [@trigger],
        originator: @pending_installation,
        actor: @pending_installation,
      )

      assert_no_enqueued_jobs do
        handler.install_integration
      end

      refute @dependabot_app.installed_on?(@user)
    end

    test "does not attempt to install if the pending installation previously failed" do
      @pending_installation.failed!

      handler = build_handler(
        install_triggers: [@trigger],
        originator: @pending_installation,
        actor: @pending_installation,
      )

      assert_no_enqueued_jobs do
        handler.install_integration
      end

      refute @dependabot_app.installed_on?(@user)
    end

    test "sets the pending install to failed if the target repository is no longer eligible" do
      repo = create(:repository, owner: @user, active: false)

      pending_repo_installation = make_pending_automatic_installation(
        target: repo, trigger_type: @trigger_type,
      )

      handler = build_handler(
        install_triggers: [@trigger],
        originator: pending_repo_installation,
        actor: pending_repo_installation,
      )

      perform_enqueued_jobs(only: [MassInstallAutomaticIntegrationsJob]) do
        handler.install_integration
      end

      user_installations = IntegrationInstallation.with_user(@user)
      assert_empty user_installations.with_repository(repo)
      assert_predicate pending_repo_installation.reload, :failed?
      assert_equal "canceled", pending_repo_installation.reason
    end

    context "after_integration_installed callback" do
      test "marks the pending installation as installed" do
        handler = build_handler(
          install_triggers: [@trigger],
          originator: @pending_installation,
          actor: @pending_installation,
        )

        refute_predicate @pending_installation, :installed?

        perform_enqueued_jobs(only: [MassInstallAutomaticIntegrationsJob]) do
          handler.install_integration
        end

        assert_predicate @pending_installation.reload, :installed?
        refute_nil @pending_installation.installed_at
      end
    end
  end

  def build_handler(install_triggers:, originator:, actor:)
    AutomaticAppInstallation::Handlers::PendingDependabotInstallationRequested.new(
      install_triggers: install_triggers,
      originator: originator,
      actor: actor,
    )
  end
end
