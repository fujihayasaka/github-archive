# typed: true
# frozen_string_literal: true

module Discussions
  class CreateIssueReferenceComponent < ApplicationComponent
    # timeline - a DiscussionTimeline
    def initialize(timeline:)
      @timeline = timeline
    end

    private

    attr_reader :timeline

    def render?
      logged_in? && timeline&.can_open_issue_from_discussion?
    end

    def show_discussion_create_issue_reference_popover?
      !current_user.dismissed_notice?(UserNotice::DISCUSSION_CREATE_ISSUE_REFERENCE_NOTICE)
    end

    def issue_create_url
      new_issue_path(timeline.repo_owner_login, timeline.repo_name,
        created_from_discussion_number: timeline.discussion_number)
    end
  end
end
