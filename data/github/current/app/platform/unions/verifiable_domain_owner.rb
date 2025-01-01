# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class VerifiableDomainOwner < Platform::Unions::Base
      description "Types that can own a verifiable domain."

      visibility :public, environments: [:enterprise, :dotcom]

      possible_types(
        Objects::Enterprise,
        Objects::Organization,
      )
    end
  end
end
