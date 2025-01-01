# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dgit"

class InteractionSettingTest < GitHub::TestCase

  fixtures do
    @user = create(:user)
  end

  context "validations" do
    test "requires user" do
      setting = InteractionSetting.new(user: nil)
      refute_predicate setting, :valid?
      assert_equal ["User must exist"], setting.errors.full_messages
    end

    test "cannot belong to organization" do
      setting = InteractionSetting.new(user: create(:organization))
      refute_predicate setting, :valid?
      assert_equal ["User cannot be an organization"], setting.errors.full_messages
    end
  end
end
