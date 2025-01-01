# typed: strict
# frozen_string_literal: true

module Search
  module Responses
    module SharedMemexProjectItemResponseDependency
      extend T::Helpers

      requires_ancestor { CursorPaginationResponse }

      # A flattened representation of slice aggregations for easier access.
      sig { returns(T.nilable(T::Array[T::Hash[T.untyped, T.untyped]])) }
      attr_reader :slices

      # Insights chart data if requested.
      sig { returns(T.nilable(MemexProjectColumn::Interface::Chartable::ChartData)) }
      attr_reader :chart_data

      # An optional array of all item owner ids in the project.
      # Each project item references an issue that resides in a repository that's owned by a user/org.
      # These owning org ids are typically used for org CAP checks to prompt users for Single Sign-On.
      sig { returns(T.nilable(T::Array[Integer])) }
      attr_reader :project_item_owner_ids

      # Redactor results including repository ids that were explicitly checked for authorization (normal auth and CAP checks)
      sig { returns(T.nilable(Search::Queries::MemexProjectItemQueryRedactor::Results)) }
      attr_reader :redactor_results

      sig { params(aggregations: T::Hash[T.untyped, T.untyped], opts: T::Hash[T.untyped, T.untyped]).void }
      def initialize_response(aggregations, opts)
        @remove_spam = T.let(!!opts[:remove_spam], T.nilable(T::Boolean))
        @viewer = T.let(opts[:viewer], T.nilable(User))

        @slices = T.let(initialize_slices(opts), T.nilable(T::Array[T::Hash[T.untyped, T.untyped]]))

        @chart_data = T.let(opts.fetch(:chart_data, nil), T.nilable(MemexProjectColumn::Interface::Chartable::ChartData))

        @repository_ids = T.let(get_values_for_aggregation(aggregations, "repository_ids"), T.nilable(T::Array[Integer]))
        @item_creator_ids = T.let(get_values_for_aggregation(aggregations, "item_creator_ids"), T.nilable(T::Array[Integer]))
        @content_creator_ids = T.let(get_values_for_aggregation(aggregations, "content_creator_ids"), T.nilable(T::Array[Integer]))

        @project_item_owner_ids = T.let(opts[:project_item_owner_ids], T.nilable(T::Array[Integer]))
        @redactor_results = T.let(nil, T.nilable(Search::Queries::MemexProjectItemQueryRedactor::Results))
      end

      # An array of all repository ids that match the query.
      # These are used to check if redactions are needed.
      sig { returns(T::Array[Integer]) }
      def repository_ids
        T.must(@repository_ids)
      end

      # An array of all project item creator user ids that match the query.
      # These are used to check if spammy redactions are needed.
      sig { returns(T::Array[Integer]) }
      def item_creator_ids
        T.must(@item_creator_ids)
      end

      # An array of all project item content (issue/pr) creator user ids that match the query.
      # These are used to check if spammy redactions are needed.
      sig { returns(T::Array[Integer]) }
      def content_creator_ids
        T.must(@content_creator_ids)
      end

      # Add redactor results to the response for use by any subsequent authorization checks.
      sig { params(results: T.nilable(Search::Queries::MemexProjectItemQueryRedactor::Results)).void }
      def set_redactor_results(results)
        @redactor_results = results
      end

      sig { returns(T::Boolean) }
      def sliced?
        !slices.nil?
      end

      sig { returns(T.nilable(ElastomerClient::Client::Error)) }
      def elastomer_exception
        error_details&.fetch(:exception, nil)
      end

      sig { params(opts: T::Hash[T.untyped, T.untyped]).returns(T.nilable(T::Array[T::Hash[T.untyped, T.untyped]])) }
      private def initialize_slices(opts)
        result = opts.fetch(:slices, nil)
        return if result.nil?
        result&.map do |s|
          s.merge!("slice_id" => Search::Responses::PropertyEncoder.encode(s.dig("slice_id")))
        end
        result
      end

      # Extract the array of unique aggregation ids from the ES aggregation response keyed by the given aggregation slug.
      sig { params(aggregations: T::Hash[T.untyped, T.untyped], slug: String).returns(T::Array[Integer]) }
      private def get_values_for_aggregation(aggregations, slug)
        buckets = aggregations.dig(slug, "buckets") || []
        buckets.map { |b| b.dig("key") }.compact
      end
    end
  end
end
