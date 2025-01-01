# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RepositoryPlanFeatures < Platform::Objects::Base
      extend T::Sig

      description "Information about the availability of features and limits for a repository based on its billing plan."

      # This object exposes information about the availability of certain paid features and limits for a repository
      # based on its owner's billing plan and its own visibility. Under the covers this object uses the standard
      # `plan_supports?` and `plan_limit` methods but surfaces the results in a more customer-friendly way.

      # Note: not all features and limits defined in GitHub::Plan need to be exposed (only publicly-documented
      # features with public APIs that could be impacted by a feature's availability or limit should be exposed).
      # See https://github.com/pricing.

      # To expose a Plan feature or limit, add a field below and an accompanying method to Models::RepositoryPlanFeatures

      # Features that may or may not be available based on billing plan
      field :draft_pull_requests, Boolean, description: "Whether pull requests can be created as or converted to draft", null: false
      field :team_review_requests, Boolean, description: "Whether teams can be requested to review pull requests", null: false
      field :codeowners, Boolean, description: "Whether reviews can be automatically requested and enforced with a CODEOWNERS file", null: false

      # Features with different numeric limits based on billing plan
      field :maximum_manual_review_requests, Integer, description: "Maximum number of manually-requested reviews on a pull request", null: false
      field :maximum_assignees, Integer, description: "Maximum number of users that can be assigned to an issue or pull request", null: false

      sig { params(permission: Platform::Authorization::Permission, object: Platform::Models::RepositoryPlanFeatures).returns(Promise[T::Boolean]) }
      def self.async_api_can_access?(permission, object)
        permission.typed_can_access?("Repository", object.repo)
      end

      sig { params(permission: Platform::Authorization::Permission, object: Platform::Models::RepositoryPlanFeatures).returns(Promise[T::Boolean]) }
      def self.async_viewer_can_see?(permission, object)
        permission.typed_can_see?("Repository", object.repo)
      end
    end
  end
end
