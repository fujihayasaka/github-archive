# typed: true
# frozen_string_literal: true

# Mixin for models that may be upvoted, like Discussions and DiscussionComments. Provides default
# implementations for the fields in the GraphQL Votable interface (see app/platform/interfaces/votable.rb).
module Votable
  extend T::Helpers

  requires_ancestor { Kernel }

  # Prerequisites:
  # - Model must implement #upvotes scopes.
  # - Model must have a #votes relation to its votes
  # - Model must have a #user relation to its author
  # - Model must have a #repository relation to its owning Repository.

  # Public: Asynchronously load the unique Vote (up or down) performed by an Actor against this subject or `nil` if
  # there is none.
  #
  # actor - a User or Bot
  #
  # Returns a Promise that resolves to an ActiveRecord vote model if one is found, or `nil` otherwise.
  sig { params(actor: T.untyped).returns(T.untyped) }
  def async_vote_for(actor)
    Platform::Loaders::VoteForUser.load(self, actor.id)
  end

  # Public: Asynchronously determine whether or not an actor is permitted to attempt to upvote this subject. Considers
  # access issues (email verification, repository access, interaction limits) but not whether or not an upvote already
  # exists.
  #
  # actor - a User or Bot or Mannequin
  # interaction_allowed - Optionally used to short-circuit the repository interaction check. If `nil`, the interaction
  #   check will be performed asynchronously during this call; if `true` or `false` are specified, the interaction
  #   check will be skipped and the provided value will be used instead.
  #
  # Returns a Promise that resolves to either true or false.
  sig { params(actor: T.untyped, interaction_allowed: T.untyped).returns(T.untyped) }
  def async_upvotable_by?(actor, interaction_allowed: nil)
    return Promise.resolve(true) if actor.mannequin?

    return Promise.resolve(false) if actor.bot? || actor.spammy? || actor.suspended? || actor.should_verify_email?

    return Promise.resolve(false) unless respond_to?(:async_reactable_by?)

    T.unsafe(self).async_reactable_by?(actor, interaction_allowed: interaction_allowed)
  end

  # Public: Asynchronously determine whether or not an actor has upvoted this subject.
  #
  # actor - a User or Bot
  #
  # Returns a Promise that resolves to a truthy or falsy value.
  sig { params(actor: T.untyped).returns(T.untyped) }
  def async_has_upvoted?(actor)
    async_vote_for(actor).then { |vote| vote&.upvote? }
  end
end
