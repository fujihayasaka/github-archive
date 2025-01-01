# typed: true
# frozen_string_literal: true

module Comments
  class SuggestionButtonComponent < ApplicationComponent
    include SuggestedChangesAnalyticsHelper, VarnishHelper

    def initialize(
      textarea_id: nil,
      outdated: false,
      lines: [],
      contains_deletions: false,
      disabled: false,
      missing_commit: false,
      empty_selection: false,
      pull_request: nil
    )
      @outdated = outdated
      @lines = lines
      @contains_deletions = contains_deletions
      @disabled = disabled
      @missing_commit = missing_commit
      @empty_selection = empty_selection
      @pull_request = pull_request
      @textarea_id = textarea_id
    end

    def disabled?
      @disabled
    end

    def data
      suggested_changes_click("insert_suggestion", current_user, @pull_request).merge({
        lines: data_lines,
        "md-button": true,
        "hotkey-scope": @textarea_id,
        hotkey: hotkey
      })
    end

    def textarea_id
      @textarea_id
    end

    def description
      if @outdated
        "Suggestions cannot be applied on outdated comments."
      elsif @contains_deletions
        "Applying suggestions on deleted lines is not supported."
      elsif @missing_commit || @empty_selection
        "Suggestions cannot be applied on this comment."
      else
        "Add a suggestion, <Ctrl+g>"
      end
    end

    private

    def data_lines
      @lines.map { |line| line[1..-1] }.join("\n")
    end

    def hotkey
      request&.user_agent&.match?(/Macintosh/) ? "Meta+g" : "Control+g"
    end
  end
end
