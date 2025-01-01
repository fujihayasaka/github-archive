# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesScheduleEnvironmentRestorationTest < GitHub::TestCase

  fixtures do
    user = create(:user)
    plan = create(:codespace_plan)
    @codespace = create(:codespace,
      :deprovisioned,
      deleted_at: Time.current,
      plan: plan,
      owner: user,
      billable_owner: user,
      ref: "master",
      guid: "069d8015-2352-4c53-b814-2a4ca3441785"
    )
  end

  test "job is enqueued" do
    FakeVSOServer.reset!
    FakeVSOServer.environments << {
        "id" => @codespace.guid,
        "updated" => Time.now.iso8601.to_s,
        "plan" => @codespace.plan.name,
        "state" => Codespaces::Vscs::State::DELETED
    }
    Codespaces::ScheduleEnvironmentRestoration.call(@codespace)

    assert_enqueued_with(job: CodespacesRestoreJob, args: [codespace: @codespace])
  end

  test "does not enqueue if codespace is not Deleted" do
    FakeVSOServer.reset!
    FakeVSOServer.environments << {
        "id" => @codespace.guid,
        "updated" => Time.now.iso8601.to_s,
        "plan" => @codespace.plan.name,
        "state" => Codespaces::Vscs::State::SHUTDOWN
    }

    @codespace.update!(state: :provisioned, deleted_at: nil)

    assert_no_enqueued_jobs(only: CodespacesRestoreJob) do
      assert_raises(Codespaces::ScheduleEnvironmentRestoration::UnrestorableEnvironmentError) do
        Codespaces::ScheduleEnvironmentRestoration.call(@codespace)
      end
    end
  end

  test "does not enqueue if codespace is Failed" do
    FakeVSOServer.reset!
    FakeVSOServer.environments << {
        "id" => @codespace.guid,
        "updated" => Time.now.iso8601.to_s,
        "plan" => @codespace.plan.name,
        "state" => Codespaces::Vscs::State::FAILED
    }

    @codespace.update!(state: :provisioned, deleted_at: nil)

    assert_no_enqueued_jobs(only: CodespacesRestoreJob) do
      assert_raises(Codespaces::ScheduleEnvironmentRestoration::UnrestorableEnvironmentError) do
        Codespaces::ScheduleEnvironmentRestoration.call(@codespace)
      end
    end
  end

  test "does not enqueue if environment is not found" do
    FakeVSOServer.reset!
    FakeVSOServer.environments << {
      "id" => "not-ours",
      "updated" => Time.now.iso8601.to_s,
      "plan" => @codespace.plan.name,
      "state" => Codespaces::Vscs::State::SHUTDOWN
  }

    assert_no_enqueued_jobs(only: CodespacesRestoreJob) do
      assert_raises(Codespaces::ScheduleEnvironmentRestoration::UnrestorableEnvironmentError) do
        Codespaces::ScheduleEnvironmentRestoration.call(@codespace)
      end
    end
  end
end unless GitHub.enterprise?
