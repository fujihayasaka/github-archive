# typed: true
# frozen_string_literal: true

module Search
  module Queries
    module Audit
      class ProjectQuery < ::Search::Queries::Audit::Query
        attr_reader :project

        # Construct a ProjectQuery.
        #
        # options - The options Hash.
        #   :project - The Project instance to search for.
        #   :latest_allowed_entry_time - The latest time to search for.
        #
        # Returns Search::Queries::Audit::ProjectQuery instance.
        def initialize(options = {}, &block)
          @project = options.fetch(:project)
          @latest_allowed_entry_time = options.fetch(:latest_allowed_entry_time, nil)
          super(options, &block)
        end

        def query_params
          {
            index: @index.name,
            type: "audit_entry",
          }
        end

        # The default sort ordering to use in the absence of a query or any
        # other sort information
        DEFAULT_SORT = %w[timestamp desc rank desc].freeze

        # The mapping of user-facing sort values to the corresponding values used
        # in the search index.
        SORT_MAPPINGS = {
          "timestamp" => "@timestamp",
          "rank" => "data.rank",
        }.freeze

        def filter_hash
          return @filter_hash if defined? @filter_hash

          actions = %w(
            project.create
            project.update
            project.close
            project.open
            project.delete
            project.link
            project.unlink
            project_column.create
            project_column.update
            project_column.move
            project_column.delete
            project_card.create
            project_card.update
            project_card.delete
            project_card.convert
            project_card.archive
            project_card.restore
            project_workflow.create
            project_workflow.update
            project_workflow.delete
          )
          qualifiers[:action].clear.must(actions)

          filters = {
            action: builder.action_filter(:action, execution: :or),
          }

          if @latest_allowed_entry_time.present?
            to = Time.parse(@latest_allowed_entry_time).utc
            qualifiers[:created].clear.must("<=#{to.iso8601}")
            filters[:@timestamp] = builder.date_range_filter(:@timestamp, :created)
          end

          @filter_hash = filters
        end

        # search for project_card.move actions that have a changes hash, an
        # empty changes means the card was moved within the same column
        def build_card_move_filter
          qualifiers[:action].clear.must("project_card.move")
          qualifiers[:"data.changes"].clear.must(:exists)

          filters = {
            "data.changes": builder.term_filter(:"data.changes"),
            action: builder.term_filter(:action),
          }

          Search::Filters::BoolFilter.new(filters).build
        end

        def build_query_filter
          action_filter = Search::Filters::BoolFilter.new(filter_hash[:action]).build

          filter = {
            bool: {
              must: [
                { term: { "data.project_id": @project.id } },
              ],
              must_not: [
                { term: { "data.catalog_service": "github/memex" } },
                { term: { "data.project_kind": "MemexProject" } },
              ],
              should: [
                action_filter,
                build_card_move_filter,
              ].compact,
              minimum_should_match: 1,
            },
          }

          if filter_hash[:@timestamp]
            timestamp_filter = Search::Filters::BoolFilter.new(filter_hash[:@timestamp]).build
            filter[:bool][:must] << timestamp_filter
          end

          filter
        end

        # Internal: Returns the sorting options Array.
        def build_sort
          return if sort.blank?

          build_sort_section(sort, "_score", SORT_MAPPINGS)
        end

        # Returns the default sort ordering to use in the absence of a query or
        # any other sort information.
        def default_sort
          DEFAULT_SORT
        end
      end
    end
  end
end
