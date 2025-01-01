# typed: strict
# frozen_string_literal: true

require "test_helper"

class Copilot::Organizations::InstrumentationDetailsTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  context "copilot_billing_type" do
    test "organization has a billing type" do
      # it's very impossible/difficult to setup the proper state for this test given the factories we have
      Customer.any_instance.stubs(:billing_type).returns(nil)
      organization = create(:organization)
      ::Organization.any_instance.stubs(:billing_type).returns("card")

      assert_equal "card", Copilot::Organization.new(organization).copilot_billing_type
    end

    test "organization customer has a billing type" do
      # it's very impossible/difficult to setup the proper state for this test given the factories we have
      Customer.any_instance.stubs(:billing_type).returns("card")
      organization = create(:organization, :zuora)
      ::Organization.any_instance.stubs(:billing_type).returns(nil)

      assert_equal "card", Copilot::Organization.new(organization).copilot_billing_type
    end

    test "organization has a business with a billing type" do
      biz = create(:business, customer: create(:credit_card_customer))
      organization = create(:enterprise_linked_organization, business: biz)
      ::Organization.any_instance.stubs(:billing_type).returns(nil)
      ::Business.any_instance.stubs(:billing_type).returns("card")

      assert_equal "card", Copilot::Organization.new(organization).copilot_billing_type
    end

    test "organization has a business with a customer with a billing type" do
      biz = create(:business, customer: create(:credit_card_customer))
      organization = create(:enterprise_linked_organization, business: biz)
      ::Organization.any_instance.stubs(:billing_type).returns(nil)
      ::Organization.any_instance.stubs(:customer).returns(nil)
      ::Business.any_instance.stubs(:billing_type).returns(nil)
      Customer.any_instance.stubs(:billing_type).returns("card")

      assert_equal "card", Copilot::Organization.new(organization).copilot_billing_type
    end

    test "mixed types" do
      biz = create(:business, customer: create(:credit_card_customer))
      organization = create(:enterprise_linked_organization, business: biz)

      ::Organization.any_instance.stubs(:billing_type).returns("card")
      ::Business.any_instance.stubs(:billing_type).returns("invoice")
      Customer.any_instance.stubs(:billing_type).returns("paypal")

      logs = capture_logs do
        assert_equal "paypal", Copilot::Organization.new(organization).copilot_billing_type
      end

      assert_includes logs, "copilot_billing_type: More than one billing type found"
      assert_includes logs, "gh.org.billing_type=\"card\""
      assert_includes logs, "gh.org.business.billing_type=\"invoice\""
      assert_includes logs, "gh.org.business.customer.billing_type=\"paypal\""
    end
  end
end if GitHub.copilot_enabled?
