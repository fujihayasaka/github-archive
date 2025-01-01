# typed: false
# frozen_string_literal: true

module Events
  class PublicView < View
    def title_text
      parts = [actor_text, actor_bot_identifier_text, "made", repo_text, "public"]
      parts.compact.join(" ")
    end

    def show_event_details?(viewer:)
      repo_details = [repo_description, repo_language_name]
      repo_counts = [repo_stargazers_count, repo_help_wanted_issues_count]
      repo_details.any?(&:present?) || repo_counts.max > 0
    end
  end
end
