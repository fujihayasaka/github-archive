# typed: true
# frozen_string_literal: true

module Issue::DiscussionsDependency
  extend T::Helpers
  extend T::Sig

  requires_ancestor { Issue }

  # Public: This is not a Discussion. Useful for partials or helpers that can accept Issues, PullRequests, or
  # Discussions.
  sig { returns FalseClass }
  def discussion?
    false
  end

  # Public: Returns the related Discussion if this Issue was converted to a Discussion.
  # Note: Technically this and the async_discussion could have been replaced with a has_one :discussion
  # on Issue.  Adding the has_one association was tested but caused some issues with how we have programmed to this
  # Issue -> Discussion "association".  The issues seemed to be around how ActiveRecord was caching the
  # loaded association breaking our Discussion builders and converters.  Refer to this issue or linked pr for
  # more context: https://github.com/github/communities/issues/1690
  sig { returns T.nilable(Discussion) }
  def discussion
    async_discussion.sync
  end

  # Public: Returns the a promise to get the related Discussion if this Issue was converted to a Discussion.
  sig { returns Promise[T.nilable(Discussion)] }
  def async_discussion
    return Promise.resolve(T.let(nil, T.nilable(Discussion))) unless persisted?

    Platform::Loaders::ActiveRecord.load(::Discussion, id, column: :issue_id).then do |discussion|
      discussion
    end
  end

  # Public: Determine whether this Issue is eligible to be converted to a Discussion.
  sig { returns T::Boolean }
  def can_be_converted_to_discussion?
    async_can_be_converted_to_discussion?.sync
  end

  # Public: Asynchronously determine whether this Issue is eligible to be converted to a Discussion.
  sig { returns Promise[T::Boolean] }
  def async_can_be_converted_to_discussion?
    async_pull_request?.then do
      # Pull requests can't be converted, only issues
      next false if pull_request?

      async_discussion.then do
        # Already in the process of converting this Issue to a Discussion
        next false if discussion

        async_is_transfer_in_progress?.then do |transfer_in_progress|
          # Issue transfer is in progress (this issue shouldn't be converted until it is done)
          !transfer_in_progress
        end
      end
    end
  end

  # Public: Determine whether this Issue can be converted to a Discussion by the specified user.
  #
  # actor - the current authenticated User
  #
  # Returns a Boolean.
  sig { params(actor: T.untyped).returns(T.untyped) }
  def can_be_converted_by?(actor)
    async_can_be_converted_by?(actor).sync
  end

  # Public: Asynchronously determine whether this Issue can be converted to a Discussion by the specified user.
  #
  # actor - the current authenticated User
  #
  # Returns a Boolean.
  sig { params(actor: T.untyped).returns(T.untyped) }
  def async_can_be_converted_by?(actor)
    Promise.all([
      async_pull_request?,
      async_repository,
      async_user
    ]).then do |is_pull_request, repository, user|
      # Pull requests can't be converted, only issues
      # This check is already part of can_be_converted_to_discussion? but for some reason
      # This is impacting p99 latency for issues if we just call can_be_converted_to_discussion first here
      next false if is_pull_request

      promises = [
        # Ensure this issue is eligible to be converted to a discussion
        async_can_be_converted_to_discussion?,

        repository ? repository.async_can_convert_issues_to_discussions?(actor) : Promise.resolve(false),

        # User must be able to close this issue or the conversion can't begin
        async_closable_by?(actor),

        # If the issue author has blocked this user, don't let them convert it
        user ? actor.async_blocked_by?(user) : Promise.resolve(false)
      ]

      Promise.all(promises).then do |can_be_converted, actor_can_convert, closable, blocked_by|
        can_be_converted && actor_can_convert && closable && !blocked_by
      end
    end
  end

  # Public: Marks this issue as converted to a discussion, which creates an
  #         issue event and updates the state to closed.
  #
  # Returns a Boolean.
  sig { params(actor: T.untyped).returns(T.untyped) }
  def mark_as_converted_to_discussion(actor:)
    return false unless actor.present?
    return false unless converted_discussion = discussion
    success = T.let(false, T::Boolean)

    IssueEvent.transaction do
      event = events.build(
        event: "converted_to_discussion",
        subject: converted_discussion,
        actor: actor,
      )
      raise ActiveRecord::Rollback unless event.save

      # Close the issue now that it has been converted
      # If closing failed, rollback the creation of the event
      raise ActiveRecord::Rollback unless closed? || close(actor, create_event: false)

      success = true
    end

    success
  end
end
