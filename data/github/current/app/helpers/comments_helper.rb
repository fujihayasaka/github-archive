# typed: true
# frozen_string_literal: true

module CommentsHelper
  include PlatformHelper
  include ActionView::Helpers::DateHelper

  DISCUSSION_DOM_ID_PREFIX = "discussion_r"
  COMMIT_COMMENT_DOM_ID_PREFIX = "r"

  def comment_dom_id(comment)
    id = comment.id || comment.object_id
    return "#{DISCUSSION_DOM_ID_PREFIX}#{id}" if comment.is_a?(PullRequestReviewComment)
    return "#{COMMIT_COMMENT_DOM_ID_PREFIX}#{id}" if comment.is_a?(CommitComment)

    "#{comment.class.name.downcase}-#{id}"
  end

  def emoji_suggestions_cache_key(use_colon_emoji:, tone:)
    base_key = "emoji-suggestions:aliases:v19:#{tone || 0}"
    use_colon_emoji ? base_key + ":use_colon_emoji" : base_key
  end

  def allows_suggested_changes(opts = {})
    opts.fetch(:allows_suggested_changes) do
      next false if defined?(specified_tab) && T.unsafe(self).specified_tab != "files"
      @pull && !@pull.new_record? && @pull.open? && @pull.head_ref_exist?
    end
  end

  # Can the current viewer open a new issue that references the given comment?
  #
  # comment - A comment-like object, one of the following types:
  #         - RepositoryAdvisory::Adapter::CommentAdapter
  #         - CommitComment
  #         - Issue
  #         - IssueComment
  #         - Issue::Adapter::CommentAdapter
  #         - Issue::Adapter::IssueAdapter
  #         - PullRequest
  #         - PullRequestReview
  #         - PullRequestReviewComment
  #         - RepositoryAdvisoryComment
  #
  # minimized_view (optional) - Boolean for whether the comment is currently being
  #                             rendered in a minimized comment view
  #
  # Returns Boolean
  def can_reference_in_new_issue?(comment, minimized_view: false)
    T.bind(self, T.untyped)
    return false if minimized_view
    return false unless logged_in?
    return false if comment.is_a?(Issue) || comment.is_a?(PlatformTypes::Issue)
    return false if comment.is_a?(RepositoryAdvisoryComment) || comment.is_a?(RepositoryAdvisory::Adapter::CommentAdapter)

    comment.repository.has_issues?
  end

  def blocked_from_commenting?(obj)
    T.bind(self, T.untyped)
    current_repository.blocked_from_commenting?(user: current_user, commentable: obj)
  end

  def blocked_notification_html(org_login, org_email, content_url, coc_url)
    T.bind(self, T.untyped)
    notification = ["A maintainer of the "]
    notification << content_tag(:b, "@#{org_login}")
    notification << " organization has blocked you because of "
    if content_url.present?
      notification << link_to("this content", content_url.to_s)
    else
      notification << "a recent post"
    end
    notification << "."

    info = []

    notification << " For more information please see "

    if coc_url
      info << link_to("the code of conduct", coc_url.to_s)
    else
      info << link_to("the community guidelines", "#{GitHub.help_url}/articles/github-community-guidelines")
    end

    unless org_email.blank?
      contact = ["contact the maintainer at "]
      contact << mail_to(org_email)

      info << safe_join(contact)
    end

    # We have used safe_join above for all these lines
    # html_safe is fine here
    notification << info.to_sentence(two_words_connector: " or ", last_word_connector: ", or ").html_safe # rubocop:disable Rails/OutputSafety
    notification << "."

    safe_join(notification)
  end

  def minimize_reasons_for_select
    if GitHub.enterprise?
      ghe_reasons = Platform::Enums::ReportedContentClassifiers.values.select do |_k, v|
        T.unsafe(v).environment_visibilities[:enterprise].any?
      end
      minimize_reasons = ghe_reasons.keys
    else
      minimize_reasons = Platform::Enums::ReportedContentClassifiers.graphql_values
    end
    minimize_reasons.map { |s| [s.titleize, s] }
  end

  def abuse_report_tooltip(reports_count, report_reason, last_reported)
    T.bind(self, T.untyped)
    if report_reason.blank?
      "#{pluralize(reports_count, "user")} reported #{time_ago_in_words(last_reported)} ago"
    else
      "#{pluralize(reports_count, "user")} reported as #{report_reason} #{time_ago_in_words(last_reported)} ago"
    end
  end

  # A list of reactions the viewer has reacted to
  #
  # Returns Array (ex. ["heart", "smile"])
  def viewer_reactions(comment)
    T.bind(self, T.untyped)
    return [] unless logged_in?

    comment.prelude_user_logins_by_reaction.filter_map do |content, user_logins|
      content if user_logins.include?(current_user.login)
    end
  end

  def reaction_popover_class(popover_direction)
    popover_offset = ""

    case popover_direction
    when "sw"
      popover_offset = "mr-n1 mt-n1"
    when "ne"
      popover_offset = "mb-0"
    end

    "dropdown-menu-#{popover_direction} #{popover_offset}"
  end

  # Builds url for fetching markup for the comment header action menu.
  #
  # comment - An ActiveRecord object that implements the UserContentEditable interface, or Adapter object that
  #           implements the PlatformTypes::UpdatableComment interface
  # permalink - String permalink for the comment, ex. "#issue-comment-1"
  #
  # TODO @ktravers: add shared interface to comment objects (Adapters and ActiveRecord models) so we can
  # call `comment#action_menu_path` instead of manually building the string here
  #
  # Returns String url
  # ex. "/monalisa/smile/issue_comments/1/comment_actions_menu?href=%23issuecomment-1&gid=IC_123abc"
  def comment_header_action_menu_path(comment, permalink:)
    T.bind(self, T.untyped)
    database_id = comment.respond_to?(:database_id) ? comment.database_id : comment.id

    params = {
      # By default, the `id` param should correspond to the comment's database id. There are two exceptions, Issue
      # and RepositoryAdvisoryComment types, where the `id` param is used to look up the comment's subject instead.
      # That value is reset in the case statement below when needed.
      id: database_id,
      gid: comment.global_relay_id,
      href: permalink,
      repository: comment.repository.name,
      user_id: comment.repository.owner_login,
    }
    params[:minimized] = 1 if comment.respond_to?(:minimized?) && comment.minimized?

    if comment.is_a?(Issue) || comment.is_a?(PlatformTypes::Issue)
      params[:id] = comment.number
      actions_menu_path(params)
    elsif comment.is_a?(CommitComment) || comment.is_a?(PlatformTypes::CommitComment)
      commit_comment_actions_menu_path(params)
    elsif comment.is_a?(RepositoryAdvisoryComment) || comment.is_a?(RepositoryAdvisory::Adapter::CommentAdapter)
      params[:id] = comment.advisory_ghsa_id
      params[:comment_id] = database_id
      repository_advisory_comment_actions_menu_path(params)
    else
      issue_comment_actions_menu_path(params)
    end
  end
end
