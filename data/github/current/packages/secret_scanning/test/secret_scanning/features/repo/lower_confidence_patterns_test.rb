# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Repo
  class RepoLowerConfidencePatternsTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    setup do
      Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
      Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
      Repository.any_instance.stubs(:advanced_security_enabled?).returns(true)
      GitHub.stubs(:configuration_secret_scanning_enabled?).returns(true)

      GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?
      @user = create(:user)
      @business = create(:global_business)
      @org = create(:business_plus_org, business: @business)
      @repo = create(:private_repository, owner: @org)

      @token_scanning_repo = SecretScanning::Features::Repo::TokenScanning.new(@repo)
      @lower_confidence_patterns_repo = SecretScanning::Features::Repo::LowerConfidencePatterns.new(@repo)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Features::Repo::LowerConfidencePatterns.new(@repo).nil?
      end
    end

    context "feature_available?" do
      test "returns false if the owner has not purchased advanced security" do
        @org.stubs(:advanced_security_purchased?).returns(false)
        refute @lower_confidence_patterns_repo.feature_available?
      end

      test "returns false if token scanning is not enabled" do
        @token_scanning_repo.disable(actor: @user)
        refute @lower_confidence_patterns_repo.feature_available?
      end

      test "returns true if owner has purchased GHAS and token scanning is enabled" do
        @token_scanning_repo.enable(actor: @user)
        assert @lower_confidence_patterns_repo.feature_available?
      end

      test "returns false for free public repos without GHAS purchased" do
        fpr = create(:public_repository, owner: @user)
        GitHub.flipper[FeatureFlags::READ_PUBLIC_REPO_ALERTS].enable(fpr)
        SecretScanning::Features::Repo::TokenScanning.new(fpr).enable(actor: @user)

        assert SecretScanning::Features::Repo::TokenScanning.new(fpr).feature_available?
        fpr.stubs(:advanced_security_enabled?).returns(false)
        refute SecretScanning::Features::Repo::LowerConfidencePatterns.new(fpr).feature_available?
      end

      test "returns true for org-owned public repos with GHAS purchased" do
        pr = create(:public_repository, owner: @org)
        SecretScanning::Features::Repo::TokenScanning.new(pr).enable(actor: @user)

        assert SecretScanning::Features::Repo::TokenScanning.new(pr).feature_available?
        assert SecretScanning::Features::Repo::LowerConfidencePatterns.new(pr).feature_available?
      end

      test "returns true for org-owned archived repos with GHAS purchased" do
        ar = create(:archived_repository, owner: @org)
        SecretScanning::Features::Repo::TokenScanning.new(ar).enable(actor: @user)

        assert SecretScanning::Features::Repo::TokenScanning.new(ar).feature_available?
        assert SecretScanning::Features::Repo::LowerConfidencePatterns.new(ar).feature_available?
      end

      test "returns false for user-owned archived repos without GHAS purchased", skip_enterprise: true do
        ar = create(:archived_repository, owner: @user)
        GitHub.flipper[FeatureFlags::READ_PUBLIC_REPO_ALERTS].enable(ar)
        SecretScanning::Features::Repo::TokenScanning.new(ar).enable(actor: @user)

        assert SecretScanning::Features::Repo::TokenScanning.new(ar).feature_available?
        ar.stubs(:advanced_security_enabled?).returns(false)
        refute SecretScanning::Features::Repo::LowerConfidencePatterns.new(ar).feature_available?
      end
    end

    context "dark_ship_enabled?", skip_enterprise: true do
      test "returns false if the feature flag is disabled" do
        GitHub.flipper[FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP].disable
        refute @lower_confidence_patterns_repo.dark_ship_enabled?
      end

      test "returns false if token scanning is disabled" do
        GitHub.flipper[FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP].enable
        refute @token_scanning_repo.enabled?
        refute @lower_confidence_patterns_repo.dark_ship_enabled?
      end

      test "returns true if the feature flag is enabled for the repo" do
        GitHub.flipper[FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP].enable(@repo)
        @token_scanning_repo.enable(actor: @user)
        assert @lower_confidence_patterns_repo.dark_ship_enabled?
      end

      test "returns true if the feature flag is enabled for the org" do
        GitHub.flipper[FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP].enable(@org)
        @token_scanning_repo.enable(actor: @user)
        assert @lower_confidence_patterns_repo.dark_ship_enabled?
      end

      test "returns true if the feature flag is enabled for the enterprise" do
        GitHub.flipper[FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP].enable(@business)
        @token_scanning_repo.enable(actor: @user)
        assert @lower_confidence_patterns_repo.dark_ship_enabled?
      end
    end

    context "enabled?" do
      test "returns false if not enabled by the repo" do
        @token_scanning_repo.enable(actor: @user)
        @repo.config.disable(SecretScanning::Features::Repo::LowerConfidencePatterns::CONFIG_KEY_USER_ENABLED, @user)
        refute @lower_confidence_patterns_repo.enabled?
      end

      test "returns true if enabled by the repo" do
        @token_scanning_repo.enable(actor: @user)
        @repo.config.enable(SecretScanning::Features::Repo::LowerConfidencePatterns::CONFIG_KEY_USER_ENABLED, @user)
        assert @lower_confidence_patterns_repo.enabled?
      end

      test "returns true if enabled by the org" do
        @token_scanning_repo.enable(actor: @user)
        @org.config.enable(SecretScanning::Features::Org::LowerConfidencePatterns::CONFIG_KEY_USER_ENABLED, @user)
        unless @lower_confidence_patterns_repo.show_security_config_ux?
          assert @lower_confidence_patterns_repo.enabled?
        end
      end

      test "returns true if enabled by the enterprise" do
        @token_scanning_repo.enable(actor: @user)
        @business.config.enable(SecretScanning::Features::Business::LowerConfidencePatterns::CONFIG_KEY_USER_ENABLED, @user)
        unless @lower_confidence_patterns_repo.show_security_config_ux?
          assert @lower_confidence_patterns_repo.enabled?
        end
      end

      context "user-owned repos" do
        context "with a non-enterprise-managed business", skip_enterprise: true do
          test "returns false, even if the business has enabled the feature" do
            user_repo = create(:private_repository, owner: @user, force_user_owned: true)
            user_repo_feature = SecretScanning::Features::Repo::LowerConfidencePatterns.new(user_repo)
            business_feature = SecretScanning::Features::Business::LowerConfidencePatterns.new(@business)

            @token_scanning_repo.enable(actor: @user)
            assert @token_scanning_repo.enabled?

            refute user_repo_feature.enabled?
            business_feature.enable(actor: @user)
            assert business_feature.enabled?
            refute user_repo_feature.enabled?
            refute user_repo_feature.enabled_by_enterprise?
          end
        end

        context "with an enterprise-managed business", skip_enterprise: true do
          test "returns :business if the business has enabled the feature" do
            emu = create(:emu)
            emu_biz = emu.enterprise_managed_business
            emu_repo = create(:private_repository, owner: emu, force_user_owned: true)

            emu_repo_token_scanning_feature = SecretScanning::Features::Repo::TokenScanning.new(emu_repo)
            emu_repo_token_scanning_feature.enable(actor: emu)
            assert emu_repo_token_scanning_feature.enabled?

            business_feature = SecretScanning::Features::Business::LowerConfidencePatterns.new(emu_biz)
            emu_repo_feature = SecretScanning::Features::Repo::LowerConfidencePatterns.new(emu_repo)

            refute emu_repo_feature.enabled?
            refute emu_repo_feature.enabled_by_enterprise?
            business_feature.enable(actor: emu)
            unless emu_repo_feature.show_security_config_ux?
              assert emu_repo_feature.enabled?
            end
            assert emu_repo_feature.enabled_by_enterprise?
          end
        end
      end
    end
  end
end
