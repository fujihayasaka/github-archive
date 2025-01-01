# typed: strict
# frozen_string_literal: true

module Business::BillingManagementDependency
  extend T::Sig
  extend T::Helpers

  requires_ancestor { Business }

  delegate :manager?,
           :managers,
           :manager_ids,
    to: :billing, prefix: :billing

  # Public: Retrieve an instance of the billing management for this business.
  sig { returns(Business::BillingManagement) }
  def billing
    @billing ||= T.let(Business::BillingManagement.new(self), T.nilable(Business::BillingManagement))
  end

  # Internal: before_destroy hook to remove all billing managers
  sig { returns(T::Boolean) }
  def remove_billing_managers
    billing.remove_all_managers
    true
  end

  # Internal: The Users that should receive billing email
  # for an business.
  sig { returns(T::Array[User]) }
  def billing_users
    owners + billing_managers
  end
end
