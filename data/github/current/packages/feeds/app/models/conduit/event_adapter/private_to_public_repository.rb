# typed: true
# frozen_string_literal: true

module Conduit
  module EventAdapter
    class PrivateToPublicRepository < Conduit::StratocasterEventAdapter
      REPO_DESCRIPTION_MAX_LENGTH = 150

      def html_url
        T.bind(self, T.untyped)
        Rails.application.routes.url_helpers.repository_path(repository: repository, user_id: repository.owner)
      end

      def title
        T.bind(self, T.untyped)
        description
      end

      def partial_path = "events/public"

      def show_event_details?(viewer:)
        repo_details = [repo_description, repo_language_name]
        repo_counts = [repo_stargazers_count, repo_help_wanted_issues_count]
        repo_details.any?(&:present?) || repo_counts.max > 0
      end

      def repo_nwo
        repository.name_with_display_owner
      end

      def formatted_repo_description
        if repo_description.present?
          HTMLTruncator.new(repo_description, REPO_DESCRIPTION_MAX_LENGTH).to_html(wrap: false)
        end
      end

      def repo_language
        Linguist::Language[repo_language_name]
      end

      def repo_language_name
        T.bind(self, T.untyped)
        repository.primary_language_name
      end

      def repo_stargazers_count
        T.bind(self, T.untyped)
        repository.stargazer_count
      end

      def repo_help_wanted_issues_count
        T.bind(self, T.untyped)
        repository.help_wanted_issues_count
      end

      def repo_pushed_on
        return unless repo_pushed_at.present?

        date = Date.parse(repo_pushed_at)
        format = if date.year == Date.today.year
          "%b %-d"
        else
          "%b %-d, %Y"
        end
        date.strftime(format)
      end

      def icon = "feed-public"

      private

      def repository
        T.bind(self, T.untyped)
        subject
      end

      def repo_description
        T.bind(self, T.untyped)
        repository.description
      end

      def repo_pushed_at = repository.pushed_at.to_s
    end
  end
end
