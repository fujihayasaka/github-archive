# typed: strict
# frozen_string_literal: true

module TriageAgent
  # Storage-agnostic value object that holds parsed trigger configuration
  # from the triage agent config file's `on:` block.
  #
  # Each trigger (issue-create, issue-comment) can be independently enabled
  # or disabled, and issue-create supports an optional filter query that
  # determines which issues should be triaged.
  class TriggerConfig

    sig { returns(T::Boolean) }
    attr_reader :issue_create_enabled

    sig { returns(T.nilable(String)) }
    attr_reader :issue_create_filter

    sig { returns(T::Boolean) }
    attr_reader :issue_comment_enabled

    sig do
      params(
        issue_create_enabled: T::Boolean,
        issue_create_filter: T.nilable(String),
        issue_comment_enabled: T::Boolean
      ).void
    end
    def initialize(
      issue_create_enabled: false,
      issue_create_filter: nil,
      issue_comment_enabled: false
    )
      @issue_create_enabled = issue_create_enabled
      @issue_create_filter = issue_create_filter
      @issue_comment_enabled = issue_comment_enabled
    end

    # Returns true when the issue-create trigger is enabled and has a filter query.
    sig { returns(T::Boolean) }
    def issue_create_has_filter?
      @issue_create_enabled && @issue_create_filter.present?
    end

    # Returns true when at least one trigger is enabled.
    sig { returns(T::Boolean) }
    def any_triggers?
      @issue_create_enabled || @issue_comment_enabled
    end
  end
end
