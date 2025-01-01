# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessCustomerCategoryTest < GitHub::TestCase
  fixtures do
    @business_organization = create :organization
    @business = create(:business, organizations: [@business_organization])
  end

  context "#customer_category" do
    if GitHub.single_business_environment?
      test "none in single business environment" do
        assert_equal "none", @business.customer_category
      end
    else
      test "none for trial" do
        @business.update(trial_expires_at: 2.weeks.from_now)
        assert_equal "none", @business.reload.customer_category
      end

      test "no additional queries when counting seats" do
        assert_equal 0, count_queries { @business.customer_category }
      end

      test "business category for business" do
        assert_equal "business_small", @business.customer_category
      end

      test "medium category for business with more than 500 seats" do
        @business.update(seats: 500)
        assert_equal "business_medium", @business.reload.customer_category
      end

      test "large category for business with more than 5000 seats" do
        @business.update(seats: 5_000)
        assert_equal "business_large", @business.reload.customer_category
      end

      test "huge category for business with more than 20000 seats" do
        @business.update(seats: 20_000)
        assert_equal "business_huge", @business.reload.customer_category
      end
    end
  end
end
