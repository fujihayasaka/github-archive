# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RepositoryRecommendation < Platform::Objects::Base
      description <<~DESCRIPTION
        A recommendation for a repository that GitHub thinks will be interesting for a
        particular user.
      DESCRIPTION

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, recommendation)
        permission.typed_can_access?("Repository", recommendation.repository)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.typed_can_see?("Repository", object.repository)
      end

      required_capabilities [:mobile_only_schema_mask]

      scopeless_tokens_as_minimum

      field :reason, Enums::RepositoryRecommendationReason, "The reason this repository was recommended.", null: false

      field :score, Float, <<~DESCRIPTION, null: false
        A value between [0, 1] that indicates the relevancy of the repository to the user for whom
        it was recommended.
      DESCRIPTION

      field :algorithm_version, String, "The recommendation ML model version", null: true

      field :generated_at, Scalars::DateTime, "The date and time at which this recommendation was generated.", null: true

      field :repository, Objects::Repository, "The recommended repository.", null: false
    end
  end
end
