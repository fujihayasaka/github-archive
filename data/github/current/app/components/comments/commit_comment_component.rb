# typed: true
# frozen_string_literal: true

module Comments
  class CommitCommentComponent < ApplicationComponent
    include AvatarHelper
    include CommentsHelper
    include DiffHelper

    attr_reader :commit_comment, :render_minimized, :repository

    def initialize(commit_comment:, repository:, render_minimized: false)
      @commit_comment = commit_comment
      @render_minimized = render_minimized
      @repository = repository
    end

    def commit_link
      commit_url = "/#{repository.name_with_display_owner}/commit/#{commit_comment.commit_id}"
      content_tag(:code, link_to(commit_comment.abbreviated_oid, commit_url, target: "_blank"))
    end

    def comment_path
      "/#{repository.name_with_display_owner}/commit_comment/#{commit_comment.id}"
    end

    def body_html_context
      { viewer: current_user, cap_filter: cap_filter, unfurl_references: true }
    end
  end
end
