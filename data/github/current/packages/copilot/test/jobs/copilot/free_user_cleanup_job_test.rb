# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::FreeUserCleanupJobTest < GitHub::TestCase
  include JobTestHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  test "deletes the free user" do
    free_user = create(:copilot_free_user)
    free_user.user.delete

    assert_changes -> { Copilot::FreeUser.count }, -1 do
      Copilot::FreeUserCleanupJob.perform_now(free_user.user_id)
    end
  end

  test "does nothing if the free user does not exist" do
    assert_no_changes -> { Copilot::FreeUser.count } do
      Copilot::FreeUserCleanupJob.perform_now(123)
    end
  end
end if GitHub.copilot_enabled?
