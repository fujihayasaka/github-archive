# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class SponsorsGoal < Platform::Objects::Base
      description "A goal associated with a GitHub Sponsors listing, representing a target " \
        "the sponsored maintainer would like to attain."

      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, goal)
        goal.async_sponsorable.then do |sponsorable|
          org = sponsorable.organization? ? sponsorable : nil
          permission.access_allowed?(:read_sponsors_goal,
            resource: sponsorable,
            sponsors_goal: goal,
            current_org: org,
            current_repo: nil,
            allow_integrations: false,
            allow_user_via_granular_actor: false,
          )
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      # Ability check for a SponsorsTier object
      #
      # Adapted from MarketplaceListingPlan GraphQL object.
      def self.async_viewer_can_see?(permission, object)
        object.async_readable_by?(permission.viewer)
      end

      minimum_accepted_scopes ["read:user", "read:org"]

      field :kind, Enums::SponsorsGoalKind,
        description: "What the objective of this goal is.", null: false

      field :target_value, Integer,
        description: "What the goal amount is. Represents an amount in USD for monthly " \
          "sponsorship amount goals. Represents a count of unique sponsors for total " \
          "sponsors count goals.", null: false

      field :title, String, "A brief summary of the kind and target value of this goal.",
        null: false

      field :description, String, "A description of the goal from the maintainer.", null: true

      field :percent_complete, Integer,
        "The percentage representing how complete this goal is, between 0-100.", null: false
    end
  end
end
