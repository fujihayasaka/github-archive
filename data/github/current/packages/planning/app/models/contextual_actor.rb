# typed: true
# frozen_string_literal: true

module ContextualActor
  extend ActiveSupport::Concern

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
