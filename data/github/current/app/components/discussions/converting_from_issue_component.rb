# typed: true
# frozen_string_literal: true

module Discussions
  class ConvertingFromIssueComponent < ApplicationComponent
    def initialize(discussion:)
      @discussion = discussion
    end

    private

    attr_reader :discussion

    def title
      if discussion.error?
        "Something went wrong"
      elsif discussion.converting?
        "This discussion is being migrated"
      else
        "This discussion is not ready"
      end
    end

    def original_issue_link_or_text
      if discussion.issue.present? # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        link_to("original issue", issue_path(discussion.issue))
      else
        "original issue"
      end
    end
  end
end
