# typed: strict
# frozen_string_literal: true

module Platform
  module Interfaces
    module PlanOwner
      extend T::Sig
      extend T::Helpers

      requires_ancestor { Platform::Objects::Base }

      include Platform::Interfaces::Base
      description "Entities that can have a billing plan with various features."
      visibility :under_development

      field :plan_supports, Boolean, null: false, visibility: :under_development do
        description "Returns whether or not the account's billing plan supports a feature."
        argument :feature, Enums::PlanFeature, "The plan feature to check", required: true
        argument :privacy, Enums::PlanFeaturePrivacy, "The privacy level to check against", required: false
      end
      sig { params(feature: Symbol, privacy: T.nilable(Symbol)).returns(T::Boolean) }
      def plan_supports(feature:, privacy: nil)
        object.plan_supports?(feature, visibility: privacy)
      end

      field :plan_limit, Integer, null: false, visibility: :under_development do
        description "Returns the limit for the account's billing plan."
        argument :feature, Enums::PlanFeatureLimit, "The limit for the plan feature", required: true
        argument :privacy, Enums::PlanFeaturePrivacy, "The privacy level to check against", required: false
      end
      sig { params(feature: Symbol, privacy: T.nilable(Symbol)).returns(Integer) }
      def plan_limit(feature:, privacy: nil)
        object.plan_limit(feature, visibility: privacy)
      end
    end
  end
end
