# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Indexable
  module Processor
    # This module provides optional helpers for Indexable::Processor::Base implementations that handle data not stored
    # in MemexProjectColumnValue records (there is currently a generic field processor helper for those processors). In
    # other words, processors that handle related data outside the project domain.
    module SpecialFieldProcessorHelpers
      extend ActiveSupport::Concern
      extend T::Sig
      extend T::Helpers
      requires_ancestor { MemexProjectColumn::Indexable::Processor::Base }

      BATCH_SIZE = 1000

      # The Indexable::Base interface includes a method (currently named `project_ids_to_resync_on_failure`) for deriving
      # project ids that should be resynced if a message fails to be processed predictably. In the majority of cases,
      # implementors should derive those project ids from the Hydro message payload or from the database because those are
      # closer to the sources of truth, less subject to race conditions.
      #
      # However, some processors -- e.g. AccountRename, RepositoryRename -- would require expensive db queries
      # across clusters, databases, and tables to derive the project ids. Those processors can use the method below to
      # derive project ids from Elasticsearch documents matching a given query.
      #
      # This method is not required for the ^above use case, but it encapsulates the logic to make efficient, paginated
      # queries and return just the ids. If an implementor has determined that an Elasticsearch query is the best of
      # all strategies for deriving project ids, this method is strongly recommended.
      #
      # Example implementation:
      #
      #   sig { returns(T::Array[Integer]) }
      #   def project_ids_to_resync_on_failure
      #     project_ids_from_elasticsearch({
      #       query: {
      #         bool: {
      #           filter: { term: { "content.id": my_content_id } }
      #         }
      #       }
      #     })
      #   end
      #
      sig { params(query: T::Hash[Symbol, T.untyped]).returns(T::Array[Integer]) }
      def project_ids_from_elasticsearch(query:)
        project_ids = T.let([], T::Array[Integer])
        search_after = T.let(nil, T.nilable(T::Array[Integer]))
        has_more_documents = T.let(true, T::Boolean)
        body = Elastomer::Interfaces::Api::Search::Request::Body.new(query:)

        while has_more_documents
          params = Elastomer::Interfaces::Api::Search::Request::Params.new(
            _source: ["memex_project_id"],
            sort: [{ database_id: :asc }],
            search_after:,
            size: BATCH_SIZE,
          )

          hits = es_client.search(body, params).hits.hits
          has_more_documents = hits.any?
          search_after = hits.last&.sort

          project_ids += hits.map { |hit| hit._source["memex_project_id"] }
        end
        project_ids.uniq
      end
    end
  end
end
