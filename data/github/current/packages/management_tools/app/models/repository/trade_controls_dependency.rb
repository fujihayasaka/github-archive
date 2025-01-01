# typed: strict
# frozen_string_literal: true

module Repository::TradeControlsDependency
  include GitHub::BatchMethod

  extend ActiveSupport::Concern
  extend T::Sig
  extend T::Helpers
  requires_ancestor { Repository }

  included do
    batch_method :has_any_trade_restrictions? do |repos|
      promises = repos.map do |repo|
        repo.async_plan_owner.then do |plan_owner|
          next false unless plan_owner
          plan_owner.async_has_any_trade_restrictions?
        end
      end
      results = Promise.all(promises).sync
      repos.zip(results).to_h
    end
  end

  # Public: Restrict write access to public repos owned by trade controls restricted
  # organizations
  #
  # Returns Boolean
  sig { params(new_visibility: T.nilable(String)).returns(T::Boolean) }
  def trade_controls_read_only?(new_visibility: nil)
    async_trade_controls_read_only?(new_visibility: new_visibility).sync
  end

  sig { params(new_visibility: T.nilable(String)).returns(Promise[T::Boolean]) }
  def async_trade_controls_read_only?(new_visibility: nil)
    is_public = public? || new_visibility == Repository::PUBLIC_VISIBILITY
    return T.cast(Promise.resolve(false), Promise[T::Boolean]) unless is_public

    async_plan_owner_organization_is_fully_trade_restricted?
  end

  # Public: Is the plan owner an organization, and is that organization fully trade restricted
  #
  # Returns Boolean
  sig { returns(T::Boolean) }
  def plan_owner_organization_is_fully_trade_restricted?
    async_plan_owner_organization_is_fully_trade_restricted?.sync
  end

  sig { returns(Promise[T::Boolean]) }
  def async_plan_owner_organization_is_fully_trade_restricted?
    async_plan_owner.then do |plan_owner|
      next Promise.resolve(false) unless plan_owner&.organization?

      plan_owner.async_has_full_trade_restrictions?
    end
  end

  private

  sig { returns(T::Boolean) }
  def ensure_owner_is_not_trade_controls_restricted
    if trade_restricted?
      errors.add(:trade_controls_restricted_owner, "can't create repositories.")
      return false
    end

    true
  end

  sig { returns(T::Boolean) }
  def ensure_creator_is_not_trade_controls_restricted
    return true if !(private? && created_by&.has_any_trade_restrictions?)

    errors.add(:trade_controls_restricted_creator, "can't create repositories.")
    false
  end
end
