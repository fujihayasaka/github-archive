# typed: strict
# frozen_string_literal: true

module Discussions
  class CommentActionsMenuComponent < ApplicationComponent
    extend T::Sig

    include DiscussionsStafftoolsRoutesHelper
    include KeyboardShortcutsHelper

    # org_param - the display_login of the Organization to use in routing, if working with org-level discussions
    sig do
      params(
        timeline: DiscussionTimeline,
        discussion_or_comment: T.any(Discussion, DiscussionComment),
        form_path: String,
        is_comment_minimized: T.nilable(T::Boolean),
        current_repository: Repository,
        org_param: T.nilable(String)
      ).void
    end
    def initialize(
      timeline:,
      discussion_or_comment:,
      form_path:,
      is_comment_minimized:,
      current_repository:,
      org_param: nil
    )
      @timeline = timeline
      @discussion_or_comment = discussion_or_comment
      @form_path = form_path
      @is_comment_minimized = is_comment_minimized
      @current_repository = current_repository
      @org_param = org_param
    end

    sig { returns(DiscussionTimeline) }
    attr_reader :timeline

    sig { returns(T.any(Discussion, DiscussionComment)) }
    attr_reader :discussion_or_comment

    sig { returns(String) }
    attr_reader :form_path

    sig { returns(T.nilable(T::Boolean)) }
    attr_reader :is_comment_minimized

    sig { returns(Repository) }
    attr_reader :current_repository

    private

    sig { returns(T.nilable(String)) }
    attr_reader :org_param

    sig { returns(String) }
    def target_class
      discussion_or_comment.is_a?(Discussion) ? "Discussion" : "Comment"
    end

    sig { returns(T::Boolean) }
    def render_first_divider?
      show_edit_option? || show_hide_comment? || show_delete?
    end

    sig { returns(T::Boolean) }
    def render_second_divider?
      show_report_link? || user_can_report_to_maintainer? || show_block_option?
    end

    sig { returns(T::Boolean) }
    def show_quote_reply?
      discussion_or_comment.body.present?
    end

    sig { returns(T::Boolean) }
    def show_reference_in_new_issue?
      discussion_or_comment.body.present? && timeline.can_open_issue_from_discussion?
    end

    sig { returns(T::Boolean) }
    memoize def show_edit_option?
      !timeline.archived_repo? && (timeline.can_update?(discussion_or_comment) || timeline.show_edit_button_requiring_email_verification?(discussion_or_comment))
    end

    sig { returns(T::Boolean) }
    memoize def show_hide_comment?
      discussion_or_comment.is_a?(DiscussionComment) && timeline.can_toggle_minimize?
    end

    sig { returns(T::Boolean) }
    memoize def show_delete?
      discussion_or_comment.is_a?(DiscussionComment) && timeline.can_delete?(discussion_or_comment)
    end

    sig { returns(T::Boolean) }
    memoize def show_report_link?
      discussion_or_comment.body.present? && timeline.can_report?(discussion_or_comment)
    end

    sig { returns(T::Boolean) }
    memoize def show_block_option?
      user_can_block? || user_can_unblock?
    end

    sig { returns(T::Boolean) }
    def user_can_block?
      timeline.can_block?(discussion_or_comment)
    end

    sig { returns(T::Boolean) }
    def user_can_unblock?
      timeline.can_unblock?(discussion_or_comment)
    end

    sig { returns(T::Boolean) }
    memoize def user_can_report_to_maintainer?
      timeline.can_report_to_maintainer?(discussion_or_comment)
    end

    sig { returns(String) }
    def stafftools_path
      discussion_or_comment = self.discussion_or_comment
      if discussion_or_comment.is_a?(Discussion)
        gh_stafftools_repository_discussion_path(discussion_or_comment)
      else
        gh_stafftools_repository_discussion_comment_path(discussion_or_comment)
      end
    end

    sig { returns(String) }
    def stafftools_link_text
      GitHub.enterprise? ? "Site Admin" : "Stafftools"
    end

    sig { returns(String) }
    def report_to_github_link
      flavored_contact_path(
        flavor: "report-content",
        report: "#{discussion_or_comment.author} (user)",
        content_url: helpers.discussion_timeline_comment_url(discussion_or_comment, org_param: org_param, timeline: timeline),
        timeline: timeline
      )
    end

    sig { returns(String) }
    def comment_to_issue_form_content_path
      if discussion_or_comment.is_a?(Discussion)
        discussion_issue_modal_path(timeline.repo_owner_login, timeline.repo_name, discussion_or_comment)
      else
        open_new_issue_modal_discussion_comment_path(timeline.repo_owner_login, timeline.repo_name,
          timeline.discussion, discussion_or_comment)
      end
    end

    sig { returns(String) }
    def block_from_comment_form_content_path
      discussion_block_from_comment_modal_path(
        timeline.repo_owner_login,
        timeline.repo_name,
        timeline.discussion,
        comment_id: discussion_or_comment.is_a?(Discussion) ? nil : discussion_or_comment.id
      )
    end

    sig { returns(String) }
    def report_content_form_content_path
      discussion_report_content_modal_path(
      timeline.repo_owner_login,
        timeline.repo_name,
        timeline.discussion,
        comment_id: discussion_or_comment.is_a?(Discussion) ? nil : discussion_or_comment.id
      )
    end

    sig { returns(String) }
    def unblock_from_comment_form_content_path
      discussion_unblock_from_comment_modal_path(
        timeline.repo_owner_login,
        timeline.repo_name,
        timeline.discussion,
        comment_id: discussion_or_comment.is_a?(Discussion) ? nil : discussion_or_comment.id
      )
    end

    sig { returns(String) }
    def unminimize_comment_form_content_path
      discussion_comment_unminimize_content_modal_path(
        timeline.repo_owner_login,
        timeline.repo_name,
        timeline.discussion,
        comment_id: discussion_or_comment.id
      )
    end

    sig { returns(String) }
    def minimize_comment_form_content_path
      minimize_form_discussion_comment_path(
        timeline.repo_owner_login,
        timeline.repo_name,
        timeline.discussion,
        discussion_or_comment
      )
    end

    sig { returns(String) }
    def delete_comment_content_form_path
      discussion_comment_delete_content_modal_path(
        timeline.repo_owner_login,
        timeline.repo_name,
        timeline.discussion,
        comment_id: discussion_or_comment.id
      )
    end

    sig { returns(String) }
    def unminimize_comment_content_form_path
      discussion_comment_unminimize_content_modal_path(
        timeline.repo_owner_login,
        timeline.repo_name,
        timeline.discussion,
        comment_id: discussion_or_comment.id
      )
    end
  end
end
