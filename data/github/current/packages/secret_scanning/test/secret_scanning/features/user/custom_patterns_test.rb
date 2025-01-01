# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::User
  class UserCustomPatternsTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    fixtures do
      @user = create(:user)
    end

    setup do
      @user_custom_pattern = SecretScanning::Features::User::CustomPatterns.new(@user)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Features::User::CustomPatterns.new(@user).nil?
      end
    end

    context "feature_available?" do
      test "returns false if advanced security is not purchased" do
        refute @user_custom_pattern.feature_available?
      end
    end
  end
end
