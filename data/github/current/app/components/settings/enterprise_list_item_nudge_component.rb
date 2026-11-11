# typed: strict
# frozen_string_literal: true

module Settings
  class EnterpriseListItemNudgeComponent < EnterpriseListItemComponent
    include DigitalFrontDoor::DfdNudgeConcern
    include InProductTargeting::EnterpriseNudgeConcern

    # Currently we can render 0, 1, or 2 nudges per business:
    #  - the Copilot Business (CB) nudge
    #  - the current "Org Sequence" nudge (in left->right order)
    sig { returns(T::Array[InProductTargeting::NudgeConcern::NudgeConfig]) }
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

      @nudges_to_render = T.let([], T::Array[InProductTargeting::NudgeConcern::NudgeConfig])

      # DFD specific nudges
      if @user.present? && @user.feature_flag_enabled?(:dfd_new_tasks, default: false)
        @nudges_to_render.push(get_dfd_new_tasks_config(:cb)) if show_dfd_new_tasks_nudge?(user, business, :cb)

        # ordered by priority
        org_sequence_nudges = [:org, :repo, :code, :ghas]
        org_sequence_nudge_to_show = org_sequence_nudges.find { |type| show_dfd_new_tasks_nudge?(user, business, type) }

        if org_sequence_nudge_to_show && allowed_org_sequence_nudge?(org_sequence_nudge_to_show)
          @nudges_to_render.push(get_dfd_new_tasks_config(org_sequence_nudge_to_show))
        end
      end

      # Enterprise-ready preview nudges only show if the user doesn't have a DFD nudge to display
      if @user.present? && @nudges_to_render.empty?
        enterprise_preview_nudge = nudge_to_show(user, business)

        @nudges_to_render.push(enterprise_preview_nudge) if enterprise_preview_nudge
      end
    end

    private

    sig { params(nudge_type: Symbol).returns(T::Boolean) }
    def allowed_org_sequence_nudge?(nudge_type)
      # Code and GHAS nudges require repository access since they link to
      # repository-specific actions (e.g., pushing code, enabling GHAS features)
      return true unless [:code, :ghas].include?(nudge_type)

      oldest_repo.present?
    end

    sig { returns T.nilable(Repository) }
    def oldest_repo
      return nil unless business
      return nil unless @user

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
      return false if @business&.suspended?
      true
    end

  end

end
