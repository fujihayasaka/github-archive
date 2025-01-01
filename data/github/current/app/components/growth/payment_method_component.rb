# typed: strict
# frozen_string_literal: true

module Growth
  class PaymentMethodComponent < ApplicationComponent
    extend T::Sig

    sig { returns(T.any(User, Organization, Business)) }
    attr_reader :target

    sig { returns(T.nilable(String)) }
    attr_reader :return_to

    sig { params(target: T.any(User, Organization, Business), return_to: T.nilable(String)).void }
    def initialize(target:, return_to: nil)
      @target = target
      @return_to = return_to
    end

    private

    sig { returns(T::Boolean) }
    def render?
      return false unless GitHub.billing_enabled?
      return false unless logged_in?
      return false if has_commercial_interaction_restriction?

      target.has_saved_trade_screening_record?
    end

    sig { returns(T::Boolean) }
    memoize def has_commercial_interaction_restriction?
      return target.has_commercial_interaction_restriction?(feature_type: :default) if target.user?

      target.has_commercial_interaction_restriction?(feature_type: :default) || current_user.has_commercial_interaction_restriction?(feature_type: :default)
    end
  end
end
