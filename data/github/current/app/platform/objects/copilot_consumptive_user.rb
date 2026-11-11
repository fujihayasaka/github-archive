# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CopilotConsumptiveUser < Platform::Objects::Base
      docs_category :copilot
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
        if use_nwq_quota_usage?
          @object.quota_percentage_remaining(feature: snapshot_bucket_for(feature:))
        else
          if @object.quota_id(feature:) == "premium_chat"
            @object.quota_percentage_remaining(feature: "premium_interactions")
          else
            @object.quota_percentage_remaining(feature:)
          end
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

      field :quota_remaining,
        Float,
        description: "The absolute number of quota units remaining for the given feature.",
        null: true do
          T.bind(self, GraphQL::Schema::Member::HasArguments)
          argument :feature, Platform::Enums::CopilotLimitedFeature, "The feature whose remaining quota is to be checked.", required: true
        end

      def quota_remaining(feature:)
        if use_nwq_quota_usage?
          @object.quota_snapshots[snapshot_bucket_for(feature:)]&.dig(:quota_remaining)&.to_f
        else
          if @object.quota_id(feature:) == "premium_chat"
            snapshot = @object.quota_snapshots["premium_interactions"]
          else
            snapshot = @object.quota_snapshots[feature]
          end

          snapshot&.dig(:quota_remaining)&.to_f
        end
      end

      field :has_unlimited_quota,
        Boolean,
        description: "Whether the user has unlimited quota for the given feature.",
        null: true do
          T.bind(self, GraphQL::Schema::Member::HasArguments)
          argument :feature, Platform::Enums::CopilotLimitedFeature, "The feature to check.", required: true
        end

      def has_unlimited_quota(feature:)
        @object.quota_snapshots[snapshot_bucket_for(feature:)]&.dig(:unlimited)
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

      field :usage_blocked,
        Boolean,
        description: "Whether the user's Copilot usage is blocked by their organization, distinct from quota exhaustion.",
        null: false,
        method: :enterprise_seat_usage_blocked?

      field :billing_entity_display_name,
        String,
        description: "The display name of the entity billed for this user's Copilot usage. Only present for Copilot Business and Copilot Enterprise users.",
        null: true

      def billing_entity_display_name
        copilot_user = Copilot::User.new(object.user)
        resolver = Copilot::BillingEntityResolver.new(copilot_user)
        result = resolver.resolve

        result.display_name
      end

      private

      def use_nwq_quota_usage?
        @object.feature_flag_enabled?(:mobile_ubb_api, default: false)
      end

      def snapshot_bucket_for(feature:)
        @object.quota_id(feature:) == "premium_chat" ? "premium_interactions" : feature
      end
    end
  end
end
