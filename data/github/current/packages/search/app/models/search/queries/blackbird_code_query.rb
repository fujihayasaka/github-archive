# typed: strict
# frozen_string_literal: true

module Search
  module Queries
    # This is a noop query class that is used to fake out some of the Search::Queries::Query API to avoid
    # instantiating a Search::Queries::CodeQuery in environments that don't have the Elastomer code search index.
    # See: https://github.com/github/availability/issues/2510
    #
    # It intentionally does not subclass Search::Queries::Query and only implements the minimal set of methods to be
    # used with Search::QueryHelper.
    class BlackbirdCodeQuery < Query
      extend T::Sig

      # FakeIndex stubs out necessary methods to avoid instantiating a Elastomer::Indexes::CodeSearch.
      class FakeIndex
        extend T::Sig

        sig { returns(String) }
        def name
          "blackbird"
        end
      end

      sig { params(opts: T.untyped).void }
      def initialize(opts = {})
        super(opts)
      end

      # The set of fields that can be queried when performing a code search.
      sig { override.returns(T::Array[Symbol]) }
      def self.field_list
        [:language, :path, :size, :user, :org, :repo, :symbol, :content, :is].freeze
      end

      # This is required to match the interface of Search::Queries::Query.
      sig { returns(Search::Queries::BlackbirdCodeQuery::FakeIndex) }
      def index
        FakeIndex.new
      end

      # Always returns nil because Blackbird doesn't support sorting.
      sig { returns(NilClass) }
      def sort
        nil
      end

      sig { override.params(skip_prune_results: T::Boolean, results_class: T.class_of(Search::Results)).returns(Search::Results[T.untyped]) }
      def execute(skip_prune_results: false, results_class: Search::Results)
        Search::Results.empty
      end
    end
  end
end
