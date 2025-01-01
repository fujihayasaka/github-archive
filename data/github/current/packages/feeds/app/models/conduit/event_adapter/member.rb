# typed: true
# frozen_string_literal: true

module Conduit
  module EventAdapter
    class Member < Conduit::StratocasterEventAdapter
      def html_url
        repository.permalink
      end

      def title
        T.bind(self, T.untyped)
        description
      end

      def partial_path
        "events/member"
      end

      def icon
        "feed-add-user"
      end

      def member_login
        member.display_login
      end

      def repo_nwo
        repository.name_with_display_owner
      end

      def action
        "added"
      end

      private

      def member
        T.bind(self, T.untyped)
        subject.member
      end

      def repository
        T.bind(self, T.untyped)
        subject.repository
      end
    end
  end
end
