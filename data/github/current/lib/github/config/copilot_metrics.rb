# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module CopilotMetrics
      # The name of the Azure Storage Account for Copilot user engagement
      attr_accessor :copilot_user_engagement_storage_account_name

      # The tenant id for the user engagement Azure SPN
      attr_accessor :copilot_user_engagement_spn_tenant_id

      # The client id for the user engagement Azure SPN
      attr_accessor :copilot_user_engagement_spn_client_id

      # The client secret for the user engagement Azure SPN
      attr_accessor :copilot_user_engagement_spn_client_secret

      # The kusto cluster name
      attr_accessor :copilot_metrics_kusto_cluster_name

      # The name of the Azure Storage Account for Copilot metrics direct data access
      attr_accessor :copilot_direct_data_access_storage_account_name
    end

    # Are Copilot metrics available?
    #
    # This feature is only available in GHEC.
    #
    # Returns Boolean.
    def copilot_metrics_available?
      !::GitHub.enterprise? && !::GitHub.multi_tenant_enterprise?
    end
  end

  extend Config::CopilotMetrics
end
