# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::Access::CopilotWorkspaceBillingCheckerTest < GitHub::TestCase

  fixtures do
    @user = create(:user)
    @user.disable_feature(:codespaces_cwtp_no_limits)
  end

  test "returns allowed if monthly usage is less than allowed usage" do
    create(:codespace_usage_record, :for_copilot_workspace, owner: @user, usage_seconds: Codespaces::Dials::CopilotWorkspaceUsageLimitSeconds.new(force_cache_miss: true).value - 1)
    result = Codespaces::Access::CopilotWorkspaceBillingChecker.new(@user).perform
    assert result.allowed?
  end

  test "returns disallowed if monthly usage is greater than or equal to allowed usage" do
    create(:codespace_usage_record, :for_copilot_workspace, owner: @user, usage_seconds: Codespaces::Dials::CopilotWorkspaceUsageLimitSeconds.new(force_cache_miss: true).value)
    result = Codespaces::Access::CopilotWorkspaceBillingChecker.new(@user).perform
    refute result.allowed?
  end

  test "properly sums up multiple usage records when checking usage" do
    set_monthly_usage_limit(20)
    create_list(:codespace_usage_record, 4, :for_copilot_workspace, owner: @user, usage_seconds: 5)
    result = Codespaces::Access::CopilotWorkspaceBillingChecker.new(@user).perform
    refute result.allowed?
  end

  test "returns allowed if monthly usage is for normal codespaces" do
    create(:codespace_usage_record, owner: @user, usage_seconds: Codespaces::Dials::CopilotWorkspaceUsageLimitSeconds.new(force_cache_miss: true).value)
    result = Codespaces::Access::CopilotWorkspaceBillingChecker.new(@user).perform
    assert result.allowed?
  end

  test "returns allowed if user is in cwtp limit opt-out flag" do
    @user.enable_feature(:codespaces_cwtp_no_limits)
    create(:codespace_usage_record, :for_copilot_workspace, owner: @user, usage_seconds: Codespaces::Dials::CopilotWorkspaceUsageLimitSeconds.new(force_cache_miss: true).value)
    result = Codespaces::Access::CopilotWorkspaceBillingChecker.new(@user).perform
    assert result.allowed?
  end

  def set_monthly_usage_limit(value)
    dial = Codespaces::Dials::CopilotWorkspaceUsageLimitSeconds.new(force_cache_miss: true)
    dial.value = value
    dial.save
  end
end
