# typed: strict
# frozen_string_literal: true

module Settings
  class EnterpriseListItemNudgeComponent < EnterpriseListItemComponent
    include DigitalFrontDoor::NudgeConcern

    # Currently we can render 0, 1, or 2 nudges per business:
    #  - the Copilot Business (CB) nudge
    #  - the current "Org Sequence" nudge (in left->right order)
    sig { returns(T::Array[DigitalFrontDoor::NudgeConfig]) }
    attr_reader :nudges_to_render

    sig do
      params(
        business: Business,
        user: User,
        show_trial_information: T::Boolean,
        system_arguments: Primer::SystemArgumentsValue
      ).void
    end
    def initialize(business:, user:, show_trial_information: false, **system_arguments)
      super(**T.unsafe({ business: business, user: user, show_trial_information: show_trial_information, **system_arguments }))

      @nudges_to_render = T.let([], T::Array[DigitalFrontDoor::NudgeConfig])
      @nudges_to_render.push(get_dfd_new_tasks_config(:cb)) if show_dfd_new_tasks_nudge?(user, business, :cb)

      # ordered by priority
      org_sequence_nudges = [:org, :repo, :code, :ghas]
      org_sequence_nudge_to_show = org_sequence_nudges.find { |type| show_dfd_new_tasks_nudge?(user, business, type) }

      @nudges_to_render.push(get_dfd_new_tasks_config(org_sequence_nudge_to_show)) if org_sequence_nudge_to_show
    end

    sig { returns T.nilable(Repository) }
    def oldest_repo
      return nil unless business

      user_orgs = ::Organization
          .includes(business_membership: [:business])
          .where(business_organization_memberships: { business_id: business&.id })

      user_orgs
        .filter { |org| org.created_at + 1.day <= Time.current }
        .map { |org| org.repositories_associated_with(current_user) }
        .flatten
        .sort { |repo| repo.created_at }
        .first
    end

    sig { returns T::Boolean }
    def render?
      return false unless current_user.feature_flag_enabled?(:dfd_new_tasks, default: false)
      return false if @user.nil?
      return false if @nudges_to_render.empty?
      return false if @business&.suspended?
      true
    end

  end

end
