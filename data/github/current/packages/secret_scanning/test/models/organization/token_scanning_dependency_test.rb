# typed: true
# frozen_string_literal: true

require "test_helper"

class OrgTokenScanningDependencyTest < GitHub::TestCase

  setup do
    @business = create(:business)
    @admin = create(:user)
    @org = create(:organization)
    @business_org = create(:organization, admin: @admin, business: @business)
    GitHub.stubs(:configuration_supports_advanced_security?).returns(true)
  end

  test "sets and gets push protection custom message" do
    msg1 = "custom msg1"
    @org.set_push_protection_custom_message(msg1, @admin)
    get1 = @org.get_push_protection_custom_message
    assert_equal msg1, get1

    msg2 = "custom msg2"
    @org.set_push_protection_custom_message(msg2, @admin)
    get2 = @org.get_push_protection_custom_message
    assert_equal msg2, get2
  end

  test "does not inherit message from business" do
    msg1 = "custom msg1"
    @business.set_push_protection_custom_message(msg1, @admin)
    got_msg = @business_org.get_push_protection_custom_message
    assert_nil got_msg
  end

  test "returns own config" do
    msg1 = "custom msg1"
    @business.set_push_protection_custom_message(msg1, @admin)
    msg2 = "custom msg2"
    @business_org.set_push_protection_custom_message(msg2, @admin)
    got_msg = @business_org.get_push_protection_custom_message
    assert_equal msg2, got_msg
  end

  test "returns own config when business does not have one" do
    assert_nil @business.get_push_protection_custom_message
    msg2 = "custom msg2"
    @business_org.set_push_protection_custom_message(msg2, @admin)
    got_msg = @business_org.get_push_protection_custom_message
    assert_equal msg2, got_msg
  end
end
