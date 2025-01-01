# typed: strict
# frozen_string_literal: true

require "test_helper"

class MemberFeatureRequest::Notification::SettingTest < GitHub::TestCase

  test "#all" do
    setting = MemberFeatureRequest::Notification::Setting.new
    setting.all!

    assert setting.all?
    assert_equal "any", setting.trigger
    assert setting.user_enabled
  end

  test "#ignore" do
    setting = MemberFeatureRequest::Notification::Setting.new
    setting.ignore!

    assert setting.ignore
    assert_equal "any", setting.trigger

    refute setting.user_enabled
  end

  context "#custom" do
    test "sets custom values unless all the features are selected" do
      setting = MemberFeatureRequest::Notification::Setting.new
      setting.custom!(features: ["copilot_for_business"])

      assert setting.custom?
      assert_equal "custom", setting.trigger
      assert_includes setting.features, "copilot_for_business"

      refute setting.user_enabled
    end

    test "ignores if all features are selected" do
      setting = MemberFeatureRequest::Notification::Setting.new
      setting.custom!(features: MemberFeatureRequest::Feature.values.map(&:to_s))

      assert setting.ignore
      assert_equal "any", setting.trigger

      refute setting.user_enabled
    end
  end

end
