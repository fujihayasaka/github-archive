# typed: true
# frozen_string_literal: true

# Public: Delete discussions by creating a new DeletedDiscussion record before
# destroying the Discussion record.
class DiscussionDeleter
  extend T::Sig

  attr_reader :discussion

  # Public: Delete all the author's discussions for any repository in the given discussion's organization.
  #
  # actor - the User who is doing the deleting
  # user - the User whose discussions are being deleted
  # owner - the Organization whose discussions are being deleted
  #
  # Returns a Boolean indicating success.
  sig { params(owner: T.untyped, user: T.untyped, actor: T.untyped).returns(T.untyped) }
  def self.delete_all_in_org(owner:, user:, actor:)
    return unless owner.organization?

    DeleteOrgDiscussionsForUserJob.perform_later(organization_id: owner.id, user_id: user.id, actor_id: actor.id)
  end

  sig { params(discussion: T.untyped).void }
  def initialize(discussion)
    @discussion = discussion
  end

  # Public: Mark the discussion as deleted by the specified user.
  #
  # actor - the User who is doing the deleting
  #
  # Returns a Boolean indicating success.
  sig { params(actor: T.untyped).returns(T.untyped) }
  def delete(actor)
    DeletedDiscussion.transaction do
      deleted_discussion = DeletedDiscussion.create(
        repository: discussion.repository,
        deleted_by: actor,
        number: discussion.number,
        old_discussion_id: discussion.id
      )

      # Set transient 'actor' on the Discussion so that when we destroy it,
      # Hydro and audit log events see the user who did the deletion:
      discussion.actor = actor

      success = deleted_discussion.persisted? && discussion.destroy
      raise ActiveRecord::Rollback unless success
      success
    end
  end
end
