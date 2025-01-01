# typed: true
# frozen_string_literal: true

module Team::LicensedCustomerDependency
  extend T::Sig
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { ::Team }

  delegate :licensed_customer_id, to: :organization
end
