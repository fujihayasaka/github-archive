# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module ApiInsights
      # Indicates whether to use the local Kusto cluster for API Insights queries.
      #
      # ** The intention is to use this only in development and test environments. **
      attr_accessor :api_insights_use_local_kusto

      # The ID (guid) of the GitHubAzure tenant.
      attr_accessor :api_insights_gh_azure_tenant_id

      # The **client ID** (guid) of the API Insights application in Microsoft Entra (AAD).
      attr_accessor :api_insights_sp_client_id

      # The client secret of the API Insights application in Microsoft Entra (AAD).
      attr_accessor :api_insights_sp_client_secret

      # The name of the API Insights Kusto cluster.
      #
      # _This is the name of the cluster, not the fully qualified domain name._
      #
      # e.g. `gh-api-insights-dotcom.eastus`
      attr_accessor :api_insights_kusto_cluster_name

      # The name of the API Insights Kusto database.
      attr_accessor :api_insights_kusto_database_name

      # The materialized view or table input for the Kusto query. This is controlled by the
      # `api_insights_use_secondary_tabular_input` feature flag. This value is used when the
      # feature flag is disabled.
      #
      # e.g. `materialized_view("APIINSIGHTS_stats_v1")`
      attr_accessor :api_insights_kusto_tabular_input_primary

      # The materialized view or table input for the Kusto query. This is controlled by the
      # `api_insights_use_secondary_tabular_input` feature flag. This value is used when the
      # feature flag is enabled.
      #
      # e.g. `materialized_view("APIINSIGHTS_stats_v1")`
      attr_accessor :api_insights_kusto_tabular_input_secondary

      sig { returns(String) }
      def api_insights_active_kusto_tabular_input
        # NOTE: This is a long-lived feature flag. It is not intended to be removed.
        if GitHub.flipper.enabled?(:api_insights_use_secondary_tabular_input)
          api_insights_kusto_tabular_input_secondary
        else
          api_insights_kusto_tabular_input_primary
        end
      end
    end
  end

  extend Config::ApiInsights
end
