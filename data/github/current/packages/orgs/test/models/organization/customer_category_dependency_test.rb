# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationCustomerCategoryTest < GitHub::TestCase
  fixtures do
    @business_organization = create :organization
    @business = create(:business, organizations: [@business_organization])
    @free_organization = create :free_organization
    @organization = create :organization
  end

  context "#customer_category" do
    if GitHub.single_business_environment?
      test "none in single business environment" do
        assert_equal "none", @organization.customer_category
      end
    else
      test "none for free organization" do
        assert_equal "none", @free_organization.customer_category
      end

      test "no additional queries when counting seats" do
        # 1 query for business_organization_membership, 1 to fetch business
        assert_equal 2, count_queries { @business_organization.customer_category }
        # 1 query for business_organization_membership
        assert_equal 1, count_queries { @organization.customer_category }
      end

      test "business category for business-owned organization" do
        assert_equal "business_small", @business_organization.customer_category
      end

      test "org category for team-plan organization" do
        assert_equal "org_small", @organization.customer_category
      end

      test "medium category for orgs with more than 500 seats" do
        @organization.update(seats: 500)
        assert_equal "org_medium", @organization.reload.customer_category
      end

      test "large category for orgs with more than 5000 seats" do
        @organization.update(seats: 5_000)
        assert_equal "org_large", @organization.reload.customer_category
      end

      test "huge category for orgs with more than 20000 seats" do
        @organization.update(seats: 20_000)
        assert_equal "org_huge", @organization.reload.customer_category
      end
    end
  end
end
