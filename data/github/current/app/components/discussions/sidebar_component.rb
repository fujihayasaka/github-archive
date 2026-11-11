# typed: true
# frozen_string_literal: true

module Discussions
  class SidebarComponent < ApplicationComponent
    # org_param - the display_login of the Organization to use in routing, if working with org-level discussions
    sig do
      params(
        timeline: T.untyped,
        participants: T.untyped,
        events: T.untyped,
        deferred_content: T.untyped,
        org_param: T.nilable(String),
      ).void
    end
    def initialize(timeline:, participants:, events:, deferred_content: false, org_param: nil)
      @timeline = timeline
      @participants = participants
      @events = events
      @deferred_content = deferred_content
      @org_param = org_param
    end

    private

    attr_reader :timeline, :participants, :events, :deferred_content

    sig { returns T.nilable(String) }
    attr_reader :org_param

    delegate :discussion, to: :timeline

    sig { returns T.nilable(String) }
    def converted_issue_link
      # the issue _should_ be preloaded by the controller
      converted_issue = discussion.issue if discussion.issue_id.present?
      return unless converted_issue

      link_to("##{converted_issue.number}", issue_path(converted_issue), class: "Link--inTextBlock")
    end

    sig { returns T::Boolean }
    private def display_converted_issue_message?
      discussion.converted_from_issue? && converted_issue_link.present?
    end
  end
end
