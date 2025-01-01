# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityConfigurationPolicyTest < GitHub::TestCase
  include SecurityProductsEnablement::EnterpriseTestHelpers

  fixtures do
    @org = create(:organization)
  end

  setup do
    @security_config = create(:security_configuration, target: @org)
  end

  context ".create_or_update" do
    test "creates security configuration policy with correct attributes" do
      security_config_policy = assert_difference "SecurityConfigurationPolicy.count", 1 do
        SecurityConfigurationPolicy.create_or_update(
          security_configuration_id: @security_config.id,
          target: @org,
          enforcement: :enforced
        )
      end

      assert_equal @security_config.id, security_config_policy.security_configuration_id
      assert_equal @org, security_config_policy.target
      assert_equal "enforced", security_config_policy.enforcement
    end

    test "does not create a new policy record when one already exists for the given target" do
      configution_policy = create(:security_configuration_policy, :enforced, security_configuration: @security_config)

      assert_equal 1, SecurityConfigurationPolicy.for_organization(@org).count
      assert_no_changes -> { configution_policy.reload } do
        SecurityConfigurationPolicy.create_or_update(
          target: @org,
          security_configuration_id: @security_config.id,
          enforcement: :enforced
        )
      end
      assert_equal 1, SecurityConfigurationPolicy.for_organization(@org).count
    end

    test "updates the enforcement attribute when it has changed on the policy" do
      configution_policy = create(:security_configuration_policy, :not_enforced, security_configuration: @security_config)

      SecurityConfigurationPolicy.create_or_update(
        target: @org,
        security_configuration_id: @security_config.id,
        enforcement: :enforced
      )

      configution_policy.reload
      assert configution_policy.enforced?
    end
  end
end
