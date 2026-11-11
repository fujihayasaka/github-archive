# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CopilotLimitedUser < Platform::Objects::Base
      description "Information about a limited Copilot Free user, such as quotas or feature availability."

      required_capabilities [:access_copilot_limited_graphql_api]

      def self.async_api_can_access?(permission, object)
        object.async_user.then do |user|
          permission.typed_can_access?("User", user)
        end
      end

      def self.async_viewer_can_see?(permission, object)
        object.async_user.then do |user|
          permission.viewer == user
        end
      end

      field :reset_date, Scalars::Date, description: "The date when the quota for the Copilot Free user will reset.", null: true

      def reset_date
        @object.async_user.then do
          @object.reset_date
        end
      end

      field :has_usage_remaining,
        Boolean,
        description: "Whether or not the user has remaining usage for the given feature.",
        null: true do
          T.bind(self, GraphQL::Schema::Member::HasArguments)
          argument :feature, Platform::Enums::CopilotLimitedFeature, "The feature whose quotas are to be checked against.", required: true
        end

      def has_usage_remaining(feature:)
        @object.async_user.then do
          @object.feature_allowed?(feature:)
        end
      end

      field :quota_percentage_remaining,
        Float,
        description: "The percentage of the quota remaining for the given feature.",
        null: true do
          T.bind(self, GraphQL::Schema::Member::HasArguments)
          argument :feature, Platform::Enums::CopilotLimitedFeature, "The feature whose quotas are to be checked against.", required: true
        end

      def quota_percentage_remaining(feature:)
        @object.async_user.then do
          @object.feature_quota_percentage_remaining(feature:)
        end
      end
    end
  end
end
