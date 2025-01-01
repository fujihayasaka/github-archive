# typed: true
# frozen_string_literal: true

require "test_helper"

class TechnicalPreviewUserTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  fixtures do
    @user = create(:user)
  end

  test "validates" do
    technical_preview_user = Copilot::TechnicalPreviewUser.new

    refute technical_preview_user.valid?
    refute_nil technical_preview_user.errors[:user]

    technical_preview_user.user = @user
    assert technical_preview_user.valid?
  end
end if GitHub.copilot_enabled?
