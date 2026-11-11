# typed: true
# frozen_string_literal: true

require "monolith-twirp-partitioning-pull_requests"

module GitHub
  module Partitioning
    RPC_TO_CLIENT = {
      "pull_requests": {
        "v1": {
          "filter_repositories_by_field": MonolithTwirp::Partitioning::PullRequests::V1::ReadDataAPIClient,
        }
      },
    }

    RPC_TO_REQUEST_CLASS = {
      "pull_requests": {
        "v1": {
          "filter_repositories_by_field": MonolithTwirp::Partitioning::PullRequests::V1::FilterRepositoriesByFieldRequest,
        }
      },
    }

    class CrossPartitionRequestBuilder
      def initialize(service:, version:, rpc:)
        @request_class = RPC_TO_REQUEST_CLASS.dig(service, version, rpc)

        @scope = nil
        @filter_value = nil
        @limit = nil
      end

      def with_scope(scope)
        @scope = scope
        self
      end

      def with_filter_value(filter_value)
        @filter_value = filter_value
        self
      end

      def with_limit(limit)
        @limit = limit
        self
      end

      def build_request
        raise ArgumentError, "Invalid rpc request class. Make sure your endpoint is registered." unless @request_class.present?

        params = {}
        params[:scope] = @scope if @scope.present?
        params[:filter_value] = @filter_value.to_s if @filter_value.present?
        params[:limit] = @limit if @limit.present?

        @request_class.new(**params)
      end
    end

    class CrossPartitionQueryBuilder
      def initialize(service:, version:, rpc:)
        @rpc = rpc
        @service = service
        @version = version

        @client = Partitioning::RPC_TO_CLIENT.dig(service, version, rpc)
        @request_builder = nil

        yield self if block_given?
      end

      def configure_request
        @request_builder = CrossPartitionRequestBuilder.new(
          service: @service,
          version: @version,
          rpc: @rpc,
        )
        @request_builder
      end

      def query_all_partitions
        raise ArgumentError, "Invalid rpc client. Make sure your endpoint is registered." unless @client.present?
        raise ArgumentError, "Missing request. Make sure to set up your request by calling .build_request" unless @request_builder.present?
        request = @request_builder.build_request
        GitHub::Partitioning::ScatterGatherer.query_all_shards(@client, @rpc, request)
      end
    end
  end
end
