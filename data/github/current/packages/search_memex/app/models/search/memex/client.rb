# typed: strict
# frozen_string_literal: true

module Search
  module Memex
    # This class proxies elastomer-client with a typed interface and opinionated parameters that we are seeking to
    # encourage or enforce within the Projects service.
    #
    # Implementors should prefer this class to direct use of Elastomer::Indexes::MemexProjectItems, particularly in
    # Indexable::Processor::Base subclasses. If a method is missing, please add it here, together with any
    # Elastomer::Interfaces types that are appropriate.
    class Client
      RETRY_ON_CONFLICT = 4
      IGNORED_DOCUMENT_ERRORS = T.let([{
        status: 404,
        type: "document_missing_exception"
      }].freeze, T::Array[T::Hash[Symbol, T.untyped]])

      # Roll up all possible return types into one `Client::Response` that can be referenced by client consumers.
      Response = T.type_alias do
        T.any(
          Elastomer::Interfaces::Api::Delete::Response,
          Elastomer::Interfaces::Api::DeleteByQuery::Response,
          Elastomer::Interfaces::Api::Update::Response,
          Elastomer::Interfaces::Api::UpdateByQuery::Response,
          Elastomer::Interfaces::Api::Bulk::Response::Body,
        )
      end

      sig { params(index: Elastomer::Index).void }
      def initialize(index)
        @index = index
      end

      sig do
        params(params: Elastomer::Interfaces::Api::Delete::Request::Params)
        .returns(Elastomer::Interfaces::Api::Delete::Response)
      end
      def delete(params)
        # While Elasticsearch doesn't require a routing value to be included, we insist on one because, for performance/load
        # purposes, we want to ensure that the request is sent directly to the correct shard.
        raise ArgumentError, "A routing value (project id) is required" if params.routing.nil?

        # The Elasticsearch default for refresh is `false`, which means that the delete operation will not be visible
        # to subsequent search requests until the next refresh. We default to `WaitFor` so that delete responses will
        # not return until the index has been refreshed, ensuring that downstream requests will see the updated data.
        params.refresh = Elastomer::Interfaces::Api::Delete::Request::Params::Refresh::WaitFor if params.refresh.nil?

        response = @index.docs.delete(params.to_hash)
        Elastomer::Interfaces::Api::Delete::Response.from_es_response(response)
      end

      sig do
        params(
          body: Elastomer::Interfaces::Api::DeleteByQuery::Request::Body,
          params: Elastomer::Interfaces::Api::DeleteByQuery::Request::Params
        )
        .returns(Elastomer::Interfaces::Api::DeleteByQuery::Response)
      end
      def delete_by_query(body, params = Elastomer::Interfaces::Api::DeleteByQuery::Request::Params.new)
        response = @index.docs.delete_by_query(body.to_hash, params.to_hash)
        Elastomer::Interfaces::Api::DeleteByQuery::Response.from_es_response(response)
      end

      sig do
        params(
          body: Elastomer::Interfaces::Api::Search::Request::Body,
          params: T.nilable(Elastomer::Interfaces::Api::Search::Request::Params),
        )
        .returns(Elastomer::Interfaces::Api::Search::Response)
      end
      def search(body, params = nil)
        raise ArgumentError.new("You must include either `q` or `query` in the request body") unless body.q || body.query

        # Elasticsearch defines a distinct body and distinct params for search requests, but sometimes it allows you to
        # specify the same properties in both places. Perhaps to reduce confusion, the elastomer-client search method
        # allows you to pass in all body + param properties in a single hash.
        combined_hash = body.to_hash.merge(params&.to_hash || {})

        response = @index.docs.search(combined_hash)
        Elastomer::Interfaces::Api::Search::Response.from_es_response(response)
      end

      sig do
        params(
          body: Elastomer::Interfaces::Api::Update::Request::Body,
          params: Elastomer::Interfaces::Api::Update::Request::Params
        )
        .returns(Elastomer::Interfaces::Api::Update::Response)
      end
      def update(body, params)
        # While Elasticsearch doesn't require a routing value to be included, we insist on one because, for performance/load
        # purposes, we want to ensure that the request is sent directly to the correct shard.
        raise ArgumentError, "A routing value (project id) is required" if params.routing.nil?

        # The Elasticsearch default for refresh is `false`, which means that the delete operation will not be visible
        # to subsequent search requests until the next refresh. We default to `WaitFor` so that delete responses will
        # not return until the index has been refreshed, ensuring that downstream requests will see the updated data.
        params.refresh = Elastomer::Interfaces::Api::Update::Request::Params::Refresh::WaitFor if params.refresh.nil?

        # We expect all updates to retry on conflict unless overridden.
        params.retry_on_conflict = RETRY_ON_CONFLICT if params.retry_on_conflict.nil?

        response = @index.docs.update(body.to_hash, params.to_hash)
        Elastomer::Interfaces::Api::Update::Response.from_es_response(response)
      end

      sig do
        params(
          body: Elastomer::Interfaces::Api::UpdateByQuery::Request::Body,
          params: Elastomer::Interfaces::Api::UpdateByQuery::Request::Params,
        )
        .returns(Elastomer::Interfaces::Api::UpdateByQuery::Response)
      end
      def update_by_query(body, params = Elastomer::Interfaces::Api::UpdateByQuery::Request::Params.new)
        # The Elasticsearch default for refresh is `false`, which means that the update by query operation will not be visible
        # to subsequent search requests until the next refresh. We default to `True` so that the index will update
        # immediately, ensuring that downstream requests will see the updated data.
        params.refresh = Elastomer::Interfaces::Api::UpdateByQuery::Request::Params::Refresh::True if params.refresh.nil?

        # We expect all updates to proceed on conflict rather than aborting and raising an exception.
        params.conflicts = Elastomer::Interfaces::Api::UpdateByQuery::Request::Params::Conflicts::Proceed if params.conflicts.nil?

        response = @index.docs.update_by_query(body.to_hash, params.to_hash)
        Elastomer::Interfaces::Api::UpdateByQuery::Response.from_es_response(response)
      end

      sig do
        params(
          params: Elastomer::Interfaces::Api::Bulk::Request::Params,
          block: T.proc.params(arg0: ElastomerClient::Client::Bulk).void,
        )
        .returns(Elastomer::Interfaces::Api::Bulk::Response::Body)
      end
      def bulk(params = Elastomer::Interfaces::Api::Bulk::Request::Params.new, &block)
        # https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-refresh.html
        params.refresh = Elastomer::Interfaces::Api::Bulk::Request::Params::Refresh::WaitFor if params.refresh.nil?

        es_response = @index.docs.bulk(params.to_hash, &block)
        response = Elastomer::Interfaces::Api::Bulk::Response::Body.from_es_response(es_response)
        response.items = response.items.filter do |i|
          # Exclude results for errors that we know are safe to ignore.
          IGNORED_DOCUMENT_ERRORS.none? do |e|
            e[:status] == i.item_result.status && e[:type] == i.item_result.error&.type
          end
        end
        response.errors = response.items.any? { |i| i.item_result.error.present? }
        response
      end
    end
  end
end
