# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::Users::CodeReviewTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  fixtures do
    @user = create(:user)
  end

  setup do
    @copilot_user = Copilot::User.new(@user)
  end

  test "user is enrolled into legacy feature flag" do
    enable_feature_flag(:copilot_code_review_v1, @user)
    disable_feature_flag(:copilot_code_review_public_preview)

    assert @copilot_user.copilot_code_review_enabled?
  end

  test "user is allowed to use code review" do
    enable_feature_flag(:copilot_code_review_public_preview, @user)

    assert @copilot_user.copilot_code_review_enabled?
  end

  test "user is not allowed to use code review" do
    disable_feature_flag(:copilot_code_review_v1)
    disable_feature_flag(:copilot_code_review_public_preview)

    refute @copilot_user.copilot_code_review_enabled?
  end
end if GitHub.copilot_enabled?
