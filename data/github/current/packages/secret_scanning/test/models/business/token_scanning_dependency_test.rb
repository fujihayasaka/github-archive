# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessTokenScanningDependencyTest < GitHub::TestCase

  fixtures do
    @business = create(:business)
    @admin = create(:user)
    @business_org = create(:organization, admin: @admin, business: @business)
  end

  setup do
    GitHub.stubs(:configuration_supports_advanced_security?).returns(true)
  end

  test "sets and gets push protection custom message" do
    msg1 = "custom msg1"
    @business_org.set_push_protection_custom_message(msg1, @admin)
    get1 = @business_org.get_push_protection_custom_message
    assert_equal msg1, get1

    msg2 = "custom msg2"
    @business_org.set_push_protection_custom_message(msg2, @admin)
    get2 = @business_org.get_push_protection_custom_message
    assert_equal msg2, get2
  end
end
