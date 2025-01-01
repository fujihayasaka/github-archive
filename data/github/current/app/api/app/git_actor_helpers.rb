# typed: false
# frozen_string_literal: true

module Api::App::GitActorHelpers

  # Internal: Attempt to extract a GitActor from the given request body.
  #
  # body         - A Hash representing the contents of the request body.
  # key          - The String name of the key in the body Hash that is expected
  #                to contain information describing a committer, author, or
  #                tagger.
  # default_time - The String time (in ISO 8601 format) to use for the Git actor
  #                if hash does not include time data (optional).
  #
  # Halts with a 422 if the given hash contains invalid actor data.
  # Returns a GitActor.
  def git_actor!(body, key:, default_time: nil)
    actor = git_actor(body[key], default_time: default_time)

    unless actor.valid?
      deliver_error! 422, resource: key, errors: actor.errors
    end

    actor
  end

  # Internal: Construct a GitActor from API request input.
  #
  # actor_hash   - A Hash containing an API request representation for a
  #                committer, author, or tagger.
  # default_time - The String time (in ISO 8601 format) to use for the Git actor
  #                if actor_hash does not include time data (optional).
  #
  # Returns a GitActor.
  def git_actor(actor_hash, default_time: nil)
    GitActor.new(
      name: actor_hash.fetch("name"),
      email: actor_hash.fetch("email"),
      time: actor_hash.fetch("date", default_time),
    )
  end
end
