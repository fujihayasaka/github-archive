# typed: true
# frozen_string_literal: true

require "test_helper"

class MultiTenantBusinessTest < GitHub::TestCase
  setup do
    on_multi_tenant_enterprise
  end

  context "set_shortcode" do
    test "uses passed in shortcode" do
      business = Business.create(name: "test3", slug: "test3", shortcode: "test3", business_type: :enterprise_managed, seats: 1)
      refute_nil business.shortcode
      assert_equal "test3", business.shortcode
    end

    test "errors if shortcode is not passed in" do
      business = Business.create(name: "test", slug: "test", business_type: :enterprise_managed, seats: 1)
      refute business.valid?
      assert_nil business.shortcode
      assert_includes business.errors.messages[:shortcode], "required to enable enterprise managed users"
    end
  end
end
