# typed: strict
# frozen_string_literal: true

module Sculk
  module MoveWork
    class FeatureBannerComponent < ApplicationComponent

      sig { returns T::Hash[Symbol, T.untyped] }
      attr_reader :system_arguments

      sig { returns T.nilable(::MoveWork::Feature) }
      attr_reader :feature

      sig do
        params(
          feature: T.nilable(String),
          system_arguments: T.untyped
        ).void
      end
      def initialize(feature: nil, **system_arguments)
        @feature = T.let(::MoveWork::Feature.try_deserialize(feature), T.nilable(::MoveWork::Feature))
        @system_arguments = system_arguments
      end

      sig { returns(T::Boolean) }
      def render?
        return false if GitHub.enterprise?
        @feature.present?
      end

      sig { returns(T.nilable(Symbol)) }
      def icon
        @feature&.metadata[:icon]
      end

      sig { returns(String) }
      def feature_name
        @feature&.name
      end

      sig { returns(T::Boolean) }
      def require_paid_plan?
        @feature&.metadata[:require_paid_plan]
      end

      sig { returns(String) }
      def title
        if require_paid_plan?
          "To access #{feature_name} in a private repository, you’ll need to move it to a GitHub Team organization account."
        else
          "To access #{feature_name}, you’ll need to move it to an organization."
        end
      end

      sig { returns(T.nilable(String)) }
      def description
        if require_paid_plan?
          "GitHub Team costs $#{GitHub::Plan.business.unit_cost} per user/month."
        end
      end

      sig { returns(T.nilable(String)) }
      def link_to_team_marketing_page
        render(Primer::Beta::Link.new(
          href: team_marketing_page_path,
          classes: "Link--inTextBlock"
          )
        ) { "Learn more about GitHub Team" }
      end
    end
  end
end
