# typed: strict
# frozen_string_literal: true

module Dashboard

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

      if show_organization_tasks_nudge?(@user, @organization, :nucbs)
        nucbs_variant = get_nucbs_nudge_variant(@user)

        if nucbs_variant >= 0
          @nudges_to_render.push(
            Dashboard::DashboardNudgeConfig.new(
              treatment_type: nucbs_variant == 0 ? :control : :treatment,
              nudge_category: "dashboard_notify_users_cb_seat_#{nucbs_variant}",
              nudge: get_new_tasks_nudge_config(:nucbs)
            )
          )
        end
      end
    end

    sig { returns T::Boolean }
    def render?
      return false if @user.nil?
      return false unless @user.subscribed_to_in_product_messages?
      return false if @nudges_to_render.empty?
      true
    end
  end
end
