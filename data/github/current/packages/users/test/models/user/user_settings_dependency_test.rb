# typed: true
# frozen_string_literal: true

require "test_helper"

class User::SettingsDependencyTest < GitHub::TestCase
  context "validation" do
    test "A user without a settings record is valid" do
      user = create(:user, user_settings_record: nil)
      assert user.valid?
    end
  end

  context "loading and persistence" do
    test "A user without an existing settings record will have one built as needed" do
      user = create(:user, user_settings_record: nil)

      assert user.settings.instance_of?(UserSettings)
      assert_not user.settings.persisted?

      # saving the user will persist the new settings record

      user.save

      assert user.reload.settings.persisted?
    end
  end
end
