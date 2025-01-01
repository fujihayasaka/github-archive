# typed: true
# frozen_string_literal: true

require "test_helper"

class TeamLicensedCustomerDependencyTest < GitHub::TestCase
  context "#licensed_customer_id" do
    test "returns the business customer_id when the team belongs to a business" do
      team = create(:team, organization: create(:enterprise_linked_organization))

      assert_equal team.organization.business.customer_id, team.licensed_customer_id
    end

    test "returns the org's customer id when the team belongs to a paying standalone org" do
      team = create(:team, organization: create(:organization, :with_azure_subscription))

      assert_equal team.organization.customer.id, team.licensed_customer_id
    end

    test "returns nil when the team is not associated with a customer" do
      team = create(:team, organization: create(:free_organization))

      refute team.licensed_customer_id
    end
  end
end
