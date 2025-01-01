# typed: true
# frozen_string_literal: true

module Gists
  class CommentComponent < ApplicationComponent
    include AvatarHelper
    include CommentsHelper
    include DiffHelper

    attr_reader :comment, :gist, :render_minimized

    def initialize(comment:, gist:, render_minimized: false)
      @comment = comment
      @gist = gist
      @render_minimized = render_minimized
    end

    def comment_path
      comment.comment_path_url
    end

    def body_html_context
      { viewer: current_user, cap_filter: cap_filter }
    end
  end
end
