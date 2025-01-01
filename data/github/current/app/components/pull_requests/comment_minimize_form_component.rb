# typed: true
# frozen_string_literal: true

module PullRequests
  class CommentMinimizeFormComponent < ApplicationComponent
    include CommentsHelper

    attr_reader :comment

    def initialize(comment:, inline: false)
      @comment = comment
      @inline = inline
    end

    def render?
      comment.respond_to?(:async_update_path_uri)
    end

    private

    def path
      path = "#{comment.async_update_path_uri.sync}/minimize" # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      path += "?inline=true" if @inline
      path
    end
  end
end
