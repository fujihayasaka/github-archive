# typed: strict
# frozen_string_literal: true

module Copilot
  class ActivityKustoClientProvider
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
      builder
        .use_azure_cluster(GitHub.copilot_activity_kusto_cluster_name)
        .use_app_auth(
          GitHub.copilot_activity_spn_tenant_id,
          GitHub.copilot_activity_spn_client_id,
          GitHub.copilot_activity_spn_client_secret
        )

      @kusto_client = T.let(builder.build, Kusto::Data::Client)
    rescue Exception => e
      GitHub.logger.error("failed to initialize kusto client", { "exception" => e, "code.namespace" => self.class.name, "code.function" => __method__ })
      raise
    end
  end
end
