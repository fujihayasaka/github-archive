# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::LimitedUserCleanupJobTest < GitHub::TestCase
  include JobTestHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  test "deletes the limited user" do
    limited_user = create(:copilot_limited_user)
    limited_user.user.delete

    assert_changes -> { Copilot::LimitedUser.count }, -1 do
      Copilot::LimitedUserCleanupJob.perform_now(limited_user.user_id)
    end
  end

  test "does nothing if the free user does not exist" do
    assert_no_changes -> { Copilot::LimitedUser.count } do
      Copilot::LimitedUserCleanupJob.perform_now(123)
    end
  end
end if GitHub.copilot_enabled?
