# typed: strict
# frozen_string_literal: true

require "test_helper"

class CopilotEngagedOssUserTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  test "factory" do
    assert build(:copilot_engaged_oss_user).valid?
  end

  test "validates" do
    copilot_engaged_oss_user = Copilot::EngagedOssUser.new
    refute copilot_engaged_oss_user.valid?

    refute_nil copilot_engaged_oss_user.errors[:language]
    refute_nil copilot_engaged_oss_user.errors[:engaged_oss_repository]
    refute_nil copilot_engaged_oss_user.errors[:role]
    refute_nil copilot_engaged_oss_user.errors[:user]

    copilot_engaged_oss_user.engaged_oss_repository = create(:copilot_engaged_oss_repository)
    refute copilot_engaged_oss_user.valid?
    copilot_engaged_oss_user.user = create(:user)
    refute copilot_engaged_oss_user.valid?
    copilot_engaged_oss_user.role = "something"
    refute copilot_engaged_oss_user.valid?
    copilot_engaged_oss_user.role = "admin"
    assert copilot_engaged_oss_user.valid?

    copilot_engaged_oss_user.save!
  end
end if GitHub.copilot_enabled?
