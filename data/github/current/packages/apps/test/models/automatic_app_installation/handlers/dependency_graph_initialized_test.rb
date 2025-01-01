# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dependabot_github_app_helper"

class AutomaticAppInstallation::Handlers::DependencyGraphInitializedTest < GitHub::TestCase
  include DependabotGithubAppHelper

  fixtures do
    make_trusted_oauth_apps_owner
    @repo = create(:repository, :minimal)
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
    @trigger = create(:integration_install_trigger, integration: @app, install_type: :dependency_graph_initialized)
  end

  def setup_dependabot_trigger
    @dependabot = create(:dependabot_integration)
    @dependabot_trigger = create(:integration_install_trigger, integration: @dependabot, install_type: :dependency_graph_initialized)
  end

  def trigger_install
    AutomaticAppInstallation.trigger(
      type: :dependency_graph_initialized,
      originator: @repo,
      actor: @repo.owner,
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
            :entry_point => :automatic_app_installation_handler_dependency_graph_initialized
          },
        ]

        if GitHub.dependabot_enabled?
          assert_enqueued_with job: MassInstallAutomaticIntegrationsJob, args: expected_arguments do
            trigger_install
          end
        else
          assert_no_enqueued_jobs only: MassInstallAutomaticIntegrationsJob
        end
      end
    end

    test "it does not perform Dependabot-specific after install actions" do
      setup_generic_trigger

      UpdateRepositoryVulnerabilityAlertsJob.expects(:enqueue_for_repository).never

      perform_enqueued_jobs(only: MassInstallAutomaticIntegrationsJob) do
        trigger_install
      end
    end
  end

  context "the Dependabot application", skip_enterprise: true do
    test "it performs Dependabot-specific after install actions" do
      setup_dependabot_trigger

      UpdateRepositoryVulnerabilityAlertsJob.expects(:enqueue_for_repository).
                                             with(@repo, equals({ reason: :on_initialize })).once

      perform_enqueued_jobs(only: MassInstallAutomaticIntegrationsJob) do
        trigger_install
      end

      @repo.reload
    end
  end
end
