# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationFeatureFlagDependencyTest < GitHub::TestCase
  context "#actor_tenant" do
    test "returns no tenant when not in Proxima mode" do
      if !TestEnv.test_in_multitenancy_mode?
        org = create(:organization)
        result = org.actor_tenant
        assert_nil result
      end
    end

    test "returns tenant info when in Proxima mode" do
      if TestEnv.test_in_multitenancy_mode?
        org = create(:organization)
        result = org.actor_tenant
        tenant = org.business
        assert_equal tenant.id, result.id
        assert_equal tenant.name, result.name
      end
    end

    test "returns no tenant info when in Proxima mode and business is missing" do
      if TestEnv.test_in_multitenancy_mode?
        org = Organization.create(login: "org-without-business-#{SecureRandom.hex(12)}")
        assert_nil org.business
        result = org.actor_tenant
        assert_nil result
      end
    end
  end
end
