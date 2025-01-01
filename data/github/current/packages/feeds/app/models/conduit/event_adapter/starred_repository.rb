# typed: true
# frozen_string_literal: true

module Conduit
  module EventAdapter
    class StarredRepository < Conduit::StratocasterEventAdapter
      REPO_DESCRIPTION_MAX_LENGTH = 150

      def html_url
        repository.permalink
      end

      def title
        T.bind(self, T.untyped)
        "#{actor.display_login} starred #{repo_nwo}"
      end

      def partial_path
        "events/watch"
      end

      def repo_nwo
        repository.name_with_display_owner
      end

      def show_event_details?(viewer:)
        repo_details = [repo_description, repo_language_name]
        repo_counts = [repo_stargazers_count, repo_help_wanted_issues_count]
        repo_details.any?(&:present?) || repo_counts.max > 0
      end

      def formatted_repo_description
        if repo_description.present?
          formatted = GitHub::Goomba::DescriptionPipeline.to_html(repo_description)
          HTMLTruncator.new(formatted, REPO_DESCRIPTION_MAX_LENGTH).to_html(wrap: false)
        end
      end

      def repo_language
        Linguist::Language[repo_language_name]
      end

      def repo_language_name
        repository.primary_language_name
      end

      def repo_stargazers_count
        repository.stargazer_count
      end

      def repo_stargazers_path
        "#{repository.permalink}/stargazers"
      end

      def repo_help_wanted_issues_count
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

      def icon
        "star"
      end

      def help_wanted_issues_path
        return unless repo_nwo

        name = help_wanted_label_name || "help wanted"
        param = { q: "label:\"#{name}\" is:open is:issue" }
        Rails.application.routes.url_helpers.issues_path(repository: repository, user_id: repository.owner, **param)
      end

      private

      def help_wanted_label_name
        repository.help_wanted_label&.name
      end

      def repository
        T.bind(self, T.untyped)
        subject
      end

      def repo_description
        repository.description
      end

      def repo_pushed_at
        repository.pushed_at.to_s
      end
    end
  end
end
