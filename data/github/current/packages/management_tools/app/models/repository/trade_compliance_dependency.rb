# typed: strict
# frozen_string_literal: true

module Repository::TradeComplianceDependency
  extend ActiveSupport::Concern
  extend T::Sig
  extend T::Helpers
  requires_ancestor { Repository }

  include Repository::TradeControlsDependency
  include Repository::TradeScreeningDependency

  sig { returns(Promise[Promise[T::Boolean]]) }
  def async_has_trade_compliance_restriction?
    async_plan_owner_organization_is_fully_trade_restricted?.then do |is_fully_restricted|
      next T.cast(Promise.resolve(true), Promise[T::Boolean]) if is_fully_restricted
      async_owner_is_sdn_restricted?
    end
  end

  sig { params(new_visibility: T.nilable(String)).returns(Promise[Promise[T::Boolean]]) }
  def async_trade_compliance_read_only?(new_visibility: nil)
    is_public = public? || new_visibility == Repository::PUBLIC_VISIBILITY
    return T.cast(Promise.resolve(false), Promise[Promise[T::Boolean]]) unless is_public

    async_has_trade_compliance_restriction?
  end
end
