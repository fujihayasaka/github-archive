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
    end
  end
end
