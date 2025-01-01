# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesScheduleEnvironmentSuspensionTest < GitHub::TestCase
  fixtures do
    user = create(:user)
    plan = create(:codespace_plan)
    @codespace = create(:codespace, plan: plan, owner: user, ref: "master", guid: "069d8015-2352-4c53-b814-2a4ca3441785")
  end
  test "job is enqueued" do
    FakeVSOServer.reset!
    FakeVSOServer.environments << {
        "id" => @codespace.guid,
        "updated" => Time.now.iso8601.to_s,
        "plan" => @codespace.plan.name
    }
    Codespaces::ScheduleEnvironmentSuspension.call(@codespace)

    assert_enqueued_with(job: CodespacesSuspendEnvironmentJob, args: [codespace: @codespace])
  end

  test "does not enqueue if environment is Shutdown" do
    FakeVSOServer.reset!
    FakeVSOServer.environments << {
        "id" => @codespace.guid,
        "updated" => Time.now.iso8601.to_s,
        "plan" => @codespace.plan.name,
        "state" => Codespaces::Vscs::State::SHUTDOWN
    }

    assert_no_enqueued_jobs(only: CodespacesSuspendEnvironmentJob) do
      Codespaces::ScheduleEnvironmentSuspension.call(@codespace)
    end
  end

  test "does not enqueue if environment is ShuttingDown" do
    FakeVSOServer.reset!
    FakeVSOServer.environments << {
        "id" => @codespace.guid,
        "updated" => Time.now.iso8601.to_s,
        "plan" => @codespace.plan.name,
        "state" => Codespaces::Vscs::State::SHUTTING_DOWN
    }

    assert_no_enqueued_jobs(only: CodespacesSuspendEnvironmentJob) do
      Codespaces::ScheduleEnvironmentSuspension.call(@codespace)
    end
  end
end unless GitHub.enterprise?
