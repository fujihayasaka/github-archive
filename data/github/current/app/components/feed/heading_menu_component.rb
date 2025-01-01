# typed: true
# frozen_string_literal: true

module Feed
  class HeadingMenuComponent < ApplicationComponent
    def initialize(item:, actor: nil, **system_arguments)
      @item = item
      @actor = actor
      @system_arguments = system_arguments
    end

    attr_reader :item, :system_arguments
    delegate :reason, :reason_message, :actor_reason?, :dismissible?, to: :item

    def render?
      return false unless item
      return false unless logged_in?
      show_report_option? || show_reason? || show_unfollowable_actor_option? ||
        show_unstarrable_option? || show_delete_option? || show_hide_option? ||
        show_dismiss_announcement_option?
    end

    memoize def actor
      @actor || item.actor
    end

    private

    memoize def show_report_option?
      GitHub.user_abuse_mitigation_enabled? &&
        !viewer_is_actor &&
        actor.present? &&
        !viewer_belongs_to_org? &&
        !item.announcement?
    end

    memoize def show_unfollowable_actor_option?
      return unless actor.present?

      actor_reason? && reason.split(",").include?("followed")
    end

    memoize def show_unstarrable_option?
      return unless actor.present?

      reason_message&.include?("starred") && !item.announcement? && item.repository.present?
    end

    def viewer_belongs_to_org?
      return false if !actor_is_org?

      actor.direct_or_team_member?(current_user)
    end

    memoize def show_reason?
      reason.present? &&
        reason_message.present?
    end

    memoize def show_disinterest_option?
      !viewer_is_actor
    end

    memoize def show_delete_option?
      item.deletable_by?(current_user)
    end

    memoize def show_hide_option?
      return false unless item.profile_activity_context?
      item.adminable_by?(current_user)
    end

    memoize def show_dismiss_announcement_option?
      item.announcement?
    end

    def actor_id
      item.actor_id
    end

    def actor_is_org?
      actor.is_a?(Organization)
    end

    def org_report_path
      return nil unless actor_is_org?
      flavored_contact_path(report: actor.to_s, flavor: "report-abuse")
    end

    def viewer_is_actor
      current_user.id == actor_id
    end

    def details_classes
      if item.announcement? || Flipper[:feeds_v2].enabled?(current_user)
        return ""
      end

      "js-feed-item-heading-menu"
    end
  end
end
