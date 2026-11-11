# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module OrgOverviewHelper
    sig { params(context: T::Hash[Symbol, T.untyped]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def top_right_marketing_promos(context)
      # Expected context keys:
      # - :current_user
      # - :current_organization
      # - :request
      #
      # Example return value:
      # [
      #   {
      #     feature: :my_feature_flag,
      #     notice: "my_user_notice",
      #     partial: "organizations/my_promo_partial",
      #     extra_condition: -> { condition_a? && condition_b? || some_method },  # optional, can be any callable
      #     locals: { key: value }                                                # optional
      #   }
      # ]
      []
    end
  end
end
