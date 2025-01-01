# typed: true
# frozen_string_literal: true

module Conduit
  module EventAdapter
    class CreatePush < Conduit::StratocasterEventAdapter
      def html_url
        push.url
      end

      def title
        T.bind(self, T.untyped)
        description
      end

      def partial_path
        "events/create"
      end

      def show_event_details?(viewer:)
        false
      end

      def repository?
        false
      end

      def branch?
        true
      end

      def object
        "branch"
      end

      def object_name
        T.bind(self, T.untyped)
        ref
      end

      def tree_path
        "/#{repo_nwo}/tree/#{UrlHelper.escape_branch(object_name)}"
      end

      def analytics_target
        "branch link"
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

      def repo_nwo
        repository.name_with_display_owner
      end

      def repo_owner
        repository.owner
      end

      def icon
        "git-branch"
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
