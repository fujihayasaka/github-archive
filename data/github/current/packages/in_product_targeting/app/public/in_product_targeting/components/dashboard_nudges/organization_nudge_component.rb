# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module Components
    module DashboardNudges
      # rubocop:disable Rails/ModuleNaming
      class DashboardNudgeConfig < T::Struct
        const :treatment_type, Symbol # :control or :treatment
        const :nudge, InProductTargeting::OrganizationNudgeConcern::NudgeConfig
        const :nudge_category, String
      end
      # rubocop:enable Rails/ModuleNaming

      class OrganizationNudgeComponent < ApplicationComponent
        include ApplicationComponent::Rescuable
        include InProductTargeting::OrganizationNudgeConcern

        rescue_from StandardError, with: :nothing

        sig { returns(T::Array[DashboardNudgeConfig]) }
        attr_reader :nudges_to_render

        sig { returns T.nilable(User) }
        attr_reader :user

        sig { returns T.nilable(Organization) }
        attr_reader :organization

        sig do
          params(
            organization: Organization,
            user: User,
            system_arguments: Primer::SystemArgumentsValue
          ).void
        end
        def initialize(organization:, user:, **system_arguments)
          @organization = organization
          @user = user

          @nudges_to_render = T.let([], T::Array[DashboardNudgeConfig])
          # NOTE: the Copilot CLI enabled dashboard nudge moved to
          # OrganizationCopilotCliEnabledDashboardNudgeComponent (rendered as a React partial).
        end

        sig { returns T::Boolean }
        def render?
          return false if @user.nil?
          return false unless @user.subscribed_to_in_product_messages?
          return false if @nudges_to_render.empty?
          return false unless ::InProductTargeting.domain.messaging_subscribed?(field: "promotion_subscribed", organization_id: @organization.id)
          business = @organization.business
          return false if business && !::InProductTargeting.domain.messaging_subscribed?(field: "promotion_subscribed", business_id: business.id)
          true
        end
      end
    end
  end
end
