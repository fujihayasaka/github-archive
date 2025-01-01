# typed: true
# frozen_string_literal: true

require "github/security_center/logging_helper"

module CodeScanning
  class AlertQueryService
    ##
    # Abstract class for defining scope-specific behavior for `AlertQueryService`
    class ScopeStrategy
      include GitHub::Memoizer
      include GitHub::SecurityCenter::LoggingHelper

      REPO_IDS_SIZE_LIMIT = 10000 # The maximum number of repository IDs we're willing to send to the API in a single request
      SECURITY_CAMPAIGN_IDS_SIZE_LIMIT = 10_000 # The maximum number of security campaign IDs we're willing to send to the API in a single request
      NON_EXISTING_USER_ID = 0 # A user ID that does not exist
      AT_ME_VALUE = "@me".freeze

      def scope
        raise NotImplementedError
      end

      def selected_repository_ids
        raise NotImplementedError
      end

      ##
      # Create a scope object used for post-filtering results by tenant.
      #
      # @return [GitHub::SecurityCenter::TenantFilteringHelper::RequestScope]
      def tenant_filter_scope
        # must override in concrete classes
        raise NotImplementedError
      end

      def tenant_id
        raise NotImplementedError
      end

      def tenant_name
        raise NotImplementedError
      end

      def with_owner_ids!(hash)
        raise NotImplementedError
      end

      def with_repository_ids!(hash, exclude_filter_type: nil)
        raise NotImplementedError
      end

      def with_autofix!(hash)
        raise NotImplementedError
      end

      def with_excluded_autofix!(hash)
        raise NotImplementedError
      end

      def with_campaign!(hash)
        raise NotImplementedError
      end

      sig { params(hash: T::Hash[Symbol, T.untyped]).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def with_assignees!(hash)
        raise NotImplementedError
      end

      sig do
        params(
          current_user: User,
          parsed_query: Search::Queries::SecurityCenter::CodeScanningBaseQuery,
          exclude_private_profiles: T::Boolean,
        ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
      end
      def self.assigned_users_filter(current_user:, parsed_query:, exclude_private_profiles: false)
        assignees_logins = parsed_query.assignees_logins
        excluded_assignees_logins = parsed_query.excluded_assignees_logins

        assignees_logins.map! { |login| login == AT_ME_VALUE ? current_user.display_login : login }
        excluded_assignees_logins.map! { |login| login == AT_ME_VALUE ? current_user.display_login : login }

        qualifiers = Search::ParsedQuery.qualifiers
        qualifiers[:user].must assignees_logins unless assignees_logins.empty?
        qualifiers[:user].must_not excluded_assignees_logins unless excluded_assignees_logins.empty?

        filter = Search::Filters::UserFilter.new(keys: :user, qualifiers:, exclude_private_profiles:, current_user:)

        assigned_user_ids = filter.map_bool_collection.must
        excluded_assigned_user_ids = filter.map_bool_collection.must_not

        # If filtering for a non-existing user, add a non existing user ID
        if assignees_logins.present? && !assigned_user_ids.present?
          assigned_user_ids.push(NON_EXISTING_USER_ID)
        end

        assigned_users = {}
        assigned_users[:assigned_user_ids] = assigned_user_ids.sort if assigned_user_ids.present?
        assigned_users[:excluded_assigned_user_ids] = excluded_assigned_user_ids.sort if excluded_assigned_user_ids.present?
        assigned_users[:assigned_user_presence] = parsed_query.assigned_user_presence if parsed_query.assigned_user_presence.present?

        assigned_users unless assigned_users.empty?
      end

      private

      sig { params(hash: T::Hash[Symbol, T.untyped], include: T::Array[Integer], exclude: T::Array[Integer], organization_ids: T::Array[Integer], user: User).void }
      def filter_campaign!(hash, include:, exclude:, organization_ids:, user:)
        return if include.empty? && exclude.empty?

        open_campaigns = SecurityCampaigns::SecurityCampaign.open.where(organization_id: organization_ids)
        open_campaigns = open_campaigns.filter_spam_for(user)
        open_security_campaign_ids = open_campaigns.limit(SECURITY_CAMPAIGN_IDS_SIZE_LIMIT).pluck(:id)

        hash[:security_campaign_state] = Turboscan::Proto::SecurityCampaignStateFilter.new(
          open_security_campaign_ids:,
          include:,
          exclude:,
        )
      end

      sig { params(hash: T::Hash[Symbol, T.untyped], current_user: User).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def filter_assignees!(hash, current_user:)
        assigned_users = self.class.assigned_users_filter(current_user:, parsed_query: @parsed_query, exclude_private_profiles: true)
        hash[:assigned_users] = assigned_users unless assigned_users&.empty?
      end
    end
  end
end
