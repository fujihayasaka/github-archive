# typed: strict
# frozen_string_literal: true

# This job updates dependabot alerts in Elasticsearch in batches.  It finds RepositoryVulnerabilityAlert models
# associated with the updated_model and updates their corresponding documents in Elasticsearch.

module Search
  module DependabotAlerts
    class BatchUpdateElasticsearchJob < BatchUpdateNormalizedDataJob
      # RetriableElastomerClientError is raised for special handling when ElastomerClient::Client::Error#retry? is true
      class RetriableElastomerClientError < StandardError; end

      class ElasticsearchBulkError < ElastomerClient::Client::MultiDocumentRequestError
        sig { params(bulk_errors: T::Array[T::Hash[String, T.untyped]]).void }
        def initialize(bulk_errors)
          # Wrap each bulk error in a "cause" to match the expected structure of
          # a response in MultiDocumentRequestError
          super({ "failures" => bulk_errors.map { |e| { "cause" => e } } })
        end
      end

      MAX_ES_CLIENT_ERROR_RETRIES = 6
      BATCH_SIZE = T.let(1000, Integer)

      # The maximum size of documents added to an Elasticsearch bulk request before
      # the request is sent to the server.
      BULK_REQUEST_SIZE = T.let(2**20 * 1, Numeric) # 1 MiB

      retry_on RetriableElastomerClientError, attempts: MAX_ES_CLIENT_ERROR_RETRIES, wait: :polynomially_longer
      retry_on Zlib::BufError, attempts: MAX_ES_CLIENT_ERROR_RETRIES, wait: :polynomially_longer

      sig { override.returns(Integer) }
      def default_batch_size
        BATCH_SIZE
      end

      # Syncing alerts to Elasticsearch requires additional fields beyond :id
      sig { override.returns(T::Array[Symbol]) }
      def repository_vulnerability_alert_fields
        [:id, :repository_id]
      end

      sig { override.params(args: T.untyped, item: T::Array[T::Hash[Symbol, T.untyped]], kwargs: T.untyped).void }
      def process_item(*args, item:, **kwargs)
        # Elasticsearch has a default refresh interval of 1s, which should be sufficient for
        # searches following these updates and avoiding refreshes lessens the load on ES.
        # Callers can override the refresh behavior via kwargs.
        refresh = kwargs.fetch(:refresh, Elastomer::Interfaces::Api::Bulk::Request::Params::Refresh::False.serialize)
        request_size = kwargs.fetch(:request_size, BULK_REQUEST_SIZE)

        response = T.let(nil, T.nilable(T::Hash[String, T.untyped]))
        updated_count = T.let(0, T.nilable(Integer))

        start = GitHub::Dogstats.monotonic_time
        response = index.docs.bulk(request_size:, refresh:) do |bulk|
          item.each do |row|
            response = bulk.update(
              # Update the document with the new dependabot alert fields.
              # Note: due to the delay between when data is loaded and when the updates are executed
              # it's possible that another concurrent process could have changed the underlying data in MySQL.
              # This would lead to the data in MySQL being out of sync with Elasticsearch.  To fix this,
              # a repair of the index would be needed.
              { doc: updated_model.dependabot_alert_fields },

              # use the repository_id as the routing value to ensure the request goes to the correct shard
              { _id: row[:id], _routing: row[:repository_id], retry_on_conflict: Search::Memex::Client::RETRY_ON_CONFLICT }
            )

            # Each individual operation in a bulk scope may or may not return a response.
            # Bulk requests are sent to Elasticsearch either when the size of all documents in the
            # bulk scope reaches the `request_size` threshold, or when the bulk scope ends.
            # A non-nil response indicates this update triggered a server call which should be processed.
            next unless response

            updated_count, errors = parse_bulk_api_response(response)
            raise ElasticsearchBulkError.new(errors) if errors.any?

            log_results(:success, updated_count, start)
            start = GitHub::Dogstats.monotonic_time # reset start time for the next batch of operations
          end
        end

        updated_count, errors = parse_bulk_api_response(response)
        raise ElasticsearchBulkError.new(errors) if errors.any?

        log_results(:success, updated_count, start)
      rescue ElastomerClient::Client::Error, ElastomerClient::Client::MultiDocumentRequestError => e
        log_results(:failure, updated_count || 0, start)
        # If the error is retriable, raise a special error that will be caught by retry_on
        raise RetriableElastomerClientError if e.retry?
        raise
      rescue StandardError => e
        log_results(:failure, updated_count || 0, start)
        raise
      end

      sig { override.returns(String) }
      def job_stats_key
        "bulk_update"
      end

      IGNORE_RESULTS = T.let([
        Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::NotFound,
        Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::Noop,
      ].freeze, T::Array[Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result])

      sig { override.params(error: Exception).void }
      def log_error(error)
        # report the root cause if this was a retriable elastomer error
        error = T.must(error.cause) if error.is_a?(RetriableElastomerClientError) && error.cause
        super(error)
      end

      private

      # Parse a bulk API response and return the number of updates + any encountered errors.
      sig do
        params(response: T::Hash[String, T.untyped])
          .returns([Integer, T::Array[T::Hash[String, T.untyped]]])
      end
      def parse_bulk_api_response(response)
        return [0, []] if response.nil?

        updated_count = 0
        errors = []
        Array(response["items"]).each do |item|
          result = item.values.first

          # ignore non-update results
          next if IGNORE_RESULTS.include?(result["result"])

          # log an update if there was no error
          error = result["error"]
          if error.blank?
            updated_count += 1
            next
          end

          # Assume that we'll try to update documents that don't exist in ES
          # because we don't filter which alerts to send updates for based on
          # whether they are searchable and already exist in ES.  Checking whether
          # a document is searchable and exists in ES is expensive and we need
          # these updates to perform quickly.
          next if result["status"] == 404 && error["type"] == "document_missing_exception"

          errors << error
        end

        [updated_count, errors]
      end

      sig { returns(Elastomer::Indexes::DependabotAlerts) }
      def index
        Elastomer::Indexes::DependabotAlerts.new
      end
    end
  end
end
