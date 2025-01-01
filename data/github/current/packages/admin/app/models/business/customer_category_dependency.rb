# typed: true
# frozen_string_literal: true

module Business::CustomerCategoryDependency
  extend ActiveSupport::Concern
  extend T::Sig
  extend T::Helpers

  requires_ancestor { Business }

  # Public: categorizes the business into a small, medium and large category, used for stats
  # tracking
  def customer_category
    return "none" if GitHub.single_business_environment? || trial?
    cat = "small"
    if seats >= 20_000
      cat = "huge"
    elsif seats >= 5_000
      cat = "large"
    elsif seats >= 500
      cat = "medium"
    end
    "business_#{cat}"
  end

  # Public: Returns the number of seats for the business
  def customer_category_size
    return 0 if GitHub.single_business_environment? || trial?
    seats
  end
end
