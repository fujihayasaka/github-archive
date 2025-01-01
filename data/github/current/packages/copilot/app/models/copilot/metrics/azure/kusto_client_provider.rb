# typed: strict
# frozen_string_literal: true

module Copilot::Metrics
  module Azure
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
        # TODO: option to use local cluster
        # if GitHub.copilot_use_local_kusto
        #   builder.use_local_cluster(port: 42000)
        # else
        builder
          .use_azure_cluster(GitHub.copilot_metrics_kusto_cluster_name)
          .use_app_auth(
            GitHub.copilot_user_engagement_spn_tenant_id,
            GitHub.copilot_user_engagement_spn_client_id,
            GitHub.copilot_user_engagement_spn_client_secret
          )

        @kusto_client = T.let(builder.build, Kusto::Data::Client)
      rescue Exception => e
        GitHub.logger.error("failed to initialize kusto client", { "exception" => e, "code.namespace" => self.class.name, "code.function" => __method__ })
        raise
      end
    end
  end
end
