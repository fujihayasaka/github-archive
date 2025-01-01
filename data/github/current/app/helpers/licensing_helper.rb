# typed: strict
# frozen_string_literal: true

module LicensingHelper

  sig { params(business: Business).returns(T::Boolean) }
  def show_cost_center?(business)
    business.user_scoped_cost_centers?
  end

  # Cost centers can have duplicate names, which the UI filter cannot distinguish between
  # When duplicates are present we use the cost center key uuid instead of the parameterized name to ensure a unique query
  sig { params(business: Business, cost_center: T::Hash[Symbol, T.untyped]).returns(T.nilable(String)) }
  def filter_value_for_cost_center(business, cost_center)
    parameterized_name = cost_center.dig(:name)&.parameterize
    return cost_center.dig(:costCenterKey, :uuid) if business.duplicate_cost_center_names.include?(parameterized_name)
    parameterized_name
  end
end
