# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class SponsorableItem < Platform::Unions::Base
      description "Entities that can be sponsored via GitHub Sponsors"
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      possible_types(
        Objects::User,
        Objects::Organization,
      )
    end
  end
end
