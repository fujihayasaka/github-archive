# typed: false
# frozen_string_literal: true

module Events
  class ForkView < View
    def title_text
      parts = [actor_text, actor_bot_identifier_text, "forked", forked_repo_text, "from", repo_text]
      parts.compact.join(" ")
    end

    def show_event_details?(viewer:)
      repo_details = [repo_description, repo_language_name]
      repo_counts = [repo_stargazers_count, repo_help_wanted_issues_count]
      repo_details.any?(&:present?) || repo_counts.max > 0
    end

    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def forked_repo_name
      @forked_repo_name ||= unless defined?(@forked_repo_name)
        name = forkee_full_name

        if name.present?
          name
        elsif sender_record
          repo = sender_record.repositories.find_by_id(forkee_id)
          repo.try(:name_with_owner)
        end
      end
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    private

    def forked_repo_text
      forked_repo_name || "deleted"
    end
  end
end
