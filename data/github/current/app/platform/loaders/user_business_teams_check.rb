# typed: true
# frozen_string_literal: true

# Used to check if a user has any BusinessTeam memberships from given business_team_ids.
#
module Platform
  module Loaders
    class UserBusinessTeamsCheck < Platform::Loader
      def self.load(actor_id, business_team_ids)
        self.for(actor_id).load(business_team_ids)
      end

      def initialize(actor_id)
        @actor_id = actor_id
      end

      def fetch(nested_business_team_ids)
        return {} if @actor_id.blank?

        results = {}

        # Collect all unique business team IDs across all requests for this actor
        all_team_ids = nested_business_team_ids.flatten.uniq

        # Single query to check which teams the actor is a member of
        member_team_ids = if all_team_ids.any?
          ::Ability.direct.where(
            actor_type: "User",
            actor_id: @actor_id,
            subject_type: "BusinessTeam",
            subject_id: all_team_ids
          ).pluck(:subject_id)
        else
          []
        end

        # Compile results for each nested request
        nested_business_team_ids.each do |business_team_ids|
          # Check if actor is member of ANY team in this request
          has_membership = (Array(business_team_ids) & member_team_ids).any?
          results[business_team_ids] = has_membership
        end

        results
      end
    end
  end
end
