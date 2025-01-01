# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dependabot_github_app_helper"

class AutomaticAppInstallation::Handlers::DependencyUpdateRequestedTest < GitHub::TestCase
  include DependabotGithubAppHelper

  fixtures do
    make_trusted_oauth_apps_owner
    @repo = create(:repository, :minimal)
    @dependency_update = create(:repository_dependency_update, repository: @repo)
  end

  setup do
    reset_dependabot_github_app_memoization
  end

  def setup_generic_trigger
    @app = create(
      :integration,
      name: "dependabot test",
      default_permissions: { "contents" => :read },
    )
    @trigger = create(:integration_install_trigger, integration: @app, install_type: :dependency_update_requested)
  end

  def setup_dependabot_trigger
    @dependabot = create(:dependabot_integration)
    @dependabot_trigger = create(:integration_install_trigger, integration: @dependabot, install_type: :dependency_update_requested)
  end

  def trigger_install
    AutomaticAppInstallation.trigger(
      type: :dependency_update_requested,
      originator: @dependency_update,
      actor: @repo,
    )
  end

  context "a generic application" do
    test "installs integration on one repository" do
      setup_generic_trigger

      Timecop.freeze do
        expected_arguments = [
          @repo.owner.id,
          @trigger.integration.id,
          @trigger.id,
          [@repo.id],
          {
            "enqueued_timestamp" => Time.now.to_i,
            "dependency_update_id" => @dependency_update.id,
            :entry_point => :automatic_app_installation_handler_dependency_update_requested
          },
        ]

        if GitHub.dependabot_enabled?
          assert_enqueued_with job: InstallAutomaticIntegrationsJob, args: expected_arguments do
            trigger_install
          end
        else
          assert_no_enqueued_jobs only: InstallAutomaticIntegrationsJob
        end
      end
    end

    test "it does not perform Dependabot-specific after install actions" do
      setup_generic_trigger

      RepositoryDependencyUpdate.expects(:find).never

      perform_enqueued_jobs(only: InstallAutomaticIntegrationsJob) do
        trigger_install
      end
    end

    test "it does not perform Dependabot-specific already installed actions" do
      setup_generic_trigger
      make_integration_installation(integration: @app, repository: @repo)

      RepositoryDependencyUpdate.expects(:find).never

      perform_enqueued_jobs(only: InstallAutomaticIntegrationsJob) do
        trigger_install
      end
    end
  end

  context "the Dependabot application", skip_enterprise: true do
    test "it performs Dependabot-specific after install actions" do
      setup_dependabot_trigger

      RepositoryDependencyUpdate.expects(:find_by).
                                 with(id: @dependency_update.id).
                                 returns(@dependency_update)

      @dependency_update.expects(:enqueue_vulnerability_update_in_hydro).with do |args|
        args[:dependabot_install_id] == @repo.dependabot_install.id
      end.once

      perform_enqueued_jobs(only: InstallAutomaticIntegrationsJob) do
        trigger_install
      end
    end

    test "it performs Dependabot-specific already installed actions" do
      setup_dependabot_trigger
      make_integration_installation(integration: @dependabot, repository: @repo)

      RepositoryDependencyUpdate.expects(:find_by).
                                 with(id: @dependency_update.id).
                                 returns(@dependency_update)

      @dependency_update.expects(:enqueue_vulnerability_update_in_hydro).with do |args|
        args[:dependabot_install_id] == @repo.dependabot_install.id
      end.once

      perform_enqueued_jobs(only: InstallAutomaticIntegrationsJob) do
        trigger_install
      end
    end
  end
end
