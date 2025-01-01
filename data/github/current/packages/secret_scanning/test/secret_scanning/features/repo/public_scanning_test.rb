# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Repo
  class RepoPublicScanningTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    fixtures do
      business = create(:business)
      @org = create(:business_plus_org, business: business)
      @user = create(:user)
    end

    setup do
      @repo = create(:public_repository, owner: @org)
      @public_scanning = SecretScanning::Features::Repo::PublicScanning.new(@repo)
      @token_scanning = SecretScanning::Features::Repo::TokenScanning.new(@repo)
      GitHub.stubs(:configuration_secret_scanning_enabled?).returns(true)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Features::Repo::PublicScanning.new(@repo).nil?
      end

    end

    context "feature_available?" do
      test "returns true if all conditions are met", skip_enterprise: true do
        assert @public_scanning.feature_available?
      end

      test "false on GHES", enterprise_only: true do
        refute @public_scanning.feature_available?
      end

      test "false if global config disabled" do
        GitHub.stubs(:configuration_secret_scanning_enabled?).returns(false)

        refute @public_scanning.feature_available?
      end

      test "false if staff locked" do
        @token_scanning.staff_disable(actor: @user)

        refute @public_scanning.feature_available?
      end
    end

    context "stafftools_available?" do
      test "returns true if all conditions are met", skip_enterprise: true do
        assert @public_scanning.stafftools_available?
      end

      test "false on GHES", enterprise_only: true do
        refute @public_scanning.stafftools_available?
      end

      test "false if global config disabled" do
        GitHub.stubs(:configuration_secret_scanning_enabled?).returns(false)

        refute @public_scanning.stafftools_available?
      end

      test "true if staff locked", skip_enterprise: true do
        @token_scanning.staff_disable(actor: @user)

        assert @public_scanning.stafftools_available?
      end
    end

    context "enabled?" do
      test "true for public repos", skip_enterprise: true do
        @repo.set_visibility(actor: @user, visibility: "public")
        assert @public_scanning.enabled?
      end

      test "false for public repos on GHES", enterprise_only: true do
        @repo.set_visibility(actor: @user, visibility: "public")
        refute @public_scanning.enabled?
      end

      test "false for private repos" do
        @repo.set_visibility(actor: @user, visibility: "private")
        refute @public_scanning.enabled?
      end

      test "false for internal repos" do
        @repo.set_visibility(actor: @user, visibility: "internal")
        refute @public_scanning.enabled?
      end

      test "false if feature unavailable" do
        GitHub.stubs(:configuration_secret_scanning_enabled?).returns(false)
        @repo.set_visibility(actor: @user, visibility: "public")
        refute @public_scanning.enabled?
      end

      test "false if staff locked" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:staff_locked?).returns(true)
        @repo.set_visibility(actor: @user, visibility: "public")
        refute @public_scanning.enabled?
      end
    end
  end
end
