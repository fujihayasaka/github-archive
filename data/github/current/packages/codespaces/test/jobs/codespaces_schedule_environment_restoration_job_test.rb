# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::ScheduleEnvironmentRestorationJobTest < GitHub::TestCase
  include GitHub::LoggerHelper

  fixtures do
    @user = create(:user)
    @deleted_codespace = create(:codespace, owner: @user, billable_owner: @user, deleted_at: Time.current, shutdown_at: Time.current, deletion_reason: Codespace.deletion_reasons[:user_requested])
    @deleted_codespace.deprovisioned!
  end

  test "calls ScheduleEnvironmentRestoration command" do
    Codespaces::ScheduleEnvironmentRestoration.expects(:call).with(@deleted_codespace)
    Codespaces::ScheduleEnvironmentRestorationJob.perform_now(codespace: @deleted_codespace)
  end

  test "logs unrestorable environment" do
    Codespaces::ScheduleEnvironmentRestoration.expects(:call).with(@deleted_codespace).raises(Codespaces::ScheduleEnvironmentRestoration::UnrestorableEnvironmentError)

    expected_log = {
      "Body" => "Unrestorable environment",
      "SeverityText" => "WARN",
      "code.namespace" => "Codespaces::CodespacesScheduleEnvironmentRestorationJob",
      "code.function" => "perform",
      "gh.codespaces.name" => @deleted_codespace.name,
      "gh.codespaces.guid" => @deleted_codespace.guid,
    }

    perform_enqueued_jobs(only: [Codespaces::ScheduleEnvironmentRestorationJob]) do
      assert_logged(**expected_log) do
        Codespaces::ScheduleEnvironmentRestorationJob.perform_now(codespace: @deleted_codespace)
      end
    end
  end
end
