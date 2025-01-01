# typed: true
# frozen_string_literal: true

class DiscussionTimeline::PermissionPreloader
  DELEGATE_PERMISSIONS_TO_DISCUSSION = [:comment, :mark_answer].freeze

  sig do
    params(
      timeline: T.untyped,
      can_interact_with_repo: T.untyped,
      show_stats_name: T.untyped
    ).returns(T.untyped)
  end
  def self.load_for(timeline, can_interact_with_repo:, show_stats_name: :preload_permissions)
    timeline.record_show_stats_distribution(show_stats_name) do
      new(
        discussion: timeline.discussion,
        comments: timeline.all_comments,
        viewer: timeline.viewer,
        can_interact_with_repo: can_interact_with_repo,
        skip_reaction_permissions: timeline.render_reaction_placeholders?
      ).tap do |preloader|
        # Warm up permissions
        # This will help us see bottlenecks/issues in flamegraphs
        preloader.preload

        timeline.permissions_preloader = preloader
      end
    end
  end

  sig do
    params(
      discussion: T.untyped,
      comments: T.untyped,
      viewer: T.untyped,
      can_interact_with_repo: T.untyped,
      skip_reaction_permissions: T.untyped
    ).void
  end
  def initialize(discussion:, comments:, viewer:, can_interact_with_repo:, skip_reaction_permissions: false)
    @discussion = discussion
    @comments = comments
    @viewer = viewer
    @can_interact_with_repo = can_interact_with_repo
    @skip_reaction_permissions = skip_reaction_permissions
  end

  sig { returns(T.untyped) }
  def preload
    return if viewer.nil?
    return if !can_interact? # don't preload if user can't interact

    permissions
  end

  sig { params(action: T.untyped, target: T.untyped).returns(T.untyped) }
  def can?(action, target)
    return false if viewer.nil?
    return false if !can_interact?

    if target.is_a?(Discussion)
      permissions[:discussion][action.to_sym].sync
    elsif target.is_a?(DiscussionComment)
      if action.in? DELEGATE_PERMISSIONS_TO_DISCUSSION
        permissions[:discussion][action.to_sym].sync
      else
        permissions[target.id][action.to_sym].sync
      end
    else
      raise ArgumentError.new("Expected a Discussion or DiscussionComment, was given a #{target.class}")
    end
  end

  # Public: Can the authenticated user interact with the repository the discussion is in at all?
  #
  # Returns a Boolean.
  sig { returns(T::Boolean) }
  def can_interact?
    @can_interact_with_repo
  end

  private

  attr_reader :discussion, :comments, :viewer

  # Collect necessary permissions for the discussion and its comments then
  # perform a single authzd batch request
  def permissions
    @_permissions ||= begin
      permissions = comment_permission_promises
      permissions[:discussion] = discussion_permission_promises

      Promise.all(permissions.values.flat_map(&:values)).sync

      permissions
    end
  end

  def discussion_permission_promises
    mark_answer =
      if discussion.supports_mark_as_answer? && comments.any?
        discussion.async_can_toggle_answer?(viewer)
      else
        Promise.resolve(false)
      end

    react = skip_reaction_permissions? ? Promise.resolve(false) : discussion.async_reactable_by?(viewer)

    {
      lock: discussion.async_lockable_by?(viewer),
      unlock: discussion.async_unlockable_by?(viewer),
      react: react,
      update: discussion.async_modifiable_by?(viewer, skip_interaction_check: true),
      comment: discussion.async_can_comment?(viewer),
      mark_answer: mark_answer,
      delete: discussion.async_deletable_by?(viewer),
      edit_labels: discussion.async_labelable_by?(viewer),
      close: discussion.async_closable_by?(viewer),
      reopen: discussion.async_reopenable_by?(viewer),
      edit_category: discussion.async_category_modifiable_by?(viewer),
      # Discussion exclusive permissions
      manage_spotlights: viewer ? viewer.async_can_manage_discussion_spotlights?(discussion.repository) : Promise.resolve(false) # maybe move to user perms?
    }
  end

  def comment_permission_promises
    @comments.map do |comment|
      permissions = {
        react: skip_reaction_permissions? ? Promise.resolve(false) : comment.async_reactable_by?(viewer),
      }

      [comment.id, permissions]
    end.to_h
  end

  def skip_reaction_permissions?
    @skip_reaction_permissions
  end
end
