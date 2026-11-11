# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class RepositoryInteractionLimitOrigin < Platform::Enums::Base
      description "Indicates where an interaction limit is configured."

      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      value "REPOSITORY", "A limit that is configured at the repository level.", value: :repository
      value "ORGANIZATION", "A limit that is configured at the organization level.", value: :organization
      value "USER", "A limit that is configured at the user-wide level.", value: :user
    end
  end
end
