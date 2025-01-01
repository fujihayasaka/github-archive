# typed: true
# frozen_string_literal: true

require "test_helper"

class StafftoolsNewsiesSettingsTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user1 = create(:user)
    @user2 = create(:user)

    GitHub.newsies.get_and_update_settings @user1 do |settings|
      settings.participating_settings.replace %w(web email)
      settings.subscribed_settings.clear
    end

    GitHub.newsies.get_and_update_settings @user2 do |settings|
      settings.participating_settings.replace %w(email)
      settings.subscribed_settings.replace %w(web)
    end

    @settings1 = Stafftools::NewsiesSettings.new(@user1)
    @settings2 = Stafftools::NewsiesSettings.new(@user2)
  end

  context "#user" do
    test "returns the user" do
      assert_equal @user1, @settings1.user
    end
  end

  context "#participating" do
    test "returns 'email, web'" do
      assert_equal "email, web", @settings1.participating
    end

    test "returns 'email'" do
      assert_equal "email", @settings2.participating
    end
  end

  context "#subscribed" do
    test "returns 'none'" do
      assert_equal "none", @settings1.subscribed
    end

    test "returns 'web'" do
      assert_equal "web", @settings2.subscribed
    end
  end
end
