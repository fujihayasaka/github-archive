# typed: true
# frozen_string_literal: true

module Organization::CustomerCategoryDependency
  extend ActiveSupport::Concern

  extend T::Helpers

  requires_ancestor { Organization }

  # Public: categorizes the organization into a small, medium and large category, used for stats
  # tracking
  def customer_category
    return "none" if plan.free? || GitHub.single_business_environment?
    return business&.customer_category || "none" if plan.business_plus? && business.present?
    cat = "small"
    if seats >= 20_000
      cat = "huge"
    elsif seats >= 5_000
      cat = "large"
    elsif seats >= 500
      cat = "medium"
    end
    "org_#{cat}"
  end

  # Public: Returns the number of seats for the organization
  def customer_category_size
    return 0 if plan.free? || GitHub.single_business_environment?
    return business&.customer_category_size || seats if plan.business_plus? && business.present?
    seats
  end
end
