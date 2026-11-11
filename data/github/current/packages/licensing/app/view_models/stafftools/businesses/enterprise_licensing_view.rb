# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::EnterpriseLicensingView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include GitHub::Memoizer
  include Stafftools::LicensingHelper

  attr_reader :business

  delegate :name, to: :business

  memoize def sales_serve_over_consumption
    business.sales_serve_plan_subscription && (business.consumed_enterprise_licenses > business.purchased_enterprise_licenses)
  end
end
