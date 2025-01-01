# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.guard_audit_log_staff_actor?
  class TheStaffUserTest < GitHub::TestCase
    setup do
      setup_staff_user
    end
    test "match login" do
      assert_equal GitHub.staff_user_login, User.staff_user.login
    end
  end
end
