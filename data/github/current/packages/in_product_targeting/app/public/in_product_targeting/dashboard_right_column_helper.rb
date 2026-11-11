# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module DashboardRightColumnHelper
    sig { params(context: T::Hash[Symbol, T.untyped]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def onboarding_promos(context)
      # Expected context keys:
      # - :current_user
      # - :current_copilot_user_v2
      #
      # Example return value:
      # [
      #   {
      #     feature: :my_feature_flag,
      #     notice: "my_user_notice",
      #     partial: "dashboard/my_promo_partial",
      #     extra_condition: -> { condition_a? && condition_b? || some_method },  # optional, can be any callable
      #     locals: { key: value }                                                # optional
      #   }
      # ]
      []
    end

    sig { params(context: T::Hash[Symbol, T.untyped]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def marketing_promos(context)
      # Expected context keys:
      # - :current_user
      # - :current_copilot_user_v2
      # - :request
      # - :copilot_user
      #
      # Example return value:
      # [
      #   {
      #     feature: :my_feature_flag,
      #     notice: "my_user_notice",
      #     partial: "dashboard/my_promo_partial",
      #     extra_condition: -> { condition_a? && condition_b? || some_method },  # optional, can be any callable
      #     locals: { key: value }                                                # optional
      #   }
      # ]
      []
    end
  end
end
