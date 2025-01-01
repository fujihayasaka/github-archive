# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  class SecurityFeaturesTest < GitHub::TestCase
    fixtures do
      @biz = if GitHub.enterprise?
        create(:global_business)
      else
        create(:business, :enterprise_managed)
      end

      @biz_owner = @biz.owners.first
      @emu_user = if GitHub.enterprise?
        create(:user, business: @biz)
      else
        create(:emu, business: @biz)
      end

      @org_owner = create(:user)
      @org = create(:organization, admin: @org_owner, business: @biz)
    end

    setup do
      setup_advanced_security(true)

      # Settings to enable EMU for GHES
      GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true) if GitHub.enterprise?
      GitHub.stubs(:security_center_for_emus_enabled?).returns(true) if GitHub.enterprise?
    end

    context ".visible_features" do
      test "returns enabled features on the instance when target is nil" do
        enabled_feature = [true, true, true]
        enabled_feature.permutation.each do |code_scanning, secret_scanning, dependabot_alerts|
          stub_feature_enablement(code_scanning:, secret_scanning:, dependabot_alerts:)

          visible_features = SecurityFeatures.visible_features(nil)

          assert_equal code_scanning, visible_features.include?("code_scanning")
          assert_equal secret_scanning, visible_features.include?("secret_scanning")
          assert_equal dependabot_alerts, visible_features.include?("dependabot_alerts")
        end
      end

      test "returns enabled features on the instance when org has purchased advanced security" do
        setup_advanced_security(true)
        enabled_feature = [true, true, true]
        enabled_feature.permutation.each do |code_scanning, secret_scanning, dependabot_alerts|
          stub_feature_enablement(code_scanning:, secret_scanning:, dependabot_alerts:)

          visible_features = SecurityFeatures.visible_features(@org)

          assert_equal code_scanning, visible_features.include?("code_scanning")
          assert_equal secret_scanning, visible_features.include?("secret_scanning")
          assert_equal dependabot_alerts, visible_features.include?("dependabot_alerts")
        end
      end

      test "returns enabled features on the instance when business has purchased advanced security" do
        setup_advanced_security(true)
        enabled_feature = [true, true, true]
        enabled_feature.permutation.each do |code_scanning, secret_scanning, dependabot_alerts|
          stub_feature_enablement(code_scanning:, secret_scanning:, dependabot_alerts:)

          visible_features = SecurityFeatures.visible_features(@biz)

          assert_equal code_scanning, visible_features.include?("code_scanning")
          assert_equal secret_scanning, visible_features.include?("secret_scanning")
          assert_equal dependabot_alerts, visible_features.include?("dependabot_alerts")
        end
      end

      test "returns available features when org has not purchased advanced security, and has limited security center" do
        setup_advanced_security(false)
        SecurityFeatures.stubs(:limited_security_center_available?).returns(true)

        enabled_feature = [true, true, true]
        enabled_feature.permutation.each do |code_scanning, secret_scanning, dependabot_alerts|
          stub_feature_enablement(code_scanning:, secret_scanning:, dependabot_alerts:)

          visible_features = SecurityFeatures.visible_features(@org)

          assert_equal code_scanning, visible_features.include?("code_scanning")
          assert_equal secret_scanning, visible_features.include?("secret_scanning")
          assert_equal dependabot_alerts, visible_features.include?("dependabot_alerts")
        end
      end

      test "returns available features when business has not purchased advanced security, and has limited security center" do
        setup_advanced_security(false)
        SecurityFeatures.stubs(:limited_security_center_available?).returns(true)

        enabled_feature = [true, true, true]
        enabled_feature.permutation.each do |code_scanning, secret_scanning, dependabot_alerts|
          stub_feature_enablement(code_scanning:, secret_scanning:, dependabot_alerts:)

          visible_features = SecurityFeatures.visible_features(@biz)

          assert_equal code_scanning, visible_features.include?("code_scanning")
          assert_equal secret_scanning, visible_features.include?("secret_scanning")
          assert_equal dependabot_alerts, visible_features.include?("dependabot_alerts")
        end
      end

      test "returns available features when business has not purchased advanced security, but not limited security center" do
        setup_advanced_security(false)
        SecurityFeatures.stubs(:limited_security_center_available?).returns(false)

        enabled_feature = [true, true, true]
        enabled_feature.permutation.each do |code_scanning, secret_scanning, dependabot_alerts|
          stub_feature_enablement(code_scanning:, secret_scanning:, dependabot_alerts:)

          visible_features = SecurityFeatures.visible_features(@biz)

          assert_equal dependabot_alerts, visible_features.include?("dependabot_alerts")
          refute visible_features.include?("secret_scanning")
          refute visible_features.include?("code_scanning")
        end
      end

      context "with user target" do
        test "ignores random user and returns enabled features on the instance as if the target is nil", skip_enterprise: true do
          # Skipping for GHES, there's is no "random" user for GHES
          ::SecurityCenter::FeatureFlagHelper.stubs(:no_visible_features_for_non_emu_owners?).returns(false)

          rando = create(:user)
          stub_feature_enablement(code_scanning: true, secret_scanning: true, dependabot_alerts: true)

          visible_features = SecurityFeatures.visible_features(rando)

          assert visible_features.include?("code_scanning")
          assert visible_features.include?("secret_scanning")
          assert visible_features.include?("dependabot_alerts")
        end

        test "returns no visible feature on the instance if the target is random user when feature flag enabled", skip_enterprise: true do
          # Skipping for GHES, there's is no "random" user for GHES
          ::SecurityCenter::FeatureFlagHelper.stubs(:no_visible_features_for_non_emu_owners?).returns(true)

          rando = create(:user)
          stub_feature_enablement(code_scanning: true, secret_scanning: true, dependabot_alerts: true)

          assert_empty SecurityFeatures.visible_features(rando)
        end

        test "returns EMU ready features for an EMU target when advanced security is available" do
          stub_feature_enablement(code_scanning: true, secret_scanning: true, dependabot_alerts: true)

          visible_features = SecurityFeatures.visible_features(@emu_user)

          refute visible_features.include?("code_scanning")
          assert visible_features.include?("secret_scanning")
          refute visible_features.include?("dependabot_alerts")
        end

        test "ignores EMU and returns enabled features on the instance as if the target is nil when GHAS disabled" do
          ::SecurityCenter::FeatureFlagHelper.stubs(:no_visible_features_for_non_emu_owners?).returns(false)

          setup_advanced_security(false)
          stub_feature_enablement(code_scanning: true, secret_scanning: true, dependabot_alerts: true)

          visible_features = SecurityFeatures.visible_features(@emu_user)

          assert visible_features.include?("code_scanning")
          assert visible_features.include?("secret_scanning")
          assert visible_features.include?("dependabot_alerts")
        end

        test "returns no visible feature on the instance if the target is EMU when GHAS disabled and feature flag enabled" do
          ::SecurityCenter::FeatureFlagHelper.stubs(:no_visible_features_for_non_emu_owners?).returns(true)

          setup_advanced_security(false)
          stub_feature_enablement(code_scanning: true, secret_scanning: true, dependabot_alerts: true)

          assert_empty SecurityFeatures.visible_features(@emu_user)
        end
      end
    end

    context ".limited_security_center_available" do
      test "returns false if target is not an org or business" do
        refute SecurityFeatures.limited_security_center_available?(nil)

        rando = create(:user)
        refute SecurityFeatures.limited_security_center_available?(rando)
      end

      test "returns false unless the target has a business plus plan", skip_enterprise: true, skip_in_multitenant_mode: true do
        biz = create(:business)
        org = create(:organization)

        refute SecurityFeatures.limited_security_center_available?(org)
        refute SecurityFeatures.limited_security_center_available?(biz)
      end

      test "returns false for emus when the managing business has advanced security", skip_enterprise: true do
        setup_advanced_security(true)
        emu = create(:emu)
        emu_business = emu.enterprise_managed_business

        assert emu_business.plan.business_plus?, "Broken assumption that the managed business to have a business plus plan"
        refute SecurityFeatures.limited_security_center_available?(emu)
        refute SecurityFeatures.limited_security_center_available?(emu_business)
      end

      test "returns false when restricted to dotcom requests, but on enterprise", enterprise_only: true do
        setup_advanced_security(false)
        org = create(:business_plus_org)

        refute SecurityFeatures.limited_security_center_available?(org, dotcom_request_only: true)
        refute SecurityFeatures.limited_security_center_available?(org.business, dotcom_request_only: true)
      end

      test "returns false if the target has business_plus plan & advanced security", skip_enterprise: true do
        setup_advanced_security(true)
        org = create(:business_plus_org)

        refute SecurityFeatures.limited_security_center_available?(org)
        refute SecurityFeatures.limited_security_center_available?(org.business)
      end

      test "returns false for emus when the managing business does not have advanced security", skip_enterprise: true do
        setup_advanced_security(false)
        emu = create(:emu)
        emu_business = emu.enterprise_managed_business

        assert emu_business.plan.business_plus?, "Broken assumption that the managed business to have a business plus plan"
        refute SecurityFeatures.limited_security_center_available?(emu)
        assert SecurityFeatures.limited_security_center_available?(emu_business)
      end

      test "returns true if the target has business_plus plan & does not have advanced security", skip_enterprise: true do
        setup_advanced_security(false)
        org = create(:business_plus_org)

        assert SecurityFeatures.limited_security_center_available?(org)
      end
    end

    test "code scanning is enabled" do
      stub_feature_enablement(code_scanning: true)
      assert_empty SecurityFeatures.all_visible(@org) - SecurityFeatures.all
      assert_same_elements %w[code_scanning repository_configuration], SecurityFeatures.all_visible(@org)
    end

    test "secret scanning is enabled" do
      stub_feature_enablement(secret_scanning: true)
      assert_empty SecurityFeatures.all_visible(@org) - SecurityFeatures.all
      assert_same_elements %w[secret_scanning repository_configuration], SecurityFeatures.all_visible(@org)
    end

    test "Dependabot alerts is enabled" do
      stub_feature_enablement(dependabot_alerts: true)
      assert_empty SecurityFeatures.all_visible(@org) - SecurityFeatures.all
      assert_same_elements %w[dependabot_alerts repository_configuration], SecurityFeatures.all_visible(@org)
    end

    test "all features are enabled" do
      stub_feature_enablement(code_scanning: true, secret_scanning: true, dependabot_alerts: true)
      assert_equal SecurityFeatures.all, SecurityFeatures.all_visible(@org)
      assert_same_elements %w[code_scanning secret_scanning dependabot_alerts repository_configuration], SecurityFeatures.all_visible(@org)
    end

    test "no features are enabled" do
      stub_feature_enablement
      assert_empty SecurityFeatures.all_visible(@org) - SecurityFeatures.all
      assert_same_elements ["repository_configuration"], SecurityFeatures.all_visible(@org)
    end

    test "Non-GHAS org returns correct features" do
      Organization.any_instance.stubs(:advanced_security_purchased?).returns(false)
      stub_feature_enablement(code_scanning: true, secret_scanning: true, dependabot_alerts: true)

      if GitHub.enterprise?
        assert_same_elements %w[dependabot_alerts repository_configuration], SecurityFeatures.all_visible(@org)
      else
        assert_same_elements %w[code_scanning dependabot_alerts repository_configuration secret_scanning], SecurityFeatures.all_visible(@org)
      end
    end

    test "Non-GHAS business returns correct features" do
      Business.any_instance.stubs(:advanced_security_purchased?).returns(false)
      stub_feature_enablement(code_scanning: true, secret_scanning: true, dependabot_alerts: true)

      if GitHub.enterprise?
        assert_same_elements %w[dependabot_alerts repository_configuration], SecurityFeatures.all_visible(@biz)
      else
        assert_same_elements %w[code_scanning dependabot_alerts repository_configuration secret_scanning], SecurityFeatures.all_visible(@biz)
      end
    end

    test "features returned in expected ordering" do
      stub_feature_enablement(code_scanning: true, dependabot_alerts: true, secret_scanning: true)
      pft = RepositorySecurityCenterStatus.primary_feature_types
      assert_equal pft, SecurityFeatures.visible_features(@org).map(&:to_sym)
      assert_equal pft, SecurityFeatures.all_visible(@org)[0...pft.size]&.map(&:to_sym)
    end

    context "#full_security_center_available?" do
      test "true when advanced security is enabled" do
        assert SecurityFeatures.full_security_center_available?(@org)
        assert SecurityFeatures.full_security_center_available?(@biz)
      end

      test "false when advanced security is disabled" do
        Organization.any_instance.stubs(:advanced_security_purchased?).returns(false)
        refute SecurityFeatures.full_security_center_available?(@org)

        Business.any_instance.stubs(:advanced_security_purchased?).returns(false)
        refute SecurityFeatures.full_security_center_available?(@biz)
      end
    end

    context "#security_center_available?" do
      test "true when advanced security is enabled" do
        assert SecurityFeatures.security_center_available?(@org)
        assert SecurityFeatures.security_center_available?(@biz)
      end

      test "true when advanced security is disabled and Limited Security Center is available" do
        Organization.any_instance.stubs(:advanced_security_purchased?).returns(false)
        Business.any_instance.stubs(:advanced_security_purchased?).returns(false)
        SecurityFeatures.stubs(:limited_security_center_available?).returns(true)

        assert SecurityFeatures.security_center_available?(@org)
        assert SecurityFeatures.security_center_available?(@biz)
      end

      test "false when advanced security is disabled and Limited Security Center is unavailable" do
        Organization.any_instance.stubs(:advanced_security_purchased?).returns(false)
        Business.any_instance.stubs(:advanced_security_purchased?).returns(false)
        SecurityFeatures.stubs(:limited_security_center_available?).returns(false)

        refute SecurityFeatures.security_center_available?(@org)
        refute SecurityFeatures.security_center_available?(@biz)
      end
    end

    private

    def stub_feature_enablement(code_scanning: false, secret_scanning: false, dependabot_alerts: false)
      SecurityCenter::SecurityFeatures.stubs(
        code_scanning_enabled_for_instance?: code_scanning,
        secret_scanning_enabled_for_instance?: secret_scanning,
        dependabot_alerts_enabled_for_instance?: dependabot_alerts,
      )
    end

    def setup_advanced_security(enabled)
      User.any_instance.stubs(:advanced_security_purchased?).returns(enabled)
      Organization.any_instance.stubs(:advanced_security_purchased?).returns(enabled)
      Business.any_instance.stubs(:advanced_security_purchased?).returns(enabled)
    end
  end
end
