# typed: true
# frozen_string_literal: true

# Public: Represents a single discussion page in a repository. Used to memoize and batch load
# necessary checks and relations for rendering the discussion page.
class DiscussionTimeline
  DEFAULT_MAX_NUMBER_OF_NESTED_COMMENTS_TO_RENDER = 300
  DEFAULT_INITIAL_REPLY_COUNT = 5
  LIMITED_NUMBER_OF_NESTED_COMMENTS = 3
  ANSWER_PREVIEW_CHARACTER_LIMIT = 700
  DEFAULT_ITEMS_PER_PAGE = 30
  ITEMS_PER_PAGE_KEY = "discussion-timeline-items-per-page"
  PAGINATED_EVENTS_LIMIT = 7
  NEW_MARKER = :new_marker
  UNREAD_MARKER = :unread_marker
  TIMELINE_HEADER = :timeline_header

  include GitHub::Memoizer
  include FeatureFlagHelper

  attr_reader :updated_at
  attr_writer :votes_preloader
  attr_accessor :permissions_preloader

  delegate :discussion, :repository, :viewer, :renderables, :reply_threads_by_parent_id, :sort, :events,
    :has_paginated_events?, :last_read_at, :new_item_count, :new_item_noun, :will_render_new_marker?,
    :blocked_from_commenting?, :show_stats, :viewer_can_push?, to: :render_context

  delegate :in_organization?, to: :repository

  sig { params(discussion: T.untyped).returns(T.untyped) }
  def self.last_modified_at_for(discussion:)
    [
      discussion.created_at,
      discussion.comments.last&.created_at,
      discussion.last_event&.created_at,
    ].compact.max
  end

  # Efficiently preload nested relations for Discussion/DiscussionComment objects
  # that are rendered. This includes avatars and owners of Integrations linked
  # via :performed_via_integration or Bot authorship.
  #
  # Returns records.
  sig { params(records: T.untyped).returns(T.untyped) }
  def self.preload_for_display(records)
    GitHub::PrefillAssociations.prefill_associations(records, [:user, :performed_via_integration])

    bots = records.filter_map { |record| record.user if record.user&.bot? }
    GitHub::PrefillAssociations.prefill_associations(bots, [:integration])

    integrations = records.filter_map do |record|
      record.user&.bot? ? record.user.integration : record.performed_via_integration
    end
    GitHub::PrefillAssociations.prefill_associations(integrations, [:owner])
    Promise.all(integrations.map(&:async_primary_avatar)).sync

    records
  end

  sig { params(render_context: T.untyped, author_role_preloader: T.untyped).void }
  def initialize(render_context:, author_role_preloader: nil)
    @render_context = render_context
    @updated_at = Time.zone.now
    @author_role_preloader = author_role_preloader
  end

  sig { returns(T.untyped) }
  memoize def last_modified_at
    self.class.last_modified_at_for(discussion: discussion)
  end

  sig { returns(T.untyped) }
  memoize def chosen_comment_selected_by_user
    discussion.chosen_comment_selected_by_user
  end

  sig { params(name: T.untyped, block: T.untyped).returns(T.untyped) }
  def record_show_stats_distribution(name, &block)
    show_stats.record_distribution(name, &block)
  end

  sig { params(renderable_name: T.untyped, block: T.untyped).returns(T.untyped) }
  def record_show_stats_render(renderable_name, &block)
    show_stats.record_render(renderable_name, &block)
  end

  # Public: Is the given comment ID the ID of the first comment on the page that
  # the viewer could mark as the answer?
  #
  # comment_id - DiscussionComment ID, integer
  #
  # Returns a Boolean.
  sig { params(comment_id: T.untyped).returns(T.untyped) }
  def is_first_comment_markable_as_answer_on_the_page?(comment_id)
    target_comment = first_comment_that_could_be_marked_as_answer
    return false unless target_comment
    comment_id == target_comment.id
  end

  sig { params(discussion_event: T.untyped).returns(T.untyped) }
  def old_repository_for_transfer_event(discussion_event)
    old_repositories_for_transfer_events_by_event_id[discussion_event.id]
  end

  sig { returns(T.untyped) }
  def answered?
    discussion.answered?
  end

  sig { returns(T.untyped) }
  def discussion_number
    discussion.number
  end

  sig { returns(T.untyped) }
  memoize def locked_discussion?
    discussion.locked_for?(viewer)
  end

  sig { returns(T.untyped) }
  memoize def can_transfer_discussion?
    discussion.transferrable_by?(viewer, modifiable_by_actor: can_update_discussion?)
  end

  sig { params(discussion_or_comment: T.untyped).returns(T.untyped) }
  def last_reported_at_for(discussion_or_comment)
    if discussion_or_comment.is_a?(Discussion)
      last_reported_at_for_discussion
    else
      last_reported_at_by_comment_id[discussion_or_comment.id]
    end
  end

  sig { params(discussion_or_comment: T.untyped).returns(T.untyped) }
  def top_report_reason_for(discussion_or_comment)
    if discussion_or_comment.is_a?(Discussion)
      top_report_reason_for_discussion
    else
      top_report_reason_by_comment_id[discussion_or_comment.id]
    end
  end

  sig { params(discussion_or_comment: T.untyped).returns(T.untyped) }
  def report_count_for(discussion_or_comment)
    if discussion_or_comment.is_a?(Discussion)
      report_count_for_discussion
    else
      report_count_by_comment_id[discussion_or_comment.id]
    end
  end

  sig { params(discussion_or_comment: T.untyped).returns(T.untyped) }
  def last_edited_at_for(discussion_or_comment)
    latest_edit_for(discussion_or_comment)&.edited_at
  end

  sig { params(discussion_or_comment: T.untyped).returns(T.untyped) }
  def latest_edit_for(discussion_or_comment)
    if discussion_or_comment.is_a?(Discussion)
      latest_edit_for_discussion
    else
      latest_edit_by_comment_id[discussion_or_comment.id]
    end
  end

  sig { params(discussion_or_comment: T.untyped).returns(T.untyped) }
  def body_html_for(discussion_or_comment)
    body_html_by_record[discussion_or_comment]
  end

  sig { params(show_stats_name: T.untyped).returns(T.untyped) }
  def preload_body_html(show_stats_name: :preload_body_html)
    record_show_stats_distribution(show_stats_name) { body_html_by_record }
  end

  sig { params(show_stats_name: T.untyped).returns(T.untyped) }
  def preload_comments(show_stats_name: :preload_comments)
    record_show_stats_distribution(show_stats_name) do
      all_comments_with_discussion.tap { |records| self.class.preload_for_display(records) }
    end
  end

  sig { params(show_stats_name: T.untyped).returns(T.untyped) }
  def preload_labels(show_stats_name: :preload_labels)
    record_show_stats_distribution(show_stats_name) { discussion.labels.load }
  end

  sig { returns(T.untyped) }
  memoize def can_mark_answer?
    return permissions_preloader.can?(:mark_answer, discussion) if permissions_preloader

    logged_in? && supports_mark_as_answer? &&
      DiscussionComment.can_toggle_answer_in_discussion?(discussion, actor: viewer)
  end

  sig { params(comment: T.untyped).returns(T.untyped) }
  def render_mark_as_answer?(comment)
    can_mark_answer? && !comment.wiped? && !comment.minimized?
  end

  sig { returns(T.untyped) }
  memoize def supports_mark_as_answer?
    discussion.supports_mark_as_answer?
  end

  sig { params(comment: T.untyped).returns(T.untyped) }
  def can_unmark_as_answer?(comment)
    return false if locked_discussion?
    return false unless logged_in?
    return false unless discussion.chosen_comment_id == comment.id
    return permissions_preloader.can?(:mark_answer, discussion) if permissions_preloader

    return false unless supports_mark_as_answer?
    can_unmark_as_answer_by_comment_id[comment.id]
  end

  sig { params(discussion_or_comment: T.untyped).returns(T.untyped) }
  def show_as_answer?(discussion_or_comment)
    return false unless discussion_or_comment.is_a?(DiscussionComment)
    return false unless supports_mark_as_answer?
    discussion_or_comment.answer?
  end

  # Public: Can the viewer open an issue quoting the text from a discussion or a comment
  #         within the discussion, in the same repository as the discussion?
  sig { returns(T.untyped) }
  memoize def can_open_issue_from_discussion?
    # Anonymous users can't open issues
    return false unless logged_in?
    return false unless repository.has_issues?
    # Discussions with polls can't be converted to issues https://github.com/github/discussions/issues/1770
    return false if discussion.poll.present?
    # If the user isn't enterprised managed, they should be able to open an issue.
    return true unless viewer.is_enterprise_managed?

    # EMUs can only open issues within repos owned by the business they belong to
    repository.enterprise_managed_business == viewer.enterprise_managed_business
  end

  sig { params(discussion_or_comment: T.untyped).returns(T.untyped) }
  def show_edit_button_requiring_email_verification?(discussion_or_comment)
    return false unless viewer_did_author?(discussion_or_comment)
    show_edit_button_requiring_email_verification_for_viewer_authored_discussion_or_comment?
  end

  sig { returns(T.untyped) }
  memoize def can_toggle_minimize?
    logged_in? && DiscussionComment.can_toggle_minimized_discussion_comment?(discussion, actor: viewer)
  end

  # Fetch all child comments that could be rendered on the page. This does not
  # paginate so we can get total visible comment counts for each comment
  # thread.
  sig { returns(T.untyped) }
  memoize def child_comments_by_parent_comment_id
    discussion.comments.filter_spam_for(viewer).where(parent_comment_id: top_level_comments.map(&:id))
      .to_a.group_by(&:parent_comment_id)
  end

  # Returns the number of visible child comments for a given thread. This can't
  # use the `nested_comments_count` counter cache because it counts *all*
  # comments, not *visible* comments.
  sig { params(parent_comment: T.untyped).returns(T.untyped) }
  def total_visible_child_comments_count(parent_comment)
    reply_thread = reply_threads_by_parent_id[parent_comment.id]
    reply_thread&.total_reply_count || 0
  end

  # Returns the number of new child comments for a given thread. This can't
  # use the `nested_comments_count` counter cache because it counts *all*
  # comments, not *visible* comments.
  sig { params(parent_comment: T.untyped, last_read_at: T.untyped).returns(T.untyped) }
  def total_new_child_comments_count(parent_comment, last_read_at)
    thread = reply_threads_by_parent_id[parent_comment.id]
    return 0 unless thread
    thread.count_newer_than(last_read_at)
  end

  sig { params(parent_comment: T.untyped).returns(T.untyped) }
  def total_previous_child_comments_count(parent_comment)
    thread = reply_threads_by_parent_id[parent_comment.id]
    return 0 unless thread
    thread.older_count
  end

  sig { params(parent_comment: T.untyped).returns(T.untyped) }
  def total_next_child_comments_count(parent_comment)
    thread = reply_threads_by_parent_id[parent_comment.id]
    return 0 unless thread
    thread.newer_count
  end

  # Return all child comments for a given top-level comment. This does paginate
  # based on the max number of nested comments we should render as defined in
  # the render context.
  sig { params(parent_comment: T.untyped).returns(T.untyped) }
  def child_comments(parent_comment)
    thread = reply_threads_by_parent_id[parent_comment.id]
    return [] unless thread
    thread.replies
  end

  # Public: Should we show the mark as answer icon that contains the 'mark as
  # answer' UI?
  #
  # discussion_or_comment - a Discussion or DiscussionComment
  #
  # Returns a Boolean.
  sig { params(discussion_or_comment: T.untyped).returns(T.untyped) }
  def show_discussion_mark_answer?(discussion_or_comment)
    return false unless discussion_or_comment.is_a?(DiscussionComment)
    show_as_answer?(discussion_or_comment) || can_unmark_as_answer?(discussion_or_comment) ||
      render_mark_as_answer?(discussion_or_comment)
  end

  sig { returns(T.untyped) }
  def discussion_graphql_id
    discussion.global_relay_id
  end

  sig { params(discussion_or_comment: T.untyped).returns(T.untyped) }
  def display_commenter_full_name?(discussion_or_comment)
    !viewer_did_author?(discussion_or_comment) && show_commenter_full_name?
  end

  sig { returns(T.untyped) }
  memoize def can_comment?
    return permissions_preloader.can?(:comment, discussion) if permissions_preloader
    discussion.can_comment?(viewer)
  end

  sig { params(comment: T.untyped).returns(T.untyped) }
  def can_reply_to_discussion_comment?(comment)
    return false unless comment.is_a?(DiscussionComment) && can_comment?
    return false if locked_discussion? || blocked_from_commenting?
    comment.can_be_commented_on?
  end

  sig { returns(T.untyped) }
  memoize def archived_repo?
    repository.archived?
  end

  sig { returns(T.untyped) }
  memoize def locked_on_migration_repo?
    repository.locked_on_migration?
  end

  sig { returns(T.untyped) }
  def private_repo?
    repository.private?
  end

  sig { returns(T.untyped) }
  def repo_name
    repository.name
  end

  sig { returns(T.untyped) }
  def repo_owner
    repository.owner
  end

  sig { returns(T.untyped) }
  def repo_owner_login
    repository.owner_display_login
  end

  sig { returns(T.untyped) }
  memoize def viewer_relationship_to_discussion
    discussion.async_viewer_relationship(viewer).sync
  end

  sig { params(discussion_or_comment: T.untyped).returns(T.untyped) }
  def can_unblock?(discussion_or_comment)
    return permissions_preloader.can?(:unblock, discussion_or_comment) if permissions_preloader

    if discussion_or_comment.is_a?(Discussion)
      can_unblock_discussion?
    else
      is_unblockable_by_comment_id[discussion_or_comment.id]
    end
  end

  sig { params(discussion_or_comment: T.untyped).returns(T.untyped) }
  def can_block?(discussion_or_comment)
    return permissions_preloader.can?(:block, discussion_or_comment) if permissions_preloader

    if discussion_or_comment.is_a?(Discussion)
      can_block_discussion?
    else
      is_blockable_by_comment_id[discussion_or_comment.id]
    end
  end

  # TODO migrate permissions
  sig { params(discussion_or_comment: T.untyped).returns(T.untyped) }
  def can_report_to_maintainer?(discussion_or_comment)
    if discussion_or_comment.is_a?(Discussion)
      can_report_discussion_to_maintainer?
    else
      is_reportable_to_maintainer_by_comment_id[discussion_or_comment.id]
    end
  end

  sig { params(discussion_or_comment: T.untyped).returns(T.untyped) }
  def can_report?(discussion_or_comment)
    return permissions_preloader.can?(:report, discussion_or_comment) if permissions_preloader

    if discussion_or_comment.is_a?(Discussion)
      can_report_discussion?
    else
      is_reportable_by_comment_id[discussion_or_comment.id]
    end
  end

  sig { params(discussion_or_comment: T.untyped).returns(T.untyped) }
  def can_delete?(discussion_or_comment)
    return permissions_preloader.can?(:delete, discussion_or_comment) if permissions_preloader

    if discussion_or_comment.is_a?(Discussion)
      # n.b. this method doesn't exist and is never called
      can_delete_discussion?
    else
      discussion_or_comment.deletable_by?(viewer)
    end
  end

  sig { params(discussion_or_comment: T.untyped).returns(T.untyped) }
  def can_update?(discussion_or_comment)
    return permissions_preloader.can?(:update, discussion_or_comment) if permissions_preloader

    if discussion_or_comment.is_a?(Discussion)
      can_update_discussion?
    else
      discussion_or_comment.modifiable_by?(viewer)
    end
  end

  sig { returns(T.untyped) }
  memoize def can_manage_spotlights?
    return permissions_preloader.can?(:manage_spotlights, discussion) if permissions_preloader
    viewer&.can_manage_discussion_spotlights?(repository)
  end

  # For now managing category pins piggybacks off of managing spotlights
  sig { returns(T.untyped) }
  memoize def can_manage_category_pins?
    can_manage_spotlights?
  end

  sig { returns(T.untyped) }
  memoize def pinned?
    DiscussionCategoryPin.where(discussion: discussion).exists?
  end

  sig { returns(T.untyped) }
  memoize def can_update_discussion?
    return permissions_preloader.can?(:update, discussion) if permissions_preloader
    discussion.modifiable_by?(viewer)
  end

  sig { returns(T.untyped) }
  memoize def can_edit_category?
    return permissions_preloader.can?(:edit_category, discussion) if permissions_preloader
    discussion.category_modifiable_by?(viewer)
  end

  sig { returns(T.untyped) }
  memoize def can_edit_labels?
    return permissions_preloader.can?(:edit_labels, discussion) if permissions_preloader
    discussion.labelable_by?(viewer)
  end

  sig { params(discussion_or_comment: T.untyped).returns(T.untyped) }
  def viewer_did_author?(discussion_or_comment)
    logged_in? && discussion_or_comment.user == viewer
  end

  sig { params(author_id: T.untyped).returns(T.untyped) }
  def author_is_sponsor?(author_id)
    return false unless GitHub.sponsors_enabled?
    sponsor_status_by_user_id[author_id]
  end

  sig { params(discussion_or_comment: T.untyped).returns(T.untyped) }
  def authored_by_subject_author?(discussion_or_comment)
    discussion_or_comment.is_a?(DiscussionComment) && discussion.user_id == discussion_or_comment.user_id
  end

  sig { params(discussion_or_comment: T.untyped).returns(T.untyped) }
  def can_react?(discussion_or_comment)
    return false if archived_repo?
    return permissions_preloader.can?(:react, discussion_or_comment) if permissions_preloader

    if discussion_or_comment.is_a?(Discussion)
      can_react_to_discussion?
    else
      can_react_to_comment_by_comment_id[discussion_or_comment.id]
    end
  end

  sig { params(discussion_or_comment: T.untyped).returns(T.untyped) }
  def reaction_groups(discussion_or_comment)
    if discussion_or_comment.is_a?(Discussion)
      discussion_reaction_groups
    else
      reaction_groups_by_comment_id[discussion_or_comment.id]
    end
  end

  sig { params(discussion_or_comment: T.untyped).returns(T.untyped) }
  def fast_reactions_for(discussion_or_comment)
    if discussion_or_comment.is_a?(Discussion)
      fast_discussion_reactions
    else
      fast_discussion_comment_reactions_by_comment_id[discussion_or_comment.id] || {}
    end
  end

  sig { returns(T.untyped) }
  def all_timeline_items
    render_context.timeline_items
  end

  sig { params(discussion_or_comment: T.untyped).returns(T.untyped) }
  def action_or_role_level_for(discussion_or_comment)
    author_role_preloader.action_or_role_level_for(discussion_or_comment)
  end

  sig { returns(T.untyped) }
  def render_with_voltron?
    render_context.render_with_voltron?
  end

  sig { returns(T.untyped) }
  def render_reaction_placeholders?
    render_context.render_reaction_placeholders?
  end
  alias_method :render_voting_placeholders?, :render_reaction_placeholders?
  alias_method :render_badge_placeholders?, :render_reaction_placeholders?

  sig { returns(T.untyped) }
  memoize def all_comments
    child_comments = top_level_comments.flat_map do |top_level_comment|
      # We want to use `child_comments` here since that includes pagination
      # logic so we only return the child comments we will actually render on
      # the page.
      child_comments(top_level_comment)
    end

    child_comments.each do |child_comment|
      # Share the repository instance between parent and child comments
      child_comment.repository = repository
    end

    top_level_comments + child_comments
  end

  sig { returns(T.untyped) }
  memoize def all_comments_with_discussion
    result = all_comments.dup
    result << discussion if render_context.render_discussion?
    result
  end

  sig { params(discussion_or_comment: T.untyped).returns(T.untyped) }
  def vote_for(discussion_or_comment)
    votes_preloader.vote_for(discussion_or_comment)
  end

  sig { returns(T.untyped) }
  memoize def max_number_of_nested_comments_to_render
    render_context.try(:max_number_of_nested_comments) || DEFAULT_MAX_NUMBER_OF_NESTED_COMMENTS_TO_RENDER
  end

  sig { returns(T.untyped) }
  memoize def can_lock_discussion?
    return permissions_preloader.can?(:lock, discussion) if permissions_preloader
    discussion.lockable_by?(viewer)
  end

  sig { returns(T.untyped) }
  memoize def can_unlock_discussion?
    return permissions_preloader.can?(:unlock, discussion) if permissions_preloader
    discussion.unlockable_by?(viewer)
  end

  sig { returns(T.untyped) }
  memoize def can_delete_discussion?
    return permissions_preloader.can?(:delete, discussion) if permissions_preloader
    discussion.deletable_by?(viewer)
  end

  sig { returns(T.untyped) }
  memoize def can_close_discussion?
    return permissions_preloader.can?(:close, discussion) if permissions_preloader
    discussion.closable_by?(viewer)
  end

  sig { returns(T.untyped) }
  memoize def can_reopen_discussion?
    return permissions_preloader.can?(:reopen, discussion) if permissions_preloader
    discussion.reopenable_by?(viewer)
  end

  sig { returns(T::Boolean) }
  memoize def can_convert_discussion_to_issue?
    return true unless GitHub.flipper[:restrict_discussions_convert_to_issue].enabled?(repository)
    Issue::PermissionsDependency::repo_triageable_by?(viewer, repository)
  end

  sig { returns(T.untyped) }
  def preload_author_roles
    author_role_preloader.preload
  end

  sig { returns(T.untyped) }
  memoize def top_level_comments
    render_context.timeline_items.select { |item| item.is_a?(DiscussionComment) }
  end

  sig { returns(T.untyped) }
  memoize def selected_answer
    return unless answered?
    discussion.chosen_comment
  end

  sig { returns(T.untyped) }
  def selected_answer_preview_body
    preloaded_body_html[:answer_preview_body]
  end

  sig { returns(T.untyped) }
  memoize def can_interact_with_repo?
    return permissions_preloader.can_interact? if permissions_preloader
    repository.can_be_interacted_with_by?(viewer, user_can_push: viewer_can_push?)
  end

  private

  attr_reader :render_context

  memoize def votes_preloader
    @votes_preloader || VotesPreloader.new(viewer: viewer, discussion: discussion, comments: top_level_comments)
  end

  memoize def show_edit_button_requiring_email_verification_for_viewer_authored_discussion_or_comment?
    viewer.should_verify_email?
  end

  memoize def fast_discussion_reactions
    discussion.reactions.group(:content).pluck(:content, Arel.sql("count(*)")).to_h
  end

  memoize def fast_discussion_comment_reactions_by_comment_id
    comment_ids_contents_counts = DiscussionCommentReaction.where(discussion_comment_id: all_comments.map(&:id))
      .group(:discussion_comment_id, :content)
      .pluck(:discussion_comment_id, :content, Arel.sql("count(*)"))
    comment_ids_contents_counts.each_with_object({}) do |(comment_id, content, count), hash|
      hash[comment_id] ||= Hash.new({})
      hash[comment_id][content] = count
    end
  end

  memoize def can_unmark_as_answer_by_comment_id
    DiscussionComment.can_unmark_as_answer_by_comment_id(discussion, actor: viewer)
  end

  memoize def old_repositories_for_transfer_events_by_event_id
    DiscussionEvent.old_repositories_for_transfer_events(events: all_transfer_events, viewer: viewer)
  end

  memoize def author_role_preloader
    @author_role_preloader || AuthorRolePreloader.new(rendered_records: all_comments_with_discussion,
      repository: repository)
  end

  def logged_in?
    !viewer.nil?
  end

  memoize def can_unblock_discussion?
    return permissions_preloader.can?(:unblock, discussion) if permissions_preloader
    discussion.viewer_can_unblock_from_org?(viewer)
  end

  memoize def is_unblockable_by_comment_id
    DiscussionComment.unblockable_by_comment_id(discussion, actor: viewer, comments: all_comments)
  end

  memoize def can_block_discussion?
    discussion.viewer_can_block_from_org?(viewer)
  end

  memoize def is_blockable_by_comment_id
    DiscussionComment.blockable_by_comment_id(discussion, actor: viewer, comments: all_comments)
  end

  memoize def can_report_discussion_to_maintainer?
    discussion.async_viewer_can_report_to_maintainer?(viewer).sync
  end

  memoize def is_reportable_to_maintainer_by_comment_id
    DiscussionComment.reportable_to_maintainer_by_comment_id(discussion, actor: viewer, comments: all_comments)
  end

  memoize def can_report_discussion?
    discussion.async_viewer_can_report?(viewer).sync
  end

  memoize def is_reportable_by_comment_id
    DiscussionComment.reportable_by_comment_id(discussion, actor: viewer, comments: all_comments)
  end

  memoize def can_react_to_discussion?
    DiscussionReaction.async_viewer_can_react?(viewer, discussion).sync
  end

  memoize def can_react_to_comment_by_comment_id
    DiscussionComment.can_react_by_comment_id(discussion, actor: viewer, comments: all_comments)
  end

  memoize def show_commenter_full_name?
    if in_organization?
      repo_owner.display_commenter_full_name_for_repo?(visibility: repository.visibility.to_sym, viewer: viewer)
    else
      false
    end
  end

  # Private: Returns a Hash{DiscussionComment|Discussion => String}.
  def body_html_by_record
    preloaded_body_html[:bodies_by_record]
  end

  memoize def latest_edit_for_discussion
    discussion.async_latest_user_content_edit.sync
  end

  memoize def latest_edit_by_comment_id
    DiscussionComment.latest_edit_by_comment_id(discussion, actor: viewer, comments: all_comments)
  end

  memoize def last_reported_at_for_discussion
    discussion.last_reported_at
  end

  memoize def last_reported_at_by_comment_id
    DiscussionComment.last_reported_at_by_comment_id(discussion, actor: viewer)
  end

  memoize def top_report_reason_for_discussion
    discussion.top_report_reason
  end

  memoize def top_report_reason_by_comment_id
    DiscussionComment.top_report_reason_by_comment_id(discussion, actor: viewer)
  end

  memoize def report_count_for_discussion
    discussion.report_count || 0
  end

  memoize def report_count_by_comment_id
    DiscussionComment.report_count_by_comment_id(discussion, actor: viewer, comments: all_comments)
  end

  memoize def discussion_reaction_groups
    discussion.reaction_groups
  end

  memoize def reaction_groups_by_comment_id
    DiscussionComment.reaction_groups_by_comment_id(discussion, actor: viewer, comments: all_comments)
  end

  memoize def all_transfer_events
    render_context.timeline_items.select { |item| item.is_a?(DiscussionEvent) && item.transferred? }
  end

  def comments_that_could_be_marked_as_answers
    all_timeline_items.select do |item|
      item.is_a?(DiscussionComment) && render_mark_as_answer?(item)
    end
  end

  memoize def first_comment_that_could_be_marked_as_answer
    comments_that_could_be_marked_as_answers.first
  end

  memoize def sponsor_status_by_user_id
    sponsor_ids = all_comments_with_discussion.map(&:user_id)
    GitHubSponsors::Public.sponsor_status_by_sponsor_id(sponsor_ids, viewer: viewer,
      sponsorable_id: repository.owner_id)
  end

  memoize def preloaded_body_html
    promise = Promise.all([
      async_all_comments_and_discussion_bodies,
      async_selected_answer_preview_body,
    ]).then do |bodies_by_record, answer_preview_body|
      {
        bodies_by_record: bodies_by_record,
        answer_preview_body: answer_preview_body,
      }
    end
    promise.sync
  end

  def async_all_comments_and_discussion_bodies
    renderer = BodyRenderer.new(all_comments_with_discussion, context: {
      viewer: viewer,
      cap_filter: render_context.cap_filter,
      unfurl_references: true
    })
    renderer.async_body_html_by_record
  end

  def async_selected_answer_preview_body
    return Promise.resolve(nil) unless selected_answer.present?
    selected_answer.async_truncated_body_html(
      ANSWER_PREVIEW_CHARACTER_LIMIT,
      strip_block_elements: false,
      wrap: false,
    )
  end
end
