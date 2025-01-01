# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class RemoveBizuserForksJobTest < GitHub::TestCase
  include JobTestHelper

  setup do
    @business = create :business
    @user = create :user
  end

  test "retry conditions" do
    assert_retry_on_dirty_exit job: RemoveBizUserForksJob, args: [biz_id: @business.id, belonging_to_user_id: @user.id], using_kwargs: true
    assert_retry_on_throttler_error job: RemoveBizUserForksJob, args: [biz_id: @business.id, belonging_to_user_id: @user.id], using_kwargs: true
  end
end
