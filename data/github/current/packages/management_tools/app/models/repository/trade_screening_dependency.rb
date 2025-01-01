# typed: strict
# frozen_string_literal: true

module Repository::TradeScreeningDependency
  extend ActiveSupport::Concern
  extend T::Helpers
  requires_ancestor { Repository }

  sig { params(new_visibility: T.nilable(String)).returns(Promise[T::Boolean]) }
  def async_trade_screening_read_only?(new_visibility: nil)
    is_public = public? || new_visibility == Repository::PUBLIC_VISIBILITY
    return T.cast(Promise.resolve(false), Promise[T::Boolean]) unless is_public

    async_owner_is_sdn_restricted?
  end

  sig { returns Promise[T::Boolean] }
  def async_owner_is_sdn_restricted?
    async_plan_owner.then do |plan_owner|
      next Promise.resolve(false) unless plan_owner.present?

      flag_enabled_for_org = plan_owner.organization? && plan_owner.feature_enabled?(:sdn_organization_suspension_v3)
      next Promise.resolve(false) unless plan_owner.user? || flag_enabled_for_org

      plan_owner.async_sdn_suspended?
    end
  end
end
