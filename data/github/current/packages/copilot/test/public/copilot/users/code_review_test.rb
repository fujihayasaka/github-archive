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
    GitHub.flipper[:copilot_pr_reviews_v1].enable(@user)
    GitHub.flipper[:copilot_code_review_public_preview].disable
    GitHub.flipper[:copilot_code_review_public_preview_denylist].disable

    assert @copilot_user.copilot_code_review_enabled?
  end

  test "user is allowed to use code review" do
    GitHub.flipper[:copilot_code_review_public_preview].enable(@user)
    GitHub.flipper[:copilot_code_review_public_preview_denylist].disable

    assert @copilot_user.copilot_code_review_enabled?
  end

  test "user is allowed to use code review but is in denylist" do
    GitHub.flipper[:copilot_pr_reviews_v1].disable
    GitHub.flipper[:copilot_code_review_public_preview].enable(@user)
    GitHub.flipper[:copilot_code_review_public_preview_denylist].enable(@user)

    refute @copilot_user.copilot_code_review_enabled?
  end

  test "user is not allowed to use code review" do
    GitHub.flipper[:copilot_pr_reviews_v1].disable
    GitHub.flipper[:copilot_code_review_public_preview].disable
    GitHub.flipper[:copilot_code_review_public_preview_denylist].disable

    refute @copilot_user.copilot_code_review_enabled?
  end
end if GitHub.copilot_enabled?
