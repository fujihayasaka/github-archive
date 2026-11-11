# typed: true
# frozen_string_literal: true

module ContextualActor
  extend ActiveSupport::Concern

  # Prefill the cached actor for this record so subsequent calls to `#actor`
  # don't issue a `User.find_by(id: GitHub.context[:actor_id])` lookup. This is
  # useful when the same actor is shared across many records (e.g. when
  # touching many `MemexProjectItem`s inside a single job) and you want to
  # resolve the actor once on the replica and reuse it.
  sig { params(actor: User).void }
  def prefill_actor(actor)
    @actor = actor
  end

  private

  # The user who performed the action as set in the GitHub request context. If the context doesn't
  # contain an actor, fallback to the ghost user.
  def actor
    # don't try and `find_by(id: nil)` below if there is no `actor_id` present in the context
    if GitHub.context[:actor_id].nil?
      @actor = User.ghost
    end
    @actor ||= (User.find_by(id: GitHub.context[:actor_id]) || User.ghost)
  end
end
