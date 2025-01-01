# typed: strict
# frozen_string_literal: true

module Discussions
  class ReportContentFormComponent < ApplicationComponent
    extend T::Sig

    # org_param - the display_login of the Organization to use in routing, if working with org-level discussions
    sig do
      params(
        discussion_or_comment: T.any(Discussion, DiscussionComment),
        repository: Repository,
        timeline: DiscussionTimeline,
        org_param: T.nilable(String)
      ).void
    end
    def initialize(discussion_or_comment:, repository:, timeline:, org_param: nil)
      @discussion_or_comment = discussion_or_comment
      @repository = repository
      @timeline = timeline
      @org_param = org_param
    end

    sig { returns(T.any(Discussion, DiscussionComment)) }
    attr_reader :discussion_or_comment

    sig { returns(Repository) }
    attr_reader :repository

    sig { returns(DiscussionTimeline) }
    attr_reader :timeline

    private

    sig { returns(T.nilable(String)) }
    attr_reader :org_param

    sig { returns(String) }
    def form_path
      report_content_path(repository.owner_display_login, repository.name, comment_id: discussion_or_comment.global_relay_id)
    end

    sig { returns(T::Array[String]) }
    def classifier_enums
      Platform::Enums::AbuseReportReason.values.keys - ["UNSPECIFIED"]
    end

    sig { returns(String) }
    def report_to_github_link
      flavored_contact_path(
        flavor: "report-content",
        report: "#{discussion_or_comment.author} (user)",
        content_url: helpers.discussion_timeline_comment_url(discussion_or_comment, timeline: timeline,
          org_param: org_param),
        timeline: timeline
      )
    end
  end
end
