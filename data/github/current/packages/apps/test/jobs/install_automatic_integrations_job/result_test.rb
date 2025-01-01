# typed: true
# frozen_string_literal: true
require "test_helper"

class InstallAutomaticIntegrationsJob::ResultTest < GitHub::TestCase
  include GitHub::LoggerHelper

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @job = InstallAutomaticIntegrationsJob.new
    @klass = InstallAutomaticIntegrationsJob::Result

    @target = create(:user, login: "monalisa")

    @app_owner = create(:user,  login: "app-owner")
    @integration = create(:integration, owner: @app_owner, name: "my app")

    @installation = make_integration_installation(
      target: @target, integration: @integration,
    )
  end

  test "logs information about a Result on success" do
    expected_log = {
      "gh.job.name" => "InstallAutomaticIntegrations",
      "gh.job.status" => "installed",
      "gh.job.installation_queue" => "install_automatic_integrations",
      "gh.integration.id" => @integration.id,
      "gh.integration.owner.id" => @app_owner.id,
      "gh.installation.target.id" => @target.id,
    }

    assert_logged(**expected_log) do
      result = @klass.success(@job, :installed, @installation, [])
      assert_predicate result, :success?
    end
  end

  test "logs information about a Result when failed" do
    expected_log = {
      "gh.job.name" => "InstallAutomaticIntegrations",
      "gh.job.status" => "failed_to_update",
      "gh.job.installation_queue" => "install_automatic_integrations",
      "gh.integration.id" => @integration.id,
      "gh.integration.owner.id" => @app_owner.id,
      "gh.installation.target.id" => @target.id,
      "gh.job.exception_message" => "boom",
      "gh.job.reason" => "something went wrong",
    }

    assert_logged(**expected_log) do
      result = @klass.failed(
        @job,
        :failed_to_update,
        @target,
        @integration,
        exception: RuntimeError.new("boom"),
        reason: "something went wrong",
      )
      assert_predicate result, :failed?
    end
  end

  test "logs information about a Result when already_installed" do
    expected_log = {
      "gh.job.name" => "InstallAutomaticIntegrations",
      "gh.job.status" => "installed_on_all_repositories",
      "gh.job.installation_queue" => "install_automatic_integrations",
      "gh.integration.id" => @integration.id,
      "gh.integration.owner.id" => @app_owner.id,
      "gh.installation.target.id" => @target.id,
    }

    assert_logged(**expected_log) do
      result = @klass.already_installed(
        @job,
        :installed_on_all_repositories,
        @installation,
      )
      assert_predicate result, :success?
    end
  end

  test "logs Results for MassInstallAutomaticIntegrations jobs" do
    expected_log = {
      "gh.job.name" => "MassInstallAutomaticIntegrations",
      "gh.job.status" => "already_installed",
      "gh.job.installation_queue" => "mass_install_automatic_integrations",
      "gh.integration.id" => @integration.id,
      "gh.integration.owner.id" => @app_owner.id,
      "gh.installation.target.id" => @target.id,
    }

    assert_logged(**expected_log) do
      result = @klass.already_installed(
        MassInstallAutomaticIntegrationsJob.new,
        :already_installed,
        @installation,
      )
      assert_predicate result, :success?
    end
  end
end
