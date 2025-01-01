# typed: true
# frozen_string_literal: true

module Conduit
  module EventAdapter
    class DeletePush < Conduit::StratocasterEventAdapter
      def title
        T.bind(self, T.untyped)
        description
      end

      def repo_pushed_on
        date = push.pushed_at
        format = if date.year == Date.today.year
          "%b %-d"
        else
          "%b %-d, %Y"
        end
        date.strftime(format)
      end

      def html_url = push.permalink

      def partial_path = "events/delete"

      def repo_nwo = repository.name_with_display_owner

      def show_event_details?(viewer:) = false

      def icon = "git-branch"

      def ref_type
        T.bind(self, T.untyped)
        push.ref_is_tag? ? :tag : :branch
      end

      private

      def push
        T.bind(self, T.untyped)
        subject
      end

      def repository
        T.bind(self, T.untyped)
        push.repository
      end
    end
  end
end
