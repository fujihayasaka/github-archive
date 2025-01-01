# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SponsorsListingFeaturedItemFeatureableType < Platform::Enums::Base
      description "The different kinds of records that can be featured on a GitHub Sponsors profile page."

      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      value "REPOSITORY", "A repository owned by the user or organization with the GitHub Sponsors profile.",
        value: "Repository"
      value "USER", "A user who belongs to the organization with the GitHub Sponsors profile.",
        value: "User"
    end
  end
end
