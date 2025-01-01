# typed: strict
# frozen_string_literal: true

module Discussions
  class SidebarLinksComponent < ApplicationComponent
    include FeatureFlagHelper
    extend T::Sig

    sig { params(timeline: DiscussionTimeline).void }
    def initialize(timeline:)
      @timeline = timeline
    end

    private

    sig { returns(DiscussionTimeline) }
    attr_reader :timeline

    delegate :discussion, :can_lock_discussion?, :can_unlock_discussion?, :can_manage_spotlights?, :can_delete_discussion?,
      :can_open_issue_from_discussion?, :can_transfer_discussion?, :repo_owner, :repo_owner_login, :repo_name, :discussion_number,
      to: :timeline

    sig { returns(T::Boolean) }
    def render?
      return false unless logged_in?
      can_lock_discussion? ||
        can_unlock_discussion? ||
        can_transfer_discussion? ||
        can_manage_spotlights? ||
        can_delete_discussion? ||
        can_open_issue_from_discussion?
    end

    sig { returns(T::Boolean) }
    def show_lock_option?
      return false if discussion.locked?
      can_lock_discussion?
    end

    sig { returns(T::Boolean) }
    def show_unlock_option?
      return false unless discussion.locked?
      can_unlock_discussion?
    end
  end
end
