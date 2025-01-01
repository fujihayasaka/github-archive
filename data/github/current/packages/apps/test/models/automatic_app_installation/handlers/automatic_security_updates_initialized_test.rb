# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "test_helpers/dependabot_github_app_helper"

class AutomaticAppInstallation::Handlers::AutomaticSecurityUpdatesInitializedTest < GitHub::TestCase
  include JobTestHelper
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
    @trigger = create(:integration_install_trigger, integration: @app, install_type: :automatic_security_updates_initialized)
  end

  def setup_dependabot_trigger
    @dependabot = create(:dependabot_integration)
    @dependabot_trigger = create(:integration_install_trigger, integration: @dependabot, install_type: :automatic_security_updates_initialized)
  end

  def trigger_install
    AutomaticAppInstallation.trigger(
      type: :automatic_security_updates_initialized,
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
            :entry_point => :automatic_app_installation_handler_security_updates_initialized,
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

      Dependabot::RepositoryEnrollJob.expects(:perform_later).never

      perform_enqueued_jobs(only: InstallAutomaticIntegrationsJob) do
        trigger_install
      end
    end
  end

  context "the Dependabot application", skip_enterprise: true do
    test "it performs Dependabot-specific after install actions" do
      setup_dependabot_trigger

      Dependabot::RepositoryEnrollJob.expects(:perform_later).with(@repo.id).once

      perform_enqueued_jobs(only: InstallAutomaticIntegrationsJob) do
        trigger_install
      end
    end

    test "retry conditions" do
      assert_retry_on_dirty_exit job: Dependabot::RepositoryEnrollJob, args: [@repo.id]
    end
  end
end
