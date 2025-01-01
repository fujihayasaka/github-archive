# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CopilotConsumptiveUser < Platform::Objects::Base
      description "Information about a consumptive Copilot user, such as quotas or feature availability."

      required_capabilities [:access_copilot_consumptive_graphql_api]

      def self.async_api_can_access?(permission, object)
        permission.typed_can_access?("User", object.user)
      end

      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_viewer(object)
      end

      field :reset_date, Scalars::Date, description: "The date when the quota for the Copilot consumptive user will reset.", null: true

      def reset_date
        @object.quota_reset_date
      end

      field :percent_remaining,
        Float,
        description: "The percentage of the quota remaining for the given feature.",
        null: true do
          T.bind(self, GraphQL::Schema::Member::HasArguments)
          argument :feature, Platform::Enums::CopilotLimitedFeature, "The feature whose quotas are to be checked against.", required: true
        end

      def percent_remaining(feature:)
        if @object.quota_id(feature:) == "premium_chat"
          @object.quota_percentage_remaining(feature: "premium_interactions")
        else
          @object.quota_percentage_remaining(feature:)
        end
      end

      field :entitlement,
        Float,
        description: "The number of requests included in the entitlement for the given feature.",
        null: false do
          T.bind(self, GraphQL::Schema::Member::HasArguments)
          argument :feature, Platform::Enums::CopilotLimitedFeature, "The feature whose entitlement is to be checked.", required: true
        end

      def entitlement(feature:)
        @object.quota_feature_entitlement(feature:)
      end

      field :current_overage_count,
        Float,
        description: "The count of overage requests made so far in this month/period for the given feature.",
        null: false do
          T.bind(self, GraphQL::Schema::Member::HasArguments)
          argument :feature, Platform::Enums::CopilotLimitedFeature, "The feature whose overage count is to be checked.", required: true
        end

      def current_overage_count(feature:)
        @object.quota_feature_overage_count(feature: "premium_interactions")
      end

      field :is_overage_permitted, Boolean, description: "Whether or not the consumptive user has overages enabled.", null: false

      # TODO: add billing platform check
      def is_overage_permitted
        @object.overages_enabled?
      end

      field :quota_id,
        String,
        description: "A well-known identifier for the given feature",
        null: false do
          T.bind(self, GraphQL::Schema::Member::HasArguments)
          argument :feature, Platform::Enums::CopilotLimitedFeature, "The feature whose quota ID is to be checked.", required: true
        end

      def quota_id(feature:)
        @object.quota_id(feature:)
      end
    end
  end
end
