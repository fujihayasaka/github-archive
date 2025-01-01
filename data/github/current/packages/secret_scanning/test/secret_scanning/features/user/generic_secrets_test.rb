# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::User
  class UserGenericSecretsTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    setup do
      @user = create(:user)
      @repo = create(:private_repository, owner: @user)
      @token_scanning_repo = SecretScanning::Features::Repo::TokenScanning.new(@repo)
      @generic_secrets_user = SecretScanning::Features::User::GenericSecrets.new(@user)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Features::User::GenericSecrets.new(@user).nil?
      end
    end

    context "feature_available?" do
      test "always returns false" do
        refute @generic_secrets_user.feature_available?
      end
    end

    context "enabled?" do
      test "always returns false" do
        refute @generic_secrets_user.enabled?
      end
    end

    context "enable" do
      test "does nothing" do
        refute @generic_secrets_user.enabled?
        @generic_secrets_user.enable(actor: @user)
        refute @generic_secrets_user.enabled?
      end
    end

    context "disable" do
      test "does nothing" do
        refute @generic_secrets_user.enabled?
        @generic_secrets_user.disable(actor: @user)
        refute @generic_secrets_user.enabled?
      end
    end
  end
end
