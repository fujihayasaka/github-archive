# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class UpdateLockedRepositoriesJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @user = create(:user)
  end

  test "doesn't raise on deleted user" do
    @user.delete

    assert_nil UpdateLockedRepositoriesJob.perform_now(@user.id)
  end

  test "works" do
    User.any_instance.expects(:update_locked_repositories).once

    UpdateLockedRepositoriesJob.perform_now(@user.id)
  end

  test "retry conditions" do
    assert_retry_on_dirty_exit job: UpdateLockedRepositoriesJob, args: [@user.id]
  end
end
