# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module Commentable
      include Platform::Interfaces::Base
      description "An object that can be commented on"
      visibility :internal

      field :viewer_can_comment, Boolean, visibility: :under_development, null: false,
        description: "Indicates whether the current user can add a new comment."

      def viewer_can_comment
        (@object.is_a?(PullRequest) ? @object.async_issue : Promise.resolve(@object)).then do |issue|
          issue.can_comment?(@context[:viewer])
        end
      end

      field :viewer_blocked_by_author, Boolean, visibility: :internal, null: false,
        description: "Indicates whether the current user has been blocked by the issue or pull request's author."

      def viewer_blocked_by_author
        @object.async_user.then do |user|
          if @context[:viewer].nil? || user.nil? || @context[:viewer] == user
            false
          else
            @context[:viewer].blocked_by?(user)
          end
        end
      end

      field :over_comment_limit, Boolean, visibility: :under_development, null: false,
        description: "Indicates whether the issue or pull request has exceeded the comment limit."

      def over_comment_limit
        (@object.is_a?(PullRequest) ? @object.async_issue : Promise.resolve(@object)).then do |issue|
          issue.over_comment_limit?
        end
      end

    end
  end
end
