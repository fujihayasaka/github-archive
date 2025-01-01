# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UnenrollInToggleableFeature < Platform::Mutations::Base
      description "Enrolls an enrollee into a toggleable feature."

      visibility :under_development
      scopeless_tokens_as_minimum

      argument :enrollee_id, ID, "The Node ID of the enrollee to enroll in the toggleable feature.", required: true, loads: Objects::User
      argument :toggleable_feature_id, ID, "The Node ID of the toggleable feature to be enrolled in.", required: true, loads: Objects::ToggleableFeature

      field :toggleable_feature, Objects::ToggleableFeature, "The toggleable feature", null: true
      field :enrollee, Objects::User, "The user toggling the feature", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        permission.hidden_from_public?(self)
      end

      def resolve(enrollee:, toggleable_feature:, **inputs)
        unless toggleable_feature.can_enroll?(enroller: context[:viewer], enrollee: enrollee)
          raise Errors::Forbidden.new("Viewer does not have permission to unenroll the enrollee in this feature.")
        end

        toggleable_feature.unenroll(enrollee)
        { toggleable_feature: toggleable_feature, enrollee: context[:viewer] }
      end
    end
  end
end
