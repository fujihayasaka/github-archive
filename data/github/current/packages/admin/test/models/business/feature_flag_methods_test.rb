# typed: true
# frozen_string_literal: true

require "test_helper"

class Business::FeatureFlagMethodsTest < GitHub::TestCase
  fixtures do
    @business = create(:business, owners: [create(:user)])
  end

  context "#billing_vnext_enabled?" do
    test "returns false if the business hasn't been enabled" do
      disable_feature_flag(:billing_vnext)
      refute_predicate @business, :billing_vnext_enabled?
    end

    test "returns true if the business has been enabled" do
      enable_feature_flag(:billing_vnext, @business)
      assert_predicate @business, :billing_vnext_enabled?
    end
  end

  context "#patsv2_enabled?" do
    test "returns true" do
      assert_predicate @business, :patsv2_enabled?
    end
  end

  context "#actor_tenant" do
    test "returns no tenant when not in Proxima mode" do
      if !TestEnv.test_in_multitenancy_mode?
        result = @business.actor_tenant
        assert_nil result
      end
    end

    test "returns tenant info when in Proxima mode" do
      if TestEnv.test_in_multitenancy_mode?
        with_env("MULTI_TENANT_ENTERPRISE" => "1") do
          result = @business.actor_tenant
          assert_equal @business.id, result.id
          assert_equal @business.name, result.name
        end
      end
    end
  end
end
