# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class RepositoryInteractionLimit < Platform::Enums::Base
      description "A repository interaction limit."

      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      value "EXISTING_USERS", "Users that have recently created their account will be unable to interact with the repository.", value: :sockpuppet_disallowed
      value "CONTRIBUTORS_ONLY", "Users that have not previously committed to a repository’s default branch will be unable to interact with the repository.", value: :contributors_only
      value "COLLABORATORS_ONLY", "Users that are not collaborators will not be able to interact with the repository.", value: :collaborators_only
      value "NO_LIMIT", "No interaction limits are enabled.", value: :no_limit
    end
  end
end
