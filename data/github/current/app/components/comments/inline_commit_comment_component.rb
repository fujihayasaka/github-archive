# typed: true
# frozen_string_literal: true

module Comments
  class InlineCommitCommentComponent < ApplicationComponent
    include AvatarHelper
    include CommentsHelper
    include KeyboardShortcutsHelper

    attr_reader :commit_comment, :show_minimized_content, :repository, :dom_id, :new_comment

    # Initiates new `Comments::InlineCommitCommentComponent`.
    #
    #   - commit_comment         - CommitComment instance
    #   - repository             - Repository instance
    #   - show_minimized_content - Boolean, used when rendering minimized comments in their full form.
    #                              Primarily used when a user expands a minimized comment and we load
    #                              it asynchronously via JS
    #   - dom_id                 - String, id attribute for the div element that contains the comment
    #   - new_comment            - Boolean, indicates whether comment already exists
    def initialize(commit_comment:, repository:, show_minimized_content: false, dom_id: nil, new_comment: false)
      @commit_comment = commit_comment
      @show_minimized_content = show_minimized_content
      @repository = repository
      @dom_id ||= comment_dom_id(commit_comment)
      @new_comment = new_comment
    end

    memoize def comment_path
      "/#{repository.name_with_display_owner}/commit_comment/#{commit_comment.id}"
    end

    def inline_comment_path
      "/#{repository.name_with_display_owner}/commit_comment/#{commit_comment.id}?inline=true"
    end

    def comment_href
      "##{dom_id}"
    end

    memoize def permalink_id
      "#{dom_id}-permalink"
    end

    def display_commenter_full_name?
      display_commenter_full_name_enabled_for_org? &&
      repository.viewer_can_see_commenter_full_name?(current_user) &&
      viewer_did_author?
    end

    memoize def viewer_can_see_minimize_button?
      # site admins may be able to minimize, but shouldn't see the option here
      # unless they have push access.
      if viewer_is_site_admin?
        minimizable? && viewer_can_push_to_repo?
      else
        minimizable?
      end
    end

    memoize def viewer_can_see_delete_button?
      # site admins may be able to delete, but shouldn't see the option here
      # unless they have push access.
      if viewer_is_site_admin?
        viewer_can_delete? && viewer_can_push_to_repo?
      else
        viewer_can_delete?
      end
    end

    def viewer_can_block?
      commit_comment.viewer_can_block_from_org?(current_user)
    end

    def viewer_can_unblock?
      commit_comment.viewer_can_unblock_from_org?(current_user)
    end

    memoize def viewer_can_update?
      commit_comment.async_viewer_can_update?(current_user).sync
    end

    memoize def viewer_can_report?
      commit_comment.async_viewer_can_report?(current_user).sync
    end

    memoize def viewer_can_view_in_stafftools?
      viewer_is_site_admin? &&
      !commit_comment.stafftools_url.nil?
    end

    memoize def minimizable?
      commit_comment.async_minimizable_by?(current_user).sync
    end

    memoize def unminimizable?
      commit_comment.async_unminimizable_by?(current_user).sync
    end

    memoize def minimized?
      commit_comment.minimized?
    end

    memoize def created_via_email?
      commit_comment.created_via_email
    end

    memoize def update_resource_path
      commit_comment.async_update_path_uri.sync&.to_s
    end

    memoize def display_dropdown_divider?
      (!archived? && viewer_can_update?) || viewer_can_see_minimize_button? || viewer_can_see_delete_button?
    end

    def show_abuse_reports?
      viewer_is_site_admin? && !commit_comment.report_count.nil? && commit_comment.report_count.positive?
    end

    memoize def viewer_did_author?
      commit_comment.user_id == current_user&.id
    end

    def authored_by_subject_author?
      commit_comment.commit.async_authors.then do |authors|
        authors.map(&:id).include?(commit_comment.user_id)
      end.sync
    end

    def abuse_tooltip
      abuse_report_tooltip(commit_comment.report_count, commit_comment.top_report_reason, commit_comment.last_reported_at)
    end

    def review_comment_classes
      if minimized? && show_minimized_content
        "border-top pt-3"
      else
        "js-minimize-container"
      end
    end

    def previewable_comment_classes
      classes = %w{previewable-edit js-suggested-changes-container js-task-list-container unminimized-comment}
      classes << "js-comment" unless minimized?
      classes << "d-none" if minimized? && !show_minimized_content
      if viewer_did_author?
        classes << "current-user"
      else
        # unread_comment_class defined at app/helpers/discussions_helper.rb
        classes << helpers.unread_comment_class
      end
      classes << "reorderable-task-lists" if logged_in?

      classes.join(" ")
    end

    def minimized_test_selector
      "#{commit_comment.id}-minimized"
    end

    def author_login
      author&.display_login || GitHub.ghost_user_login
    end

    memoize def author
      commit_comment.user
    end

    def view_in_stafftools_text
      GitHub.enterprise? ? "Site Admin" : "Stafftools"
    end

    def viewer_relationship
      commit_comment.async_viewer_relationship(current_user).sync
    end

    def last_edited_at
      commit_comment.async_latest_user_content_edit.then do |user_content_edit|
        user_content_edit&.edited_at
      end.sync
    end

    memoize def available_emotions
      commit_comment.respond_to?(:emotions) ? commit_comment.emotions : commit_comment.class.emotions
    end

    def archived?
      repository.archived?
    end

    private

    memoize def organization
      repository.organization
    end

    memoize def viewer_can_delete?
      commit_comment.async_viewer_can_delete?(current_user).sync
    end

    memoize def viewer_can_push_to_repo?
      repository.pushable_by?(current_user)
    end

    def display_commenter_full_name_enabled_for_org?
      organization&.display_commenter_full_name_setting_enabled?
    end

    def published_at
      commit_comment.created_at
    end

    memoize def viewer_is_site_admin?
      current_user&.site_admin?
    end
  end
end
