# typed: false
# frozen_string_literal: true

module Events
  class WatchView < View
    def title_text
      [actor_text, "starred", repo_text].join(" ")
    end

    def show_event_details?(viewer:)
      return true if grouped

      repo_details = [repo_description, repo_language_name]
      repo_counts = [repo_stargazers_count, repo_help_wanted_issues_count]
      repo_details.any?(&:present?) || repo_counts.max > 0
    end

    def icon
      "watch_#{action}"
    end
  end
end
