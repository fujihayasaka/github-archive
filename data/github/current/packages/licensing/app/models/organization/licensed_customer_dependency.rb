# typed: true
# frozen_string_literal: true

module Organization::LicensedCustomerDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { ::Organization }

  sig { returns(T.nilable(Integer)) }
  def licensed_customer_id
    business&.customer_id || customer&.id
  end
end
