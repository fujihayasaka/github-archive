# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationLicensedCustomerDependencyTest < GitHub::TestCase
  context "#licensed_customer_id" do
    test "returns the business customer_id when the org belongs to a business" do
      org = create(:enterprise_linked_organization)

      assert_equal org.business.customer_id, org.licensed_customer_id
    end

    test "returns the org's customer id when the org is standalone" do
      org = create(:organization, :with_azure_subscription)

      assert_equal org.customer.id, org.licensed_customer_id
    end

    test "returns nil when the org is not associated with a customer" do
      org = create(:free_organization)

      refute org.licensed_customer_id
    end
  end
end
