# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module Components
    module SettingsNudges
      class EnterpriseOrganizationsNudgeComponent < ApplicationComponent
        sig { returns(T::Array[InProductTargeting::NudgeConcern::NudgeConfig]) }
        attr_reader :nudges_to_render

        sig { returns User }
        attr_reader :user

        sig { returns Business }
        attr_reader :business

        sig do
          params(
            business: Business,
            user: User,
            nudges: T::Array[InProductTargeting::NudgeConcern::NudgeConfig],
            has_organizations: T::Boolean,
            system_arguments: Primer::SystemArgumentsValue
          ).void
        end
        def initialize(business:, user:, nudges:, has_organizations:, **system_arguments)
          @business = T.let(business, Business)
          @user = T.let(user, User)
          @nudges_to_render = T.let(nudges, T::Array[InProductTargeting::NudgeConcern::NudgeConfig])
          @has_organizations = T.let(has_organizations, T::Boolean)
        end

        private

        sig { returns T::Boolean }
        def render?
          return false if @nudges_to_render.empty?
          return false if @business.suspended?
          return false unless @has_organizations
          true
        end
      end
    end
  end
end
