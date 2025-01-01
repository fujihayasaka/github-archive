# typed: true
# frozen_string_literal: true

module Stafftools
  module Repositories
    module SearchIndexes
      class DependabotAlertsComponent < ApplicationComponent
        include GitHub::Memoizer

        DOCUMENT_TYPE = "dependabot-alert"

        def initialize(repository:)
          @repository = repository
        end

        private

        attr_reader :repository

        delegate :vulnerability_alerts_enabled?, :repository_vulnerability_alerts, to: :repository

        memoize def result
          index.search(query, type: DOCUMENT_TYPE, routing: repository.id)
        end

        def document_count
          Elastomer::UpgradeShims.get_total_hits(result["hits"])
        end

        def search_entry
          if document_count > 0
            result["hits"]["hits"].first["_source"]
          end
        end

        def search_entry?
          !search_entry.nil?
        end

        def index
          Elastomer::Indexes::DependabotAlerts.new
        end

        def query
          {
            query: {
              constant_score: {
                filter: {
                  term: {
                    repository_id: repository.id,
                  },
                },
              },
            },
            size: 1,
          }
        end

        def purge?
          !searchable? && search_entry?
        end

        def purge_reason
          if !vulnerability_alerts_enabled?
            "Dependabot alerts have been disabled for this repository."
          end
        end

        def searchable?
          vulnerability_alerts_enabled?
        end

        def reindex?
          return false unless searchable?
          return true unless count_match?
          return true unless owner_match?

          false
        end

        def reindex_reason
          if !owner_match?
            "The repository's owner has changed"
          elsif !count_match?
            "The dependabot alerts count differs from the database."
          end
        end

        memoize def count_match?
          repository.repository_vulnerability_alerts.active.count == document_count
        end

        memoize def owner_match?
          return true unless search_entry?

          repository.owner_id == search_entry["owner_id"]
        end

        def purge_before_reindex?
          search_entry? && !owner_match?
        end
      end
    end
  end
end
