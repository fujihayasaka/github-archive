# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning
  class SecretScanningBulkEnablementServiceTest < GitHub::TestCase
    include SecurityProductsEnablement::EnterpriseTestHelpers
    fixtures do
      enable_feature_flag(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::GHAS_VOLUME_UNBUNDLED_TRIALS_AUTO_ENABLE)

      @org = create(:organization)
      @user = create(:user)
      @business = create(:business, owners: [@user], organizations: [@org])
      @business.mark_advanced_security_as_purchased_for_entity_as_volume_unbundled(actor: @user)

      @bundled_ghas_enabled_org_model_hash = {
        "name" => "config name",
        "description" => "config description",
        "enable_ghas" => true,
        "private_vulnerability_reporting" => "disabled",
        "dependency_graph" => "enabled",
        "dependency_graph_autosubmit_action" => "disabled",
        "dependency_graph_autosubmit_action_options" => {},
        "dependabot_alerts" => "enabled",
        "dependabot_security_updates" => "not_set",
        "code_scanning" => "enabled",
        "code_scanning_delegated_alert_dismissal" => "not_set",
        "secret_scanning" => "disabled",
        "secret_scanning_push_protection" => "disabled",
        "secret_scanning_delegated_bypass" => "disabled",
        "secret_scanning_delegated_alert_dismissal" => "disabled",
        "secret_scanning_validity_checks" => "disabled",
        "secret_scanning_non_provider_patterns" => "disabled",
        "secret_scanning_generic_secrets" => "disabled",
        "target" => @org
      }.freeze

      @bundled_ghas_enabled_business_model_hash = {
        "name" => "config name",
        "description" => "config description",
        "enable_ghas" => true,
        "private_vulnerability_reporting" => "disabled",
        "dependency_graph" => "enabled",
        "dependency_graph_autosubmit_action" => "disabled",
        "dependency_graph_autosubmit_action_options" => {},
        "dependabot_alerts" => "enabled",
        "dependabot_security_updates" => "not_set",
        "code_scanning" => "enabled",
        "code_scanning_delegated_alert_dismissal" => "not_set",
        "secret_scanning" => "disabled",
        "secret_scanning_push_protection" => "disabled",
        "secret_scanning_delegated_bypass" => "disabled",
        "secret_scanning_delegated_alert_dismissal" => "disabled",
        "secret_scanning_validity_checks" => "disabled",
        "secret_scanning_non_provider_patterns" => "disabled",
        "secret_scanning_generic_secrets" => "disabled",
        "target" => @business
      }.freeze


      @bundled_ghas_disabled_org_model_hash = {
        "name" => "config name",
        "description" => "config description",
        "enable_ghas" => false,
        "private_vulnerability_reporting" => "disabled",
        "dependency_graph" => "disabled",
        "dependency_graph_autosubmit_action" => "disabled",
        "dependency_graph_autosubmit_action_options" => {},
        "dependabot_alerts" => "disabled",
        "dependabot_security_updates" => "disabled",
        "code_scanning" => "disabled",
        "code_scanning_delegated_alert_dismissal" => "disabled",
        "secret_scanning" => "disabled",
        "secret_scanning_push_protection" => "disabled",
        "secret_scanning_delegated_bypass" => "disabled",
        "secret_scanning_delegated_alert_dismissal" => "disabled",
        "secret_scanning_validity_checks" => "disabled",
        "secret_scanning_non_provider_patterns" => "disabled",
        "secret_scanning_generic_secrets" => "disabled",
        "target" => @org
      }.freeze

      @bundled_ghas_disabled_business_model_hash = {
        "name" => "config name",
        "description" => "config description",
        "enable_ghas" => false,
        "private_vulnerability_reporting" => "disabled",
        "dependency_graph" => "disabled",
        "dependency_graph_autosubmit_action" => "disabled",
        "dependency_graph_autosubmit_action_options" => {},
        "dependabot_alerts" => "disabled",
        "dependabot_security_updates" => "disabled",
        "code_scanning" => "disabled",
        "code_scanning_delegated_alert_dismissal" => "disabled",
        "secret_scanning" => "disabled",
        "secret_scanning_push_protection" => "disabled",
        "secret_scanning_delegated_bypass" => "disabled",
        "secret_scanning_delegated_alert_dismissal" => "disabled",
        "secret_scanning_validity_checks" => "disabled",
        "secret_scanning_non_provider_patterns" => "disabled",
        "secret_scanning_generic_secrets" => "disabled",
        "target" => @business
      }.freeze


      ####

      @unbundled_ghas_enabled_org_model_hash = {
        "name" => "config name",
        "description" => "config description",
        "enable_ghas" => false,
        "secret_protection_sku_enabled" => true,
        "code_security_sku_enabled" => true,
        "private_vulnerability_reporting" => "disabled",
        "dependency_graph" => "enabled",
        "dependency_graph_autosubmit_action" => "disabled",
        "dependency_graph_autosubmit_action_options" => {},
        "dependabot_alerts" => "enabled",
        "dependabot_security_updates" => "not_set",
        "code_scanning" => "enabled",
        "code_scanning_delegated_alert_dismissal" => "not_set",
        "secret_scanning" => "disabled",
        "secret_scanning_push_protection" => "disabled",
        "secret_scanning_delegated_bypass" => "disabled",
        "secret_scanning_delegated_alert_dismissal" => "disabled",
        "secret_scanning_validity_checks" => "disabled",
        "secret_scanning_non_provider_patterns" => "disabled",
        "secret_scanning_generic_secrets" => "disabled",
        "target" => @org
      }.freeze

      @unbundled_ghas_enabled_business_model_hash = {
        "name" => "config name",
        "description" => "config description",
        "enable_ghas" => false,
        "secret_protection_sku_enabled" => true,
        "code_security_sku_enabled" => true,
        "private_vulnerability_reporting" => "disabled",
        "dependency_graph" => "enabled",
        "dependency_graph_autosubmit_action" => "disabled",
        "dependency_graph_autosubmit_action_options" => {},
        "dependabot_alerts" => "enabled",
        "dependabot_security_updates" => "not_set",
        "code_scanning" => "enabled",
        "code_scanning_delegated_alert_dismissal" => "not_set",
        "secret_scanning" => "disabled",
        "secret_scanning_push_protection" => "disabled",
        "secret_scanning_delegated_bypass" => "disabled",
        "secret_scanning_delegated_alert_dismissal" => "disabled",
        "secret_scanning_validity_checks" => "disabled",
        "secret_scanning_non_provider_patterns" => "disabled",
        "secret_scanning_generic_secrets" => "disabled",
        "target" => @business
      }.freeze


      @unbundled_ghas_disabled_org_model_hash = {
        "name" => "config name",
        "description" => "config description",
        "enable_ghas" => false,
        "secret_protection_sku_enabled" => true,
        "code_security_sku_enabled" => true,
        "private_vulnerability_reporting" => "disabled",
        "dependency_graph" => "disabled",
        "dependency_graph_autosubmit_action" => "disabled",
        "dependency_graph_autosubmit_action_options" => {},
        "dependabot_alerts" => "disabled",
        "dependabot_security_updates" => "disabled",
        "code_scanning" => "disabled",
        "code_scanning_delegated_alert_dismissal" => "disabled",
        "secret_scanning" => "disabled",
        "secret_scanning_push_protection" => "disabled",
        "secret_scanning_delegated_bypass" => "disabled",
        "secret_scanning_delegated_alert_dismissal" => "disabled",
        "secret_scanning_validity_checks" => "disabled",
        "secret_scanning_non_provider_patterns" => "disabled",
        "secret_scanning_generic_secrets" => "disabled",
        "target" => @org
      }.freeze

      @unbundled_ghas_disabled_business_model_hash = {
        "name" => "config name",
        "description" => "config description",
        "enable_ghas" => false,
        "secret_protection_sku_enabled" => true,
        "code_security_sku_enabled" => true,
        "private_vulnerability_reporting" => "disabled",
        "dependency_graph" => "disabled",
        "dependency_graph_autosubmit_action" => "disabled",
        "dependency_graph_autosubmit_action_options" => {},
        "dependabot_alerts" => "disabled",
        "dependabot_security_updates" => "disabled",
        "code_scanning" => "disabled",
        "code_scanning_delegated_alert_dismissal" => "disabled",
        "secret_scanning" => "disabled",
        "secret_scanning_push_protection" => "disabled",
        "secret_scanning_delegated_bypass" => "disabled",
        "secret_scanning_delegated_alert_dismissal" => "disabled",
        "secret_scanning_validity_checks" => "disabled",
        "secret_scanning_non_provider_patterns" => "disabled",
        "secret_scanning_generic_secrets" => "disabled",
        "target" => @business
      }.freeze
    end

    context "enable_all_secret_scanning for bundled, ghas enabled", skip_enterprise: true do
      test "enables secret scanning and push protection on existing org config" do
        config = SecurityConfiguration.create_configuration(
          model_hash: @bundled_ghas_enabled_org_model_hash,
          default_for_new_public_repos: false,
          default_for_new_private_repos: false,
          enforcement: :not_enforced,
          actor: @user
        )
        assert config.persisted?
        assert_equal @org, config.target
        assert_equal "disabled", config.secret_scanning
        config_id = config.id

        assert_enqueued_with(
          job: SecurityProductsEnablement::OrganizationSecurityConfigurationJob,
          args: [{
            actor_id: @user.id,
            organization_id: @org.id,
            security_configuration_id: config_id,
            action: :update,
            repository_ids: nil,
            options: { publish_backfill_group_request: true }
          }]
        ) do
          BulkEnablementService.enable_all_secret_scanning(@business, @user)
        end

        # Config should now be unbundled
        updated_config = UnbundledSecurityConfiguration.find(config_id)
        assert_equal "enabled", updated_config.secret_scanning
        assert_equal "enabled", updated_config.secret_scanning_push_protection
        assert updated_config.secret_protection_sku_enabled
      end

      test "enables secret scanning and push protection on existing business config" do
        config = SecurityConfiguration.create_configuration(
          model_hash: @bundled_ghas_enabled_business_model_hash,
          default_for_new_public_repos: false,
          default_for_new_private_repos: false,
          enforcement: :not_enforced,
          actor: @user
        )
        assert config.persisted?
        assert_equal @business, config.target
        assert_equal "disabled", config.secret_scanning
        config_id = config.id

        assert_enqueued_with(
          job: SecurityProductsEnablement::EnterpriseSecurityConfigurationJob,
          args: [{
            actor_id: @user.id,
            enterprise_id: @business.id,
            security_configuration_id: config_id,
            action: :update,
            options: { publish_backfill_group_request: true }
          }]
        ) do
          BulkEnablementService.enable_all_secret_scanning(@business, @user)
        end

        # Config should now be unbundled
        updated_config = UnbundledSecurityConfiguration.find(config_id)
        assert_equal "enabled", updated_config.secret_scanning
        assert_equal "enabled", updated_config.secret_scanning_push_protection
        assert updated_config.secret_protection_sku_enabled
      end

      test "does not enable when feature flag disabled" do
        disable_feature_flag(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::GHAS_VOLUME_UNBUNDLED_TRIALS_AUTO_ENABLE)
        config = SecurityConfiguration.create_configuration(
          model_hash: @bundled_ghas_enabled_business_model_hash,
          default_for_new_public_repos: false,
          default_for_new_private_repos: false,
          enforcement: :not_enforced,
          actor: @user
        )

        assert config.persisted?
        assert_equal @business, config.target
        assert_equal "disabled", config.reload.secret_scanning

        BulkEnablementService.enable_all_secret_scanning(@business, @user)
        refute_equal "enabled", config.reload.secret_scanning
        refute_equal "enabled", config.reload.secret_scanning_push_protection
      end

      test "creates new config" do
        config = SecurityConfiguration.find_by(target: @business)
        assert_nil config

        BulkEnablementService.enable_all_secret_scanning(@business, @user)
        config = UnbundledSecurityConfiguration.find_by(target: @business)
        refute_nil config
        assert_equal @business, T.must(config).target
        assert_equal "enabled", T.must(config).reload.secret_scanning
        assert_equal "enabled", T.must(config).reload.secret_scanning_push_protection
      end

      test "new config is default for public repos if one does not exist" do
        config = SecurityConfiguration.find_by(target: @business)
        assert_nil config

        BulkEnablementService.enable_all_secret_scanning(@business, @user)
        config = UnbundledSecurityConfiguration.find_by(target: @business)
        refute_nil config
        assert_equal @business, T.must(config).target
        assert_equal "enabled", T.must(config).reload.secret_scanning
        assert_equal "enabled", T.must(config).reload.secret_scanning_push_protection

        assert_equal 1, SecurityConfigurationDefault.find_for(target: @business, visibility: :public).count
        assert_equal config&.id, SecurityConfigurationDefault.find_for(target: @business, visibility: :public).first&.security_configuration_id
      end

      test "new config is default for private repos if one does not exist" do
        config = SecurityConfiguration.find_by(target: @business)
        assert_nil config

        BulkEnablementService.enable_all_secret_scanning(@business, @user)
        config = UnbundledSecurityConfiguration.find_by(target: @business)
        refute_nil config
        assert_equal @business, T.must(config).target
        assert_equal "enabled", T.must(config).reload.secret_scanning
        assert_equal "enabled", T.must(config).reload.secret_scanning_push_protection

        assert_equal 1, SecurityConfigurationDefault.find_for(target: @business, visibility: :private).count
        assert_equal config&.id, SecurityConfigurationDefault.find_for(target: @business, visibility: :private).first&.security_configuration_id
      end

      test "new config is not default if one already exists" do
        config = SecurityConfiguration.create_configuration(
          model_hash: @bundled_ghas_enabled_business_model_hash,
          default_for_new_private_repos: true,
          default_for_new_public_repos: true,
          enforcement: :not_enforced,
          actor: @user
        )
        assert config.persisted?
        assert SecurityConfigurationDefault.find_for(target: @business, visibility: :all).any?
        assert SecurityConfigurationDefault.find_for(target: @business, visibility: :public).any?
        assert SecurityConfigurationDefault.find_for(target: @business, visibility: :private).any?

        BulkEnablementService.enable_all_secret_scanning(@business, @user)

        # find the most recent business config, this is the new one
        new_config = SecurityConfiguration.where(target: @business).order(created_at: :desc).first

        refute_equal config, new_config
        assert_equal @business, T.must(new_config).target
        assert_equal 1, SecurityConfigurationDefault.find_for(target: @business, visibility: :all).count
        assert_equal config.id, SecurityConfigurationDefault.find_for(target: @business, visibility: :all).first&.security_configuration_id
        refute_equal new_config&.id, SecurityConfigurationDefault.find_for(target: @business, visibility: :all).first&.security_configuration_id
        assert_equal "enabled", T.must(config).reload.secret_scanning # validate secret scanning is enabled while we're here
      end

      test "new config is not default for public if one already exists" do
        config = SecurityConfiguration.create_configuration(
          model_hash: @bundled_ghas_enabled_business_model_hash,
          default_for_new_public_repos: true,
          default_for_new_private_repos: false,
          enforcement: :not_enforced,
          actor: @user
        )
        assert config.persisted?
        assert SecurityConfigurationDefault.find_for(target: @business, visibility: :all).any?
        assert SecurityConfigurationDefault.find_for(target: @business, visibility: :public).any?

        BulkEnablementService.enable_all_secret_scanning(@business, @user)

        # find the most recent business config, this is the new one
        new_config = UnbundledSecurityConfiguration.where(target: @business).order(created_at: :desc).first

        refute_equal config, new_config
        assert_equal @business, T.must(new_config).target
        assert_equal 1, SecurityConfigurationDefault.find_for(target: @business, visibility: :public).count
        assert_equal config.id, SecurityConfigurationDefault.find_for(target: @business, visibility: :public).first&.security_configuration_id
        assert_equal new_config&.id, SecurityConfigurationDefault.find_for(target: @business, visibility: :private).first&.security_configuration_id
      end

      test "new config is not default for private if one already exists" do
        config = SecurityConfiguration.create_configuration(
          model_hash: @bundled_ghas_enabled_business_model_hash,
          default_for_new_public_repos: false,
          default_for_new_private_repos: true,
          enforcement: :not_enforced,
          actor: @user
        )
        assert config.persisted?
        assert SecurityConfigurationDefault.find_for(target: @business, visibility: :all).any?
        assert SecurityConfigurationDefault.find_for(target: @business, visibility: :private).any?

        BulkEnablementService.enable_all_secret_scanning(@business, @user)

        # find the most recent business config, this is the new one
        new_config = UnbundledSecurityConfiguration.where(target: @business).order(created_at: :desc).first

        refute_equal config, new_config
        assert_equal @business, T.must(new_config).target
        assert_equal 1, SecurityConfigurationDefault.find_for(target: @business, visibility: :private).count
        assert_equal config.id, SecurityConfigurationDefault.find_for(target: @business, visibility: :private).first&.security_configuration_id
        assert_equal new_config&.id, SecurityConfigurationDefault.find_for(target: @business, visibility: :public).first&.security_configuration_id
      end
    end

    context "enable_all_secret_scanning for bundled, ghas disabled", skip_enterprise: true do
      test "enables secret scanning and push protection on existing org config" do
        config = SecurityConfiguration.create_configuration(
          model_hash: @bundled_ghas_disabled_org_model_hash,
          default_for_new_public_repos: false,
          default_for_new_private_repos: false,
          enforcement: :not_enforced,
          actor: @user
        )
        assert config.persisted?
        assert_equal @org, config.target
        assert_equal "disabled", config.secret_scanning
        config_id = config.id

        assert_enqueued_with(
          job: SecurityProductsEnablement::OrganizationSecurityConfigurationJob,
          args: [{
            actor_id: @user.id,
            organization_id: @org.id,
            security_configuration_id: config_id,
            action: :update,
            repository_ids: nil,
            options: { publish_backfill_group_request: true }
          }]
        ) do
          BulkEnablementService.enable_all_secret_scanning(@business, @user)
        end

        # Config should now be unbundled
        updated_config = UnbundledSecurityConfiguration.find(config_id)
        assert_equal "enabled", updated_config.secret_scanning
        assert_equal "enabled", updated_config.secret_scanning_push_protection
        assert updated_config.secret_protection_sku_enabled
      end

      test "enables secret scanning and push protection on existing business config" do
        config = SecurityConfiguration.create_configuration(
          model_hash: @bundled_ghas_disabled_business_model_hash,
          default_for_new_public_repos: false,
          default_for_new_private_repos: false,
          enforcement: :not_enforced,
          actor: @user
        )
        assert config.persisted?
        assert_equal @business, config.target
        assert_equal "disabled", config.secret_scanning
        config_id = config.id

        assert_enqueued_with(
          job: SecurityProductsEnablement::EnterpriseSecurityConfigurationJob,
          args: [{
            actor_id: @user.id,
            enterprise_id: @business.id,
            security_configuration_id: config_id,
            action: :update,
            options: { publish_backfill_group_request: true }
          }]
        ) do
          BulkEnablementService.enable_all_secret_scanning(@business, @user)
        end

        # Config should now be unbundled
        updated_config = UnbundledSecurityConfiguration.find(config_id)
        assert_equal "enabled", updated_config.secret_scanning
        assert_equal "enabled", updated_config.secret_scanning_push_protection
        assert updated_config.secret_protection_sku_enabled
      end

      test "does not enable when feature flag disabled" do
        disable_feature_flag(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::GHAS_VOLUME_UNBUNDLED_TRIALS_AUTO_ENABLE)
        config = SecurityConfiguration.create_configuration(
          model_hash: @bundled_ghas_disabled_business_model_hash,
          default_for_new_public_repos: false,
          default_for_new_private_repos: false,
          enforcement: :not_enforced,
          actor: @user
        )

        assert config.persisted?
        assert_equal @business, config.target
        assert_equal "disabled", config.reload.secret_scanning

        BulkEnablementService.enable_all_secret_scanning(@business, @user)
        refute_equal "enabled", config.reload.secret_scanning
        refute_equal "enabled", config.reload.secret_scanning_push_protection
      end

      test "creates new config" do
        config = SecurityConfiguration.find_by(target: @business)
        assert_nil config
        config = UnbundledSecurityConfiguration.find_by(target: @business)
        assert_nil config

        BulkEnablementService.enable_all_secret_scanning(@business, @user)

        config = UnbundledSecurityConfiguration.find_by(target: @business)
        refute_nil config
        assert_equal @business, T.must(config).target
        assert_equal "enabled", T.must(config).reload.secret_scanning
        assert_equal "enabled", T.must(config).reload.secret_scanning_push_protection
      end

      test "new config is default for public repos if one does not exist" do
        config = SecurityConfiguration.find_by(target: @business)
        assert_nil config

        BulkEnablementService.enable_all_secret_scanning(@business, @user)

        config = UnbundledSecurityConfiguration.find_by(target: @business)
        refute_nil config
        assert_equal @business, T.must(config).target
        assert_equal "enabled", T.must(config).reload.secret_scanning
        assert_equal "enabled", T.must(config).reload.secret_scanning_push_protection
      end

      test "new config is default for private repos if one does not exist" do
        config = SecurityConfiguration.find_by(target: @business)
        assert_nil config

        BulkEnablementService.enable_all_secret_scanning(@business, @user)

        config = UnbundledSecurityConfiguration.find_by(target: @business)
        refute_nil config
        assert_equal @business, T.must(config).target
        assert_equal "enabled", T.must(config).reload.secret_scanning
        assert_equal "enabled", T.must(config).reload.secret_scanning_push_protection
      end

      test "new config is not default if one already exists" do
        config = SecurityConfiguration.create_configuration(
          model_hash: @bundled_ghas_disabled_business_model_hash,
          default_for_new_public_repos: true,
          default_for_new_private_repos: true,
          enforcement: :not_enforced,
          actor: @user
        )
        assert config.persisted?
        assert SecurityConfigurationDefault.find_for(target: @business, visibility: :all).any?
        assert SecurityConfigurationDefault.find_for(target: @business, visibility: :public).any?
        assert SecurityConfigurationDefault.find_for(target: @business, visibility: :private).any?

        BulkEnablementService.enable_all_secret_scanning(@business, @user)

        # find the most recent business config, this is the new one
        new_config = UnbundledSecurityConfiguration.where(target: @business).order(created_at: :desc).first
        refute_nil new_config
        refute_equal config, new_config
        assert_equal @business, T.must(new_config).target
        assert_equal 1, SecurityConfigurationDefault.find_for(target: @business, visibility: :all).count
        assert_equal config.id, SecurityConfigurationDefault.find_for(target: @business, visibility: :all).first&.security_configuration_id
        assert_equal "enabled", T.must(config).reload.secret_scanning # validate secret scanning is enabled while we're here
      end

      test "new config is not default for public if one already exists" do
        config = SecurityConfiguration.create_configuration(
          model_hash: @bundled_ghas_disabled_business_model_hash,
          default_for_new_public_repos: true,
          default_for_new_private_repos: false,
          enforcement: :not_enforced,
          actor: @user
        )
        assert config.persisted?
        assert SecurityConfigurationDefault.find_for(target: @business, visibility: :all).any?
        assert SecurityConfigurationDefault.find_for(target: @business, visibility: :public).any?

        BulkEnablementService.enable_all_secret_scanning(@business, @user)

        # find the most recent business config, this is the new one
        new_config = UnbundledSecurityConfiguration.where(target: @business).order(created_at: :desc).first

        refute_nil new_config
        refute_equal config, new_config
        assert_equal @business, T.must(new_config).target
        assert_equal 1, SecurityConfigurationDefault.find_for(target: @business, visibility: :public).count
        assert_equal config.id, SecurityConfigurationDefault.find_for(target: @business, visibility: :public).first&.security_configuration_id
        assert_equal "enabled", T.must(config).reload.secret_scanning # validate secret scanning is enabled while we're here
      end

      test "new config is not default for private if one already exists" do
        config = SecurityConfiguration.create_configuration(
          model_hash: @bundled_ghas_disabled_business_model_hash,
          default_for_new_public_repos: false,
          default_for_new_private_repos: true,
          enforcement: :not_enforced,
          actor: @user
        )
        assert config.persisted?
        assert SecurityConfigurationDefault.find_for(target: @business, visibility: :all).any?
        assert SecurityConfigurationDefault.find_for(target: @business, visibility: :private).any?

        BulkEnablementService.enable_all_secret_scanning(@business, @user)

        # find the most recent business config, this is the new one
        new_config = UnbundledSecurityConfiguration.where(target: @business).order(created_at: :desc).first

        refute_nil new_config
        refute_equal config, new_config
        assert_equal @business, T.must(new_config).target
        assert_equal 1, SecurityConfigurationDefault.find_for(target: @business, visibility: :private).count
        assert_equal config.id, SecurityConfigurationDefault.find_for(target: @business, visibility: :private).first&.security_configuration_id
        assert_equal "enabled", T.must(config).reload.secret_scanning # validate secret scanning is enabled while we're here
      end
    end

    context "enable_all_secret_scanning for unbundled, ghas enabled", skip_enterprise: true do
      test "enables secret scanning and push protection on existing org config" do
        config = UnbundledSecurityConfiguration.create_configuration(
          model_hash: @unbundled_ghas_enabled_org_model_hash,
          default_for_new_public_repos: false,
          default_for_new_private_repos: false,
          enforcement: :not_enforced,
          actor: @user
        )
        assert config.persisted?
        assert_equal @org, config.target
        assert_equal "disabled", config.secret_scanning

        BulkEnablementService.enable_all_secret_scanning(@business, @user)
        assert_equal "enabled", config.reload.secret_scanning
        assert_equal "enabled", config.reload.secret_scanning_push_protection
      end

      test "enables secret scanning and push protection on existing business config" do
        config = UnbundledSecurityConfiguration.create_configuration(
          model_hash: @unbundled_ghas_enabled_business_model_hash,
          default_for_new_public_repos: false,
          default_for_new_private_repos: false,
          enforcement: :not_enforced,
          actor: @user
        )

        assert config.persisted?
        assert_equal @business, config.target
        assert_equal "disabled", config.reload.secret_scanning

        BulkEnablementService.enable_all_secret_scanning(@business, @user)
        assert_equal "enabled", config.reload.secret_scanning
        assert_equal "enabled", config.reload.secret_scanning_push_protection
      end

      test "does not enable when feature flag disabled" do
        disable_feature_flag(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::GHAS_VOLUME_UNBUNDLED_TRIALS_AUTO_ENABLE)
        config = UnbundledSecurityConfiguration.create_configuration(
          model_hash: @unbundled_ghas_enabled_business_model_hash,
          default_for_new_public_repos: false,
          default_for_new_private_repos: false,
          enforcement: :not_enforced,
          actor: @user
        )

        assert config.persisted?
        assert_equal @business, config.target
        assert_equal "disabled", config.reload.secret_scanning

        BulkEnablementService.enable_all_secret_scanning(@business, @user)
        refute_equal "enabled", config.reload.secret_scanning
        refute_equal "enabled", config.reload.secret_scanning_push_protection
      end

      test "creates new config" do
        config = SecurityConfiguration.find_by(target: @business)
        assert_nil config

        BulkEnablementService.enable_all_secret_scanning(@business, @user)
        config = UnbundledSecurityConfiguration.find_by(target: @business)
        refute_nil config
        assert_equal @business, T.must(config).target
        assert_equal "enabled", T.must(config).reload.secret_scanning
        assert_equal "enabled", T.must(config).reload.secret_scanning_push_protection
      end

      test "new config is default for public repos if one does not exist" do
        config = SecurityConfiguration.find_by(target: @business)
        assert_nil config

        BulkEnablementService.enable_all_secret_scanning(@business, @user)
        config = UnbundledSecurityConfiguration.find_by(target: @business)
        refute_nil config
        assert_equal @business, T.must(config).target
        assert_equal "enabled", T.must(config).reload.secret_scanning
        assert_equal "enabled", T.must(config).reload.secret_scanning_push_protection
      end

      test "new config is default for private repos if one does not exist" do
        config = SecurityConfiguration.find_by(target: @business)
        assert_nil config

        BulkEnablementService.enable_all_secret_scanning(@business, @user)
        config = UnbundledSecurityConfiguration.find_by(target: @business)
        refute_nil config
        assert_equal @business, T.must(config).target
        assert_equal "enabled", T.must(config).reload.secret_scanning
        assert_equal "enabled", T.must(config).reload.secret_scanning_push_protection
      end

      test "new config is not default if one already exists" do
        config = UnbundledSecurityConfiguration.create_configuration(
          model_hash: @unbundled_ghas_enabled_business_model_hash,
          default_for_new_public_repos: true,
          default_for_new_private_repos: true,
          enforcement: :not_enforced,
          actor: @user
        )
        assert config.persisted?
        assert SecurityConfigurationDefault.find_for(target: @business, visibility: :all).any?
        assert SecurityConfigurationDefault.find_for(target: @business, visibility: :public).any?
        assert SecurityConfigurationDefault.find_for(target: @business, visibility: :private).any?

        BulkEnablementService.enable_all_secret_scanning(@business, @user)

        # find the most recent business config, this is the new one
        new_config = SecurityConfiguration.where(target: @business).order(created_at: :desc).first

        refute_equal config, new_config
        assert_equal @business, T.must(new_config).target
        assert_equal 1, SecurityConfigurationDefault.find_for(target: @business, visibility: :all).count
        assert_equal config.id, SecurityConfigurationDefault.find_for(target: @business, visibility: :all).first&.security_configuration_id
        assert_equal "enabled", T.must(config).reload.secret_scanning # validate secret scanning is enabled while we're here
      end

      test "new config is not default for public if one already exists" do
        config = UnbundledSecurityConfiguration.create_configuration(
          model_hash: @unbundled_ghas_enabled_business_model_hash,
          default_for_new_public_repos: true,
          default_for_new_private_repos: false,
          enforcement: :not_enforced,
          actor: @user
        )
        assert config.persisted?
        assert SecurityConfigurationDefault.find_for(target: @business, visibility: :all).any?
        assert SecurityConfigurationDefault.find_for(target: @business, visibility: :public).any?

        BulkEnablementService.enable_all_secret_scanning(@business, @user)

        # find the most recent business config, this is the new one
        new_config = UnbundledSecurityConfiguration.where(target: @business).order(created_at: :desc).first

        refute_equal config, new_config
        assert_equal @business, T.must(new_config).target
        assert_equal 1, SecurityConfigurationDefault.find_for(target: @business, visibility: :public).count
        assert_equal config.id, SecurityConfigurationDefault.find_for(target: @business, visibility: :public).first&.security_configuration_id
        assert_equal "enabled", T.must(config).reload.secret_scanning # validate secret scanning is enabled while we're here
      end

      test "new config is not default for private if one already exists" do
        config = UnbundledSecurityConfiguration.create_configuration(
          model_hash: @unbundled_ghas_enabled_business_model_hash,
          default_for_new_public_repos: false,
          default_for_new_private_repos: true,
          enforcement: :not_enforced,
          actor: @user
        )
        assert config.persisted?
        assert SecurityConfigurationDefault.find_for(target: @business, visibility: :all).any?
        assert SecurityConfigurationDefault.find_for(target: @business, visibility: :private).any?

        BulkEnablementService.enable_all_secret_scanning(@business, @user)

        # find the most recent business config, this is the new one
        new_config = UnbundledSecurityConfiguration.where(target: @business).order(created_at: :desc).first

        refute_equal config, new_config
        assert_equal @business, T.must(new_config).target
        assert_equal 1, SecurityConfigurationDefault.find_for(target: @business, visibility: :private).count
        assert_equal config.id, SecurityConfigurationDefault.find_for(target: @business, visibility: :private).first&.security_configuration_id
        assert_equal "enabled", T.must(config).reload.secret_scanning # validate secret scanning is enabled while we're here
      end
    end

    context "enable_all_secret_scanning for unbundled, ghas disabled", skip_enterprise: true do
      test "enables secret scanning and push protection on existing org config" do
        config = UnbundledSecurityConfiguration.create_configuration(
          model_hash: @unbundled_ghas_disabled_org_model_hash,
          default_for_new_public_repos: false,
          default_for_new_private_repos: false,
          enforcement: :not_enforced,
          actor: @user
        )
        assert config.persisted?
        assert_equal @org, config.target
        assert_equal "disabled", config.secret_scanning

        BulkEnablementService.enable_all_secret_scanning(@business, @user)
        assert_equal "enabled", config.reload.secret_scanning
        assert_equal "enabled", config.reload.secret_scanning_push_protection
      end

      test "enables secret scanning and push protection on existing business config" do
        config = UnbundledSecurityConfiguration.create_configuration(
          model_hash: @unbundled_ghas_disabled_business_model_hash,
          default_for_new_public_repos: false,
          default_for_new_private_repos: false,
          enforcement: :not_enforced,
          actor: @user
        )
        assert config.persisted?
        assert_equal @business, config.target
        assert_equal "disabled", config.reload.secret_scanning

        BulkEnablementService.enable_all_secret_scanning(@business, @user)

        assert_equal "enabled", config.reload.secret_scanning
        assert_equal "enabled", config.reload.secret_scanning_push_protection
      end

      test "does not enable when feature flag disabled" do
        disable_feature_flag(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::GHAS_VOLUME_UNBUNDLED_TRIALS_AUTO_ENABLE)
        config = UnbundledSecurityConfiguration.create_configuration(
          model_hash: @unbundled_ghas_disabled_business_model_hash,
          default_for_new_public_repos: false,
          default_for_new_private_repos: false,
          enforcement: :not_enforced,
          actor: @user
        )

        assert config.persisted?
        assert_equal @business, config.target
        assert_equal "disabled", config.reload.secret_scanning

        BulkEnablementService.enable_all_secret_scanning(@business, @user)
        refute_equal "enabled", config.reload.secret_scanning
        refute_equal "enabled", config.reload.secret_scanning_push_protection
      end

      test "creates new config" do
        config = SecurityConfiguration.find_by(target: @business)
        assert_nil config
        config = UnbundledSecurityConfiguration.find_by(target: @business)
        assert_nil config

        BulkEnablementService.enable_all_secret_scanning(@business, @user)

        config = UnbundledSecurityConfiguration.find_by(target: @business)
        refute_nil config
        assert_equal @business, T.must(config).target
        assert_equal "enabled", T.must(config).reload.secret_scanning
        assert_equal "enabled", T.must(config).reload.secret_scanning_push_protection
      end

      test "new config is default for public repos if one does not exist" do
        config = SecurityConfiguration.find_by(target: @business)
        assert_nil config

        BulkEnablementService.enable_all_secret_scanning(@business, @user)

        config = UnbundledSecurityConfiguration.find_by(target: @business)
        refute_nil config
        assert_equal @business, T.must(config).target
        assert_equal "enabled", T.must(config).reload.secret_scanning
        assert_equal "enabled", T.must(config).reload.secret_scanning_push_protection
      end

      test "new config is default for private repos if one does not exist" do
        config = SecurityConfiguration.find_by(target: @business)
        assert_nil config

        BulkEnablementService.enable_all_secret_scanning(@business, @user)

        config = UnbundledSecurityConfiguration.find_by(target: @business)
        refute_nil config
        assert_equal @business, T.must(config).target
        assert_equal "enabled", T.must(config).reload.secret_scanning
        assert_equal "enabled", T.must(config).reload.secret_scanning_push_protection
      end

      test "new config is not default if one already exists 2" do
        config = UnbundledSecurityConfiguration.create_configuration(
          model_hash: @unbundled_ghas_disabled_business_model_hash,
          default_for_new_public_repos: true,
          default_for_new_private_repos: true,
          enforcement: :not_enforced,
          actor: @user
        )
        assert config.persisted?
        assert SecurityConfigurationDefault.find_for(target: @business, visibility: :all).any?
        assert SecurityConfigurationDefault.find_for(target: @business, visibility: :public).any?
        assert SecurityConfigurationDefault.find_for(target: @business, visibility: :private).any?

        BulkEnablementService.enable_all_secret_scanning(@business, @user)

        # find the most recent business config, this is the new one
        new_config = UnbundledSecurityConfiguration.where(target: @business).order(created_at: :desc).first
        refute_nil new_config
        refute_equal config, new_config
        assert_equal @business, T.must(new_config).target
        assert_equal 1, SecurityConfigurationDefault.find_for(target: @business, visibility: :all).count
        assert_equal config.id, SecurityConfigurationDefault.find_for(target: @business, visibility: :all).first&.security_configuration_id
        assert_equal "enabled", T.must(config).reload.secret_scanning # validate secret scanning is enabled while we're here
      end

      test "new config is not default for public if one already exists" do
        config = UnbundledSecurityConfiguration.create_configuration(
          model_hash: @unbundled_ghas_disabled_business_model_hash,
          default_for_new_public_repos: true,
          default_for_new_private_repos: false,
          enforcement: :not_enforced,
          actor: @user
        )
        assert config.persisted?
        assert SecurityConfigurationDefault.find_for(target: @business, visibility: :all).any?
        assert SecurityConfigurationDefault.find_for(target: @business, visibility: :public).any?

        BulkEnablementService.enable_all_secret_scanning(@business, @user)

        # find the most recent business config, this is the new one
        new_config = UnbundledSecurityConfiguration.where(target: @business).order(created_at: :desc).first

        refute_nil new_config
        refute_equal config, new_config
        assert_equal @business, T.must(new_config).target
        assert_equal 1, SecurityConfigurationDefault.find_for(target: @business, visibility: :public).count
        assert_equal config.id, SecurityConfigurationDefault.find_for(target: @business, visibility: :public).first&.security_configuration_id
        assert_equal "enabled", T.must(config).reload.secret_scanning # validate secret scanning is enabled while we're here
      end

      test "new config is not default for private if one already exists" do
        config = UnbundledSecurityConfiguration.create_configuration(
          model_hash: @unbundled_ghas_disabled_business_model_hash,
          default_for_new_public_repos: false,
          default_for_new_private_repos: true,
          enforcement: :not_enforced,
          actor: @user
        )
        assert config.persisted?
        assert SecurityConfigurationDefault.find_for(target: @business, visibility: :all).any?
        assert SecurityConfigurationDefault.find_for(target: @business, visibility: :private).any?

        BulkEnablementService.enable_all_secret_scanning(@business, @user)

        # find the most recent business config, this is the new one
        new_config = UnbundledSecurityConfiguration.where(target: @business).order(created_at: :desc).first

        refute_nil new_config
        refute_equal config, new_config
        assert_equal @business, T.must(new_config).target
        assert_equal 1, SecurityConfigurationDefault.find_for(target: @business, visibility: :private).count
        assert_equal config.id, SecurityConfigurationDefault.find_for(target: @business, visibility: :private).first&.security_configuration_id
        assert_equal "enabled", T.must(config).reload.secret_scanning # validate secret scanning is enabled while we're here
      end
    end

    context "enable_all_secret_scanning repository configuration", skip_enterprise: true do
      test "applies new config to repositories without config" do
        repo1 = create(:repository, organization: @org, owner: @org)
        repo2 = create(:repository, organization: @org, owner: @org)
        @org.repositories << repo1
        @org.repositories << repo2

        assert_nil repo1.repository_security_configuration
        assert_nil repo2.repository_security_configuration

        BulkEnablementService.enable_all_secret_scanning(@business, @user)

        # Should find exactly one config for the business
        new_config = UnbundledSecurityConfiguration.find_by(target: @business)
        refute_nil new_config

        # Both repositories should have the new config being applied
        assert_predicate RepositorySecurityConfiguration.find_by(repository_id: repo1.id, security_configuration_id: new_config&.id), :attaching?
        assert_predicate RepositorySecurityConfiguration.find_by(repository_id: repo2.id, security_configuration_id: new_config&.id), :attaching?
      end

      test "does not apply new config to repositories without feature flag" do
        disable_feature_flag(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::GHAS_VOLUME_UNBUNDLED_TRIALS_AUTO_ENABLE)

        repo1 = create(:repository, organization: @org, owner: @org)
        repo2 = create(:repository, organization: @org, owner: @org)
        @org.repositories << repo1
        @org.repositories << repo2

        BulkEnablementService.enable_all_secret_scanning(@business, @user)

        # Should find exactly one config for the business
        new_config = UnbundledSecurityConfiguration.find_by(target: @business)
        assert_nil new_config

        # Both repositories should not have the new config being applied
        refute RepositorySecurityConfiguration.find_by(repository_id: repo1.id, security_configuration_id: new_config&.id)
        refute RepositorySecurityConfiguration.find_by(repository_id: repo2.id, security_configuration_id: new_config&.id)
      end

      test "does not apply new config to repositories with applied bundled config" do
        repo = create(:repository, organization: @org, owner: @org)
        @org.repositories << repo
        existing_config = SecurityConfiguration.create_configuration(
          model_hash: @bundled_ghas_enabled_org_model_hash,
          default_for_new_public_repos: false,
          default_for_new_private_repos: false,
          enforcement: :not_enforced,
          actor: @user
        )
        # Mark the config as applied
        create(:repository_security_configuration,
          repository: repo,
          security_configuration: existing_config,
          state: "attached",
          user: @user
        )

        BulkEnablementService.enable_all_secret_scanning(@business, @user)

        # Should find exactly one config for the business
        new_config = UnbundledSecurityConfiguration.find_by(target: @business)
        refute_nil new_config

        # Repository not have the new config being applied
        refute RepositorySecurityConfiguration.find_by(repository_id: repo.id, security_configuration_id: new_config&.id)

        # Repository should still have the original config
        assert_equal existing_config, repo.repository_security_configuration&.security_configuration
        assert_equal "attached", repo.repository_security_configuration&.state
      end

      test "does not apply new config to repositories with applied unbundled config" do
        repo = create(:repository, organization: @org, owner: @org)
        @org.repositories << repo
        existing_config = UnbundledSecurityConfiguration.create_configuration(
          model_hash: @unbundled_ghas_enabled_org_model_hash,
          default_for_new_public_repos: false,
          default_for_new_private_repos: false,
          enforcement: :not_enforced,
          actor: @user
        )

        # Mark the config as applied
        create(:repository_security_configuration,
          repository: repo,
          security_configuration: existing_config,
          state: "attached",
          user: @user
        )

        BulkEnablementService.enable_all_secret_scanning(@business, @user)

        # Should find exactly one config for the business
        new_config = UnbundledSecurityConfiguration.find_by(target: @business)
        refute_nil new_config

        # Repository not have the new config being applied
        refute RepositorySecurityConfiguration.find_by(repository_id: repo.id, security_configuration_id: new_config&.id)

        # Repository should still have the original config
        assert_equal existing_config, repo.repository_security_configuration&.security_configuration
        assert_equal "attached", repo.repository_security_configuration&.state
      end

      test "does not apply new config to repositories with applying unbundled config" do
        repo = create(:repository, organization: @org, owner: @org)
        @org.repositories << repo
        existing_config = UnbundledSecurityConfiguration.create_configuration(
          model_hash: @unbundled_ghas_enabled_org_model_hash,
          default_for_new_public_repos: false,
          default_for_new_private_repos: false,
          enforcement: :not_enforced,
          actor: @user
        )

        # Mark the config as applied
        create(:repository_security_configuration,
          repository: repo,
          security_configuration: existing_config,
          state: "attaching",
          user: @user
        )

        BulkEnablementService.enable_all_secret_scanning(@business, @user)

        # Should find exactly one config for the business
        new_config = UnbundledSecurityConfiguration.find_by(target: @business)
        refute_nil new_config

        # Repository not have the new config being applied
        refute RepositorySecurityConfiguration.find_by(repository_id: repo.id, security_configuration_id: new_config&.id)

        # Repository should still have the original config
        assert_equal existing_config, repo.repository_security_configuration&.security_configuration
        assert_equal "attaching", repo.repository_security_configuration&.state
      end
    end

    context "enable_all_secret_scanning with GitHub recommended config", skip_enterprise: true do
      test "does not modify GitHub recommended config" do
        skip "Enterprise does not have GitHub recommended config" if GitHub.enterprise?

        gh_config = SecurityConfiguration.github_recommended_configuration
        refute_nil gh_config
        refute gh_config&.secret_protection_sku_enabled
        assert_equal "enabled", gh_config&.secret_scanning

        repo = create(:repository, organization: @org, owner: @org)
        @org.repositories << repo

        # Apply GH recommended config first
        gh_config&.apply_to_repository(@user, repo, @user)
        RepositorySecurityConfiguration.find_by(repository: repo)&.update!(state: :attached)

        # Run bulk enablement
        BulkEnablementService.enable_all_secret_scanning(@business, @user)

        # Verify GH config was not modified
        T.must(gh_config).reload
        refute gh_config&.secret_protection_sku_enabled
        assert_equal "enabled", gh_config&.secret_scanning

        # Verify repo still uses original GH config
        repo_config = repo.repository_security_configuration
        refute_nil repo_config
        assert_equal gh_config, repo_config.security_configuration
        assert_equal "attaching", repo_config.state
      end
    end
  end
end
