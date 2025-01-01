# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class SponsorsListingFeatureableItem < Platform::Unions::Base
      description "A record that can be featured on a GitHub Sponsors profile."
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      possible_types(
        Objects::User,
        Objects::Repository,
      )
    end
  end
end
