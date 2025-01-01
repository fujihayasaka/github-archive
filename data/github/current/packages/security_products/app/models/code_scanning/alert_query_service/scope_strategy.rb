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
    end
  end
end
