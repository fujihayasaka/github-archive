# typed: true
# frozen_string_literal: true

module Audit
  module Elastic
    # Sends audit logs to ElasticSearch directly using Faraday through the ES
    # REST API.
    class Logger < Adapter
      # Internal: Posts the data to ElasticSearch.
      #
      # payload - The Hash of data that is sent over as JSON.
      #
      # Returns the Faraday::Response.
      def perform(payload)
        entry = Elastomer::Adapters::AuditEntry.create(payload)
        index_name = if test_env?
          payload.delete(:index) || payload.delete("index") || index.name
        end

        dogtags = [
          "destination:elasticsearch",
        ]

        unless GitHub.enterprise?
          action = payload.fetch(:action, "unknown")
          actiontags = [
            "action:#{action}",
          ]
          GitHub.dogstats.count("audit_log_dotcom_publisher", 1, tags: actiontags)
        end

        return_value = GitHub.dogstats.distribution_time("audit.entry", tags: dogtags) do
          begin
            response = Elastomer.add_to_search_index(entry, {
              index: index_name,
              cluster: cluster,
            })

            # Only when we get a response from Elasticsearch is it a Hash.
            if response.is_a?(Hash)
              record_response(created_at: entry.timestamp, dogtags: dogtags, response: response)
            end
            response
          rescue StandardError => error # rubocop:todo Lint/GenericRescue
            GitHub.dogstats.increment("audit.entry.error", tags: dogtags)
            raise error if error.kind_of?(ElastomerClient::Client::Error) && error.retry?
            GitHub.dogstats.increment("audit.entry.indexing.failure", tags: dogtags)
            Failbot.report(error)
            false
          end
        end

        return return_value.first if return_value.is_a?(Array)
        return_value
      end

      private

      def record_response(created_at:, response:, dogtags: [])
        created =
          if Elastomer.router.cluster_running_version_8_plus?(GitHub.es_audit_log_cluster)
            response["result"] == "created"
          else
            response["created"]
          end

        unless response && created
          GitHub.dogstats.increment("audit.entry.indexing.failure", tags: dogtags)
          return
        end

        created_at_time = Audit.milliseconds_to_time(created_at)
        GitHub.dogstats.increment("audit.entry.indexing.success", tags: dogtags)
        GitHub.dogstats.timing_since("audit.entry.indexing.ttl", created_at_time, tags: dogtags)
      end
    end
  end
end
