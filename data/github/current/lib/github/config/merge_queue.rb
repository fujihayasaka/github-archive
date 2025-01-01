# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module MergeQueue
      def merge_queue_github_app_slug
        "github-merge-queue"
      end

      def merge_queue_github_app_name
        "GitHub Merge Queue"
      end

      def merge_queue_bot
        return @merge_queue_bot if defined?(@merge_queue_bot)

        integration_id = Apps::Privileged::MergeQueue.id
        @merge_queue_bot = integration_id != nil ? Integration.find(integration_id).bot : nil
      end
    end
  end

  extend Config::MergeQueue
end
