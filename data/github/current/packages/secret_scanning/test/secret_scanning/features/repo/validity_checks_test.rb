# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Repo
  class RepoValidityChecksTest < GitHub::TestCase
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
      @validity_checks_repo = SecretScanning::Features::Repo::ValidityChecks.new(@repo)
      @validity_checks_org = SecretScanning::Features::Org::ValidityChecks.new(@org)
      @validity_checks_business = SecretScanning::Features::Business::ValidityChecks.new(@business)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Features::Repo::ValidityChecks.new(@repo).nil?
      end
    end

    context "enterprise", enterprise_only: true do
      test "feature_available? returns false for enterprise" do
        refute @validity_checks_repo.feature_available?
      end
    end

    context "proxima", skip_enterprise: true do
      test "feature_available? returns false" do
        on_multi_tenant_enterprise do
          refute @validity_checks_repo.feature_available?
        end
      end
    end

    context "feature_available?", skip_enterprise: true do
      test "returns false if the owner has not purchased advanced security" do
        @org.stubs(:advanced_security_purchased?).returns(false)

        refute @validity_checks_repo.feature_available?
      end

      test "returns false if token scanning is not enabled" do
        @token_scanning_repo.disable(actor: @user)

        refute @validity_checks_repo.feature_available?
      end

      test "returns true when conditions are met" do
        @token_scanning_repo.enable(actor: @user)

        assert @validity_checks_repo.feature_available?
      end

      test "returns true if sku split is enabled and secret scanning license is available" do
        @token_scanning_repo.enable(actor: @user)
        @org.stubs(:secret_protection_purchased?).returns(true)
        assert @validity_checks_repo.feature_available?
      end
    end

    context "enabled_by_org_or_biz", skip_enterprise: true do
      test "returns true if enabled by org without security config" do
        SecretScanning::Features::Repo::ValidityChecks.any_instance.stubs(:show_security_config_ux?).returns(false)
        SecretScanning::Features::Org::ValidityChecks.any_instance.stubs(:show_security_config_ux?).returns(false)
        @validity_checks_org.enable(actor: @user)
        assert_equal SecretScanning::Features::Repo::ValidityChecks::ENABLED_BY_ORGANIZATION, @validity_checks_repo.enabled_by
        assert @validity_checks_repo.enabled_by_org_or_biz?
      end

      test "returns true if enabled by business without security config" do
        SecretScanning::Features::Repo::ValidityChecks.any_instance.stubs(:show_security_config_ux?).returns(false)
        SecretScanning::Features::Org::ValidityChecks.any_instance.stubs(:show_security_config_ux?).returns(false)
        @validity_checks_business.enable(actor: @user)
        assert_equal SecretScanning::Features::Repo::ValidityChecks::ENABLED_BY_BUSINESS, @validity_checks_repo.enabled_by
        assert @validity_checks_repo.enabled_by_org_or_biz?
      end

      test "returns false with security config" do
        @validity_checks_repo.stubs(:show_security_config_ux?).returns(true)
        @validity_checks_business.enable(actor: @user)
        @validity_checks_org.enable(actor: @user)
        assert_nil @validity_checks_repo.enabled_by
        refute @validity_checks_repo.enabled_by_org_or_biz?
      end
    end

    context "enabled_by", skip_enterprise: true do
      test "returns ENABLED_BY_BUSINESS  if enabled by business" do
        SecretScanning::Features::Repo::ValidityChecks.any_instance.stubs(:show_security_config_ux?).returns(false)
        SecretScanning::Features::Org::ValidityChecks.any_instance.stubs(:show_security_config_ux?).returns(false)
        @token_scanning_repo.enable(actor: @user)

        @validity_checks_repo.enable(actor: @user)
        assert @validity_checks_repo.enabled?

        @validity_checks_org.enable(actor: @user)
        assert @validity_checks_org.enabled?

        @validity_checks_business.enable(actor: @user)
        assert @validity_checks_business.enabled?

        assert @validity_checks_org.enabled?
        assert @validity_checks_business.enabled?
        assert @validity_checks_repo.enabled?
        assert_equal SecretScanning::Features::Repo::ValidityChecks::ENABLED_BY_BUSINESS, @validity_checks_repo.enabled_by
      end

      test "returns ENABLED_BY_ORGANIZATION if enabled by the org" do
        SecretScanning::Features::Repo::ValidityChecks.any_instance.stubs(:show_security_config_ux?).returns(false)
        @token_scanning_repo.enable(actor: @user)

        @validity_checks_repo.enable(actor: @user)
        assert @validity_checks_repo.enabled?

        @validity_checks_org.enable(actor: @user)
        assert @validity_checks_org.enabled?

        @validity_checks_business.disable(actor: @user)
        refute @validity_checks_business.enabled?

        assert @validity_checks_org.enabled?
        refute @validity_checks_business.enabled?
        assert @validity_checks_repo.enabled?
        assert_equal SecretScanning::Features::Repo::ValidityChecks::ENABLED_BY_ORGANIZATION, @validity_checks_repo.enabled_by
      end

      test "returns :self if enabled by the repo and not the org and not the business" do
        SecretScanning::Features::Repo::ValidityChecks.any_instance.stubs(:show_security_config_ux?).returns(false)
        @token_scanning_repo.enable(actor: @user)

        @validity_checks_repo.enable(actor: @user)

        assert @validity_checks_repo.enabled?
        assert_equal SecretScanning::Features::Repo::ValidityChecks::ENABLED_BY_SELF, @validity_checks_repo.enabled_by
      end

      test "returns :disabled if disabled by the repo" do
        SecretScanning::Features::Repo::ValidityChecks.any_instance.stubs(:show_security_config_ux?).returns(false)
        @token_scanning_repo.enable(actor: @user)

        @validity_checks_repo.disable(actor: @user)

        refute @validity_checks_repo.enabled?
        assert_nil @validity_checks_repo.enabled_by
      end

      test "with security config returns nil even with org and business" do
        SecretScanning::Features::Repo::ValidityChecks.any_instance.stubs(:show_security_config_ux?).returns(true)
        @token_scanning_repo.enable(actor: @user)
        @validity_checks_repo.disable(actor: @user)

        @validity_checks_org.enable(actor: @user)
        assert @validity_checks_org.enabled?

        @validity_checks_business.enable(actor: @user)
        assert @validity_checks_business.enabled?

        assert @validity_checks_org.enabled?
        assert @validity_checks_business.enabled?
        refute @validity_checks_repo.enabled?
        assert_nil @validity_checks_repo.enabled_by
      end

      test "with security config returns enabled by self even with org and business" do
        SecretScanning::Features::Repo::ValidityChecks.any_instance.stubs(:show_security_config_ux?).returns(true)
        @token_scanning_repo.enable(actor: @user)
        @validity_checks_repo.enable(actor: @user)

        @validity_checks_org.enable(actor: @user)
        assert @validity_checks_org.enabled?

        @validity_checks_business.enable(actor: @user)
        assert @validity_checks_business.enabled?

        assert @validity_checks_org.enabled?
        assert @validity_checks_business.enabled?
        assert @validity_checks_repo.enabled?
        assert_equal SecretScanning::Features::Repo::ValidityChecks::ENABLED_BY_SELF, @validity_checks_repo.enabled_by
      end

      context "user-owned repos" do
        context "with a non-enterprise-managed business" do
          test "returns nil, even if the business has enabled the feature" do
            user_repo = create(:private_repository, owner: @user, force_user_owned: true)
            user_repo_feature = SecretScanning::Features::Repo::ValidityChecks.new(user_repo)

            refute user_repo_feature.enabled?
            @validity_checks_business.enable(actor: @user)
            assert @validity_checks_business.enabled?
            refute user_repo_feature.enabled?
            assert_nil user_repo_feature.enabled_by
          end
        end

        context "with an enterprise-managed business" do
          test "returns :business if the business has enabled the feature" do
            SecretScanning::Features::Repo::ValidityChecks.any_instance.stubs(:show_security_config_ux?).returns(false)
            emu = create(:emu)
            emu_biz = emu.enterprise_managed_business
            emu_repo = create(:private_repository, owner: emu, force_user_owned: true)

            emu_repo_token_scanning_feature = SecretScanning::Features::Repo::TokenScanning.new(emu_repo)
            emu_repo_token_scanning_feature.enable(actor: emu)
            assert emu_repo_token_scanning_feature.enabled?

            business_feature = SecretScanning::Features::Business::ValidityChecks.new(emu_biz)
            emu_repo_feature = SecretScanning::Features::Repo::ValidityChecks.new(emu_repo)

            refute emu_repo_feature.enabled?
            refute emu_repo_feature.enabled_by == SecretScanning::Features::Repo::ValidityChecks::ENABLED_BY_BUSINESS
            business_feature.enable(actor: emu)
            assert emu_repo_feature.enabled?
            assert emu_repo_feature.enabled_by == SecretScanning::Features::Repo::ValidityChecks::ENABLED_BY_BUSINESS
          end

          test "with security configs returns nil even if the business has enabled the feature" do
            SecretScanning::Features::Repo::ValidityChecks.any_instance.stubs(:show_security_config_ux?).returns(true)
            emu = create(:emu)
            emu_biz = emu.enterprise_managed_business
            emu_repo = create(:private_repository, owner: emu, force_user_owned: true)

            emu_repo_token_scanning_feature = SecretScanning::Features::Repo::TokenScanning.new(emu_repo)
            emu_repo_token_scanning_feature.enable(actor: emu)
            assert emu_repo_token_scanning_feature.enabled?

            business_feature = SecretScanning::Features::Business::ValidityChecks.new(emu_biz)
            emu_repo_feature = SecretScanning::Features::Repo::ValidityChecks.new(emu_repo)

            refute emu_repo_feature.enabled?
            refute emu_repo_feature.enabled_by == SecretScanning::Features::Repo::ValidityChecks::ENABLED_BY_BUSINESS
            business_feature.enable(actor: emu)
            refute emu_repo_feature.enabled?
            assert_nil emu_repo_feature.enabled_by
          end
        end
      end
    end

    context "enabled", skip_enterprise: true do
      test "returns true if enabled" do
        @token_scanning_repo.enable(actor: @user)

        @validity_checks_repo.enable(actor: @user)

        assert @validity_checks_repo.enabled?
      end

      test "returns false if not enabled" do
        @token_scanning_repo.enable(actor: @user)

        @validity_checks_repo.disable(actor: @user)

        refute @validity_checks_repo.enabled?
      end

      test "returns true if enabled by org or enterprise" do
        @token_scanning_repo.enable(actor: @user)

        @validity_checks_repo.stubs(:show_security_config_ux?).returns(false)
        @validity_checks_repo.stubs(:enabled_by_org_or_biz?).returns(true)

        assert @validity_checks_repo.enabled?
      end
    end

    context "display_token_groups_validity_enabled?" do
      test "returns true when enabled" do
        disable_feature_flag(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::TOKEN_GROUPS_VALIDITY)
        refute @validity_checks_repo.display_token_groups_validity_enabled?
      end

      test "returns false when disabled" do
        enable_feature_flag(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::TOKEN_GROUPS_VALIDITY)
        assert @validity_checks_repo.display_token_groups_validity_enabled?
      end
    end

    context "show_security_config_ux" do
      test "returns true" do
        assert @validity_checks_repo.show_security_config_ux?
      end
    end

    context "on_demand_checks_enabled_for_async_token_types?" do
      test "true if FF enabled" do
        enable_feature_flag(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::ON_DEMAND_CHECKS_ENABLED_FOR_ASYNC_TOKEN_TYPES)

        assert @validity_checks_repo.on_demand_checks_enabled_for_async_token_types?
      end

      test "false if FF disabled" do
        disable_feature_flag(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::ON_DEMAND_CHECKS_ENABLED_FOR_ASYNC_TOKEN_TYPES)

        refute @validity_checks_repo.on_demand_checks_enabled_for_async_token_types?
      end
    end
  end
end
