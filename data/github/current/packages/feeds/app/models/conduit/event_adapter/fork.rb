# typed: true
# frozen_string_literal: true

module Conduit
  module EventAdapter
    class Fork < Conduit::StratocasterEventAdapter
      include GitHub::Memoizer

      REPO_DESCRIPTION_MAX_LENGTH = 150

      def html_url
        Rails.application.routes.url_helpers.repository_path(repository: repository, user_id: repository.owner)
      end

      def event_type
        "ForkEvent"
      end

      def title
        T.bind(self, T.untyped)
        description
      end

      def partial_path
        "events/fork"
      end

      memoize def forked_repo_name
        T.bind(self, T.untyped)
        name = payload[:forkee][:full_name]
        if name.present?
          name
        elsif forked_repo
          forked_repo.name_with_display_owner
        end
      end

      def repo_nwo
        repository.name_with_display_owner
      end

      def show_event_details?(viewer:)
        repo_description? ||
          repo_language? ||
          repo_stargazers? ||
          repo_help_wanted_issues?
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
        "fork"
      end

      private

      def repository
        T.bind(self, T.untyped)
        subject
      end

      def repo_description
        repository.description
      end

      memoize def forked_repo
        T.bind(self, T.untyped)
        forkee_id = payload[:forkee][:id]
        forkee = Repository.find_by(id: forkee_id)
      end

      def repo_pushed_at
        repository.pushed_at.to_s
      end

      def repo_description?
        repo_description.present?
      end

      def repo_language?
        repo_language_name.present?
      end

      def repo_stargazers?
        repo_stargazers_count.positive?
      end

      def repo_help_wanted_issues?
        repo_help_wanted_issues_count.positive?
      end
    end
  end
end
