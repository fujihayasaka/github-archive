# typed: strict
# frozen_string_literal: true

module Settings
  class OrganizationListItemNudgeComponent < ApplicationComponent
    include ApplicationComponent::Rescuable
    include InProductTargeting::OrganizationNudgeConcern

    rescue_from StandardError, with: :nothing

    sig { returns User }
    attr_reader :user

    sig { returns ::Organization }
    attr_reader :organization

    sig { returns(T::Array[InProductTargeting::OrganizationNudgeConcern::NudgeConfig]) }
    attr_reader :nudges_to_render

    sig { returns(::Copilot::Organization) }
    attr_reader :copilot_org

    sig do
      params(
        organization: ::Organization,
        user: User,
        system_arguments: Primer::SystemArgumentsValue
      ).void
    end
    def initialize(organization:, user:, **system_arguments)
      @organization = organization
      @user = user
      @copilot_org = T.let(::Copilot::Organization.new(@organization), ::Copilot::Organization)

      @nudges_to_render = T.let([], T::Array[InProductTargeting::OrganizationNudgeConcern::NudgeConfig])

      if show_organization_tasks_nudge?(@user, @organization, :win_cb_users_back_credit_offer_to_accept)
        @nudges_to_render.push(get_new_tasks_nudge_config(:win_cb_users_back_credit_offer_to_accept, @organization))
      end

      if show_organization_tasks_nudge?(@user, @organization, :win_cb_users_back_credit_assign_seats)
        @nudges_to_render.push(get_new_tasks_nudge_config(:win_cb_users_back_credit_assign_seats, @organization))
      end

      if show_organization_tasks_nudge?(@user, @organization, :win_cb_users_back_credit)
        @nudges_to_render.push(get_new_tasks_nudge_config(:win_cb_users_back_credit, @organization))
      end

      if show_organization_tasks_nudge?(@user, @organization, :raf_cb)
        @nudges_to_render.push(get_new_tasks_nudge_config(:raf_cb, @organization))
      end

    end

    # Only show the dismiss button to Orgs which don't yet have Copilot Business enabled
    # so we don't spam them indefinitely
    # (currently RAF cannot dismiss RAF requests until the org has enabled CB)
    sig do
      params(nudge: InProductTargeting::OrganizationNudgeConcern::NudgeConfig).returns(T::Boolean)
    end
    def should_show_dismiss_button?(nudge)
      return false if nudge.nudge_type == :raf_cb && copilot_org.has_copilot_for_business?
      true
    end

    sig { returns T::Boolean }
    def render?
      return false if @user.nil?
      return false if @nudges_to_render.empty?
      true
    end

  end

end
