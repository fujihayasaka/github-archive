# typed: true
# frozen_string_literal: true

module Conduit
  module EventAdapter
    class Release < Conduit::StratocasterEventAdapter
      def release_id
        release.id
      end

      def release_tag_name
        release.tag_name
      end

      def release_title
        release.name
      end

      def repo_nwo
        repository.name_with_display_owner
      end

      def repo_owner
        repository.owner
      end

      def release_short_description_html
        release.short_description_html_info[:html]
      end

      def release_short_description_html_truncated?
        release.short_description_html_info[:truncated?]
      end

      def release_mentions
        release.mentions
      end

      def description
        "#{repo_owner_login} released #{release_tag_name} at #{repo_nwo}"
      end

      def title
        T.bind(self, T.untyped)
        description
      end

      def html_url
        release_path
      end

      def icon
        "release"
      end

      def partial_path
        "events/release"
      end

      def release_path
        release.permalink
      end

      private

      def release
        T.bind(self, T.untyped)
        subject
      end

      def repository
        T.bind(self, T.untyped)
        release.repository
      end

      def repo_owner_login
        repo_owner.display_login
      end

      def repo_name
        repository.name
      end
    end
  end
end
