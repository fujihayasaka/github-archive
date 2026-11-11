# typed: strict
# frozen_string_literal: true

module Dashboard

  class BusinessNudgeComponent < ApplicationComponent
    include ApplicationComponent::Rescuable
    include DigitalFrontDoor::DfdNudgeConcern

    rescue_from StandardError, with: :nothing

    NudgeConfig = InProductTargeting::NudgeConcern::NudgeConfig

    # Currently we can render 0, 1, or 2 nudges per business:
    #  - the Copilot Business (CB) nudge
    #  - the current "Org Sequence" nudge (in left->right order)
    sig { returns(T::Array[NudgeConfig]) }
    attr_reader :nudges_to_render

    sig { returns T.nilable(User) }
    attr_reader :user

    sig { returns T.nilable(Business) }
    attr_reader :business

    sig do
      params(
        business: Business,
        user: User,
        system_arguments: Primer::SystemArgumentsValue
      ).void
    end
    def initialize(business:, user:, **system_arguments)
      @business = business
      @user = user

      @nudges_to_render = T.let([], T::Array[NudgeConfig])

      # DFD specific nudges
      if @user.present? && @user.feature_flag_enabled?(:dfd_new_tasks, default: false)
        @nudges_to_render.push(get_dfd_new_tasks_config(:cb)) if show_dfd_new_tasks_nudge?(user, business, :cb)

        # ordered by priority
        org_sequence_nudges = [:org, :repo, :code, :ghas]
        org_sequence_nudge_to_show = org_sequence_nudges.find { |type| show_dfd_new_tasks_nudge?(user, business, type) }

        @nudges_to_render.push(get_dfd_new_tasks_config(org_sequence_nudge_to_show)) if org_sequence_nudge_to_show
      end
    end

    sig { returns T.nilable(Repository) }
    def oldest_repo
      return nil unless business

      user_orgs = ::Organization
          .includes(business_membership: [:business])
          .where(business_organization_memberships: { business_id: business&.id })

      user_orgs
        .map { |org| org.repositories_associated_with(@user) }
        .flatten
        .sort_by(&:created_at)
        .first
    end

    sig { returns T::Boolean }
    def render?
      return false if @user.nil?
      return false if @nudges_to_render.empty?
      return false if @business.suspended?
      true
    end

  end

end
