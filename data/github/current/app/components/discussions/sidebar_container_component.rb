# typed: true
# frozen_string_literal: true

module Discussions
  class SidebarContainerComponent < ApplicationComponent
    # org_param - the display_login of the Organization to use in routing, if working with org-level discussions
    sig do
      params(
        discussion: T.untyped,
        timeline: T.untyped,
        participants: T.untyped,
        current_repository: T.untyped,
        events: T.untyped,
        deferred_content: T.untyped,
        org_param: T.nilable(String)
      ).void
    end
    def initialize(discussion:, timeline:, participants:, current_repository:, events:, deferred_content: false, org_param: nil)
      @discussion = discussion
      @timeline = timeline
      @participants = participants
      @current_repository = current_repository
      @events = events
      @deferred_content = deferred_content
      @org_param = org_param
    end

    attr_reader :discussion, :timeline, :participants, :current_repository, :events, :deferred_content

    sig { returns T.nilable(String) }
    attr_reader :org_param

    delegate :blocked_from_commenting?, to: :timeline

    memoize def localization_config
      helpers.localization_config
    end
  end
end
