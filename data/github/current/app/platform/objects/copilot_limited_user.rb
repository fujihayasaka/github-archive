# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CopilotLimitedUser < Platform::Objects::Base
      docs_category :copilot
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

      field :quota_remaining,
        Float,
        description: "The absolute number of quota units remaining for the given feature.",
        null: true do
          T.bind(self, GraphQL::Schema::Member::HasArguments)
          argument :feature, Platform::Enums::CopilotLimitedFeature, "The feature whose remaining quota is to be checked.", required: true
        end

      def quota_remaining(feature:)
        snapshot = @object.quota_snapshots[feature]
        snapshot&.dig(:quota_remaining)&.to_f
      end

      field :has_quota,
        Boolean,
        description: "Whether the user has a quota set for the given feature. Distinguishes 'zero remaining' from 'no budget set'.",
        null: true do
          T.bind(self, GraphQL::Schema::Member::HasArguments)
          argument :feature, Platform::Enums::CopilotLimitedFeature, "The feature to check.", required: true
        end

      def has_quota(feature:)
        snapshot = @object.quota_snapshots[feature]
        snapshot&.dig(:has_quota)
      end

      field :quota_reset_at,
        Scalars::DateTime,
        description: "The UTC date and time when the quota resets for the given feature when reset happens at granularity finer than a day.",
        null: true do
          T.bind(self, GraphQL::Schema::Member::HasArguments)
          argument :feature, Platform::Enums::CopilotLimitedFeature, "The feature to check.", required: true
        end

      def quota_reset_at(feature:)
        snapshot = @object.quota_snapshots[feature]
        reset_at = snapshot&.dig(:quota_reset_at)
        return nil if reset_at.nil? || reset_at == 0
        Time.at(reset_at).utc
      end

      field :token_based_billing,
        Boolean,
        description: "Whether this user is on the token-based billing model.",
        null: false

      def token_based_billing
        @object.use_token_based_billing?
      end
    end
  end
end
