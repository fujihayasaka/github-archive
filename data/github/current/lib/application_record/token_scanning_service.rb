# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class TokenScanningService < Base
    self.abstract_class = true

    connects_to database: { writing: :token_scanning_service_primary, reading: :token_scanning_service_readonly }

    # The cluster name for `TokenScanningService` is `token-scanning-service-prod` - some things
    # derive the cluster name from the ApplicationRecord class name (e.g., Freno) which does not work because
    # they don't match.  So we override it here by returning a symbol matching the expected
    # cluster name.
    def self.cluster_name
      :"token-scanning-service-prod"
    end

    def self.production_schema_name
      "token_scanning_service"
    end
  end
end
