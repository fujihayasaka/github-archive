# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CopilotFreeUserExpirationJobTest < GitHub::TestCase
  include JobTestHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  test "calls the free user command" do
    free_user = create(:copilot_free_user)

    Copilot::FreeUser
      .any_instance
      .expects(:cancel!)
      .once

    Copilot::FreeUserCancellationJob.perform_now(free_user.id)
  end

  test "deletes the user" do
    free_user = create(:copilot_free_user)

    assert_changes -> { Copilot::FreeUser.count }, -1 do
      Copilot::FreeUserCancellationJob.perform_now(free_user.id)
    end
  end

  test "does nothing if the free user does not exist" do
    assert_no_changes -> { Copilot::FreeUser.count } do
      Copilot::FreeUserCancellationJob.perform_now(123)
    end
  end
end if GitHub.copilot_enabled?
