# typed: strict
# frozen_string_literal: true

module Organization::BillingManagementDependency
  extend T::Sig

  extend ActiveSupport::Concern

  included do
    T.bind(self, T.class_of(Organization))

    after_commit :remove_billing_managers, on: :destroy
  end

  # Public: Retrieve an instance of the billing management for this organization.
  sig { returns(Organization::BillingManagement) }
  def billing
    T.bind(self, Organization)

    @billing ||= T.let(Organization::BillingManagement.new(self), T.nilable(Organization::BillingManagement))
  end

  # Public: Is the given user a billing manager?
  sig { params(user: T.nilable(User)).returns(T::Boolean) }
  def billing_manager?(user)
    billing.manager?(user)
  end

  sig { params(user: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_billing_manager?(user)
    billing.async_manager?(user)
  end

  # Public: retrieve a list of billing managers for this organization
  sig { returns(ActiveRecord::Relation) }
  def billing_managers
    billing.members
  end

  # Public: retrieve a list of billing manager ids for this organization
  sig { returns(T::Array[Integer]) }
  def billing_manager_ids
    billing.member_ids
  end

  # Internal: before_destroy hook to remove all billing managers
  sig { returns(T::Boolean) }
  def remove_billing_managers
    billing.remove_all_managers
    true
  end

  # Internal: The Users that should receive billing email
  # for an organization.
  sig { returns(T::Array[User]) }
  def billing_users
    if billing_managers.any?
      [self] + billing_managers
    else
      super
    end
  end
end
