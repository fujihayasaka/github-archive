# typed: true
# frozen_string_literal: true

module Issues
  class ComposerView
    include HydroHelper

    attr_reader :issue, :user, :related_issue_events_session_key

    def initialize(issue, user)
      raise ArgumentError, "no issue for ComposerView" unless issue
      @issue = issue
      @user = user
    end

    def show_body_errors?
      issue.errors[:body].any?
    end

    def body_errors
      issue.errors[:body].first
    end

    def issue_body
      issue.body || issue.body_template.tap do |template|
        if template.present?
          GitHub.dogstats.increment(type, tags: ["action:issue_body", "type:form_with_template"])
        else
          GitHub.dogstats.increment(type, tags: ["action:issue_body", "type:form_without_template"])
        end
      end
    end

    def type
      "issue"
    end
  end
end
