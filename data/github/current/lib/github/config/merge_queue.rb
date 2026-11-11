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

        @merge_queue_bot = Apps::Privileged.integration(:merge_queue)&.bot
      end
    end
  end

  extend Config::MergeQueue
end
