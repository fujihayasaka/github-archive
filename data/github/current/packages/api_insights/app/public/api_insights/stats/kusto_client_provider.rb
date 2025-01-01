# typed: strict
# frozen_string_literal: true
module ApiInsights::Stats
  class KustoClientProvider
    include Singleton

    sig { returns(Kusto::Data::Client) }
    def self.kusto_client
      self.instance.kusto_client
    end

    sig { returns(Kusto::Data::Client) }
    def kusto_client
      @kusto_client
    end

    private

    sig { void }
    def initialize
      builder = Kusto::Data::ClientBuilder.new
      if GitHub.api_insights_use_local_kusto
        builder.use_local_cluster(port: 42000)
      else
        builder
          .use_azure_cluster(GitHub.api_insights_kusto_cluster_name)
          .use_app_auth(
            GitHub.api_insights_gh_azure_tenant_id,
            GitHub.api_insights_sp_client_id,
            GitHub.api_insights_sp_client_secret)
      end
      @kusto_client = T.let(builder.build, Kusto::Data::Client)
    end
  end
end
