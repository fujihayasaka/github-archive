# typed: strict
# frozen_string_literal: true

module Search
  module Responses
    module SharedMemexProjectItemResponseDependency
      extend T::Helpers
      extend T::Sig

      # A flattened representation of slice aggregations for easier access.
      sig { returns(T.nilable(T::Array[T::Hash[T.untyped, T.untyped]])) }
      attr_reader :slices

      # An optional array of all item owner ids in the project.
      # Each project item references an issue that resides in a repository that's owned by a user/org.
      # These owning org ids are typically used for org CAP checks to prompt users for Single Sign-On.
      sig { returns(T.nilable(T::Array[Integer])) }
      attr_reader :project_item_owner_ids

      sig { params(aggregations: T::Hash[T.untyped, T.untyped], opts: T::Hash[T.untyped, T.untyped]).void }
      def initialize_response(aggregations, opts)
        @remove_spam = T.let(!!opts[:remove_spam], T.nilable(T::Boolean))
        @viewer = T.let(opts[:viewer], T.nilable(User))

        @slices = T.let(initialize_slices(opts), T.nilable(T::Array[T::Hash[T.untyped, T.untyped]]))

        @repository_ids = T.let([], T.nilable(T::Array[Integer]))
        @repository_ids = initialize_repository_ids(aggregations)

        @project_item_owner_ids = T.let(opts[:project_item_owner_ids], T.nilable(T::Array[Integer]))
      end

      # An array of all repository ids that match the query.
      # These are used to check if redactions are needed.
      sig { returns(T::Array[Integer]) }
      def repository_ids
        T.must(@repository_ids)
      end

      sig { returns(T::Boolean) }
      def sliced?
        !slices.nil?
      end

      sig { params(opts: T::Hash[T.untyped, T.untyped]).returns(T.nilable(T::Array[T::Hash[T.untyped, T.untyped]])) }
      private def initialize_slices(opts)
        result = opts.fetch(:slices, nil)
        return if result.nil?
        result&.map do |s|
          s.merge!("slice_id" => encode_identifier(s.dig("slice_id")))
        end
        result
      end

      # Performs the same encoding as encode_cursor, but for group identifiers.
      # Separate method to ensure stronger param type safety per use case.
      sig do
        params(identifier: T.nilable(MemexProjectColumn::Groupable::GroupIdentifier))
        .returns(T.nilable(String))
      end
      private def encode_identifier(identifier)
        Platform::ConnectionWrappers::CursorGenerator.generate_cursor(identifier, version: :v2) if identifier
      end

      # Extract the array of repository ids from the ES aggregation response keyed by repository_ids.
      sig { params(aggregations: T::Hash[T.untyped, T.untyped]).returns(T::Array[Integer]) }
      private def initialize_repository_ids(aggregations)
        repo_buckets = aggregations.dig("repository_ids", "buckets") || []
        repo_buckets.map { |b| b.dig("key") }.compact
      end
    end
  end
end
