# typed: true
# frozen_string_literal: true

require "test_helper"

class GlobalNoticeNext::DisabledOrgReposCheckTest < GitHub::TestCase
  fixtures do
    @user = create(:user, :verified, plan: "small")
  end

  context "#should_show_notice?" do
    test "returns true if user is having billing trouble" do
      org = create :organization, admin: @user, plan: "silver"
      11.times { create :private_repository, owner: org }
      org.update plan: "bronze"
      org.reload
      org.enable_or_disable!

      assert org.disabled?
      assert org.over_plan_limit?
      assert org.paid_plan?

      check = GlobalNoticeNext::DisabledOrgReposCheck.new(viewer: @user)

      assert check.should_show_notice?
    end

    test "returns false if user has no disabled repos" do
      check = GlobalNoticeNext::DisabledOrgReposCheck.new(viewer: @user)

      refute check.should_show_notice?
    end
  end
end
