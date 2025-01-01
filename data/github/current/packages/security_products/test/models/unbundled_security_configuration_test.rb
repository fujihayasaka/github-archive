# typed: true
# frozen_string_literal: true

require "test_helper"

class UnbundledSecurityConfigurationTest < GitHub::TestCase
  include SecurityProductsEnablement::EnterpriseTestHelpers
  fixtures do
    @org = create(:organization)
    @user = create(:user)
    @business = create(:business, owners: [@user], organizations: [@org])
  end

  context "validations" do
    test "prohibits use of enable_ghas" do
      config = build(:unbundled_security_configuration, enable_ghas: true)
      refute config.valid?
    end

    test "code security features can only be enabled if code_security_sku_enabled is true" do
      UnbundledSecurityConfiguration::CODE_SECURITY_SKU_FEATURES.each do |feature|
        required_fields = {
          "#{feature}": 1,
          code_security_sku_enabled: false,
        }

        config = build(:unbundled_security_configuration, required_fields)

        refute config.valid?

        required_fields[:code_security_sku_enabled] = true
        config = build(:unbundled_security_configuration, required_fields)

        assert config.valid?
      end
    end

    test "secret protection features can only be enabled if secret_protection_sku_enabled is true" do
      UnbundledSecurityConfiguration::SECRET_PROTECTION_SKU_FEATURES.each do |feature|
        required_fields = {
          "#{feature}": 1,
          secret_protection_sku_enabled: false,
        }

        config = build(:unbundled_security_configuration, required_fields)

        refute config.valid?

        required_fields[:secret_protection_sku_enabled] = true
        config = build(:unbundled_security_configuration, required_fields)

        assert config.valid? unless feature == :secret_scanning_validity_checks && !GitHub.secret_scanning_validity_checks_available_on_instance?
      end
    end
  end

  context "bundling", skip_enterprise: true do
    test "an unbundled config can be bundled" do
      config = create(:unbundled_security_configuration, target: @org, secret_protection_sku_enabled: true, code_security_sku_enabled: true)
      refute config.enable_ghas

      bundled_config = config.bundle!

      assert_equal config.id, bundled_config.id
      assert_instance_of SecurityConfiguration, bundled_config

      assert bundled_config.enable_ghas
      refute bundled_config.secret_protection_sku_enabled
      refute bundled_config.code_security_sku_enabled

      assert_equal "enabled", bundled_config.secret_scanning
      assert_equal "enabled", bundled_config.code_scanning
    end

    test "a SP config can be bundled" do
      config = create(:unbundled_security_configuration, target: @org, secret_protection_sku_enabled: true, code_security_sku_enabled: false, code_scanning: "disabled")
      refute config.enable_ghas

      bundled_config = config.bundle!

      assert_equal config.id, bundled_config.id
      assert_instance_of SecurityConfiguration, bundled_config

      assert bundled_config.enable_ghas
      refute bundled_config.secret_protection_sku_enabled
      refute bundled_config.code_security_sku_enabled

      assert_equal "enabled", bundled_config.secret_scanning
      assert_equal "disabled", bundled_config.code_scanning
    end

    test "a CS config can be bundled" do
      config = create(:unbundled_security_configuration, :disabled, target: @org, secret_protection_sku_enabled: false, code_security_sku_enabled: true, code_scanning: "enabled")
      refute config.enable_ghas

      bundled_config = config.bundle!

      assert_equal config.id, bundled_config.id
      assert_instance_of SecurityConfiguration, bundled_config

      assert bundled_config.enable_ghas
      refute bundled_config.secret_protection_sku_enabled
      refute bundled_config.code_security_sku_enabled

      assert_equal "disabled", bundled_config.secret_scanning
      assert_equal "enabled", bundled_config.code_scanning
    end

    test "a free config can be bundled" do
      config = create(:unbundled_security_configuration, :disabled, target: @org, secret_protection_sku_enabled: false, code_security_sku_enabled: false)
      refute config.enable_ghas

      bundled_config = config.bundle!

      assert_equal config.id, bundled_config.id
      assert_instance_of SecurityConfiguration, bundled_config

      refute bundled_config.enable_ghas
      refute bundled_config.secret_protection_sku_enabled
      refute bundled_config.code_security_sku_enabled

      assert_equal "disabled", bundled_config.secret_scanning
      assert_equal "disabled", bundled_config.code_scanning
    end

    test "a global config can't be bundled" do
      config = create(:unbundled_security_configuration, target_type: "global", target_id: 0)

      assert_raises ArgumentError do
        config.bundle!
      end
    end
  end
end
