# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Owner
  class OwnerCustomPatternsTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    fixtures do
      @user = create(:user)
      @org = create(:organization)
    end

    setup do
      @org_custom_pattern = SecretScanning::Features::Owner::CustomPatterns.new(@org)
      @user_custom_pattern = SecretScanning::Features::Owner::CustomPatterns.new(@user)

      @org.stubs(:advanced_security_purchased?).returns(true)
      SecretScanning::Features::Org::TokenScanning.any_instance.stubs(:feature_available?).returns(false)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Features::Owner::CustomPatterns.new(@org).nil?
        refute SecretScanning::Features::Owner::CustomPatterns.new(@user).nil?
      end
    end

    context "feature_available?(org)" do
      test "returns false if advanced security is not purchased" do
        @org.stubs(:advanced_security_purchased?).returns(false)
        refute @org_custom_pattern.feature_available?
      end

      test "returns true if token scanning enabled" do
        SecretScanning::Features::Org::TokenScanning.any_instance.stubs(:feature_available?).returns(true)
        assert @org_custom_pattern.feature_available?
      end

      test "false if token scanning disabled" do
        refute @org_custom_pattern.feature_available?
      end
    end

    context "feature_available?(user)" do
      test "false" do
        refute @user_custom_pattern.feature_available?
      end
    end
  end
end
