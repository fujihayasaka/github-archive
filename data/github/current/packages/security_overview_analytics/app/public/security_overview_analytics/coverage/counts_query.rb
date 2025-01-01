# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Coverage
    class CountsQuery < AbstractQuery
      include GitHub::Memoizer

      class Result < T::Struct
        const :active_count, Integer
        const :archived_count, Integer
        const :total_entries, Integer
        const :total_pages, Integer
      end

      sig { params(page_size: Integer).returns(Result) }
      def perform(page_size: 25)
        return Result.new(
          active_count: 0,
          archived_count: 0,
          total_entries: 0,
          total_pages: 0,
        ) if visible_features.empty?

        GitHub.dogstats.distribution_time("security_center.coverage_counts_data_query.run.dist", tags: datadog_tags) do
          query_data(page_size:)
        end
      end

      sig { params(page_size: Integer).returns(Result) }
      def query_data(page_size: 25)
        query = Repository
          .joins(:feature_status_summary)
          .where(
            repository_id: @repos_filterer
              .any_feature_repo_metadata_rel
              .unscope(where: :archived) # we need counts for both active/archived
              .select(:repository_id)
          )
          .then { |rel| @features_filterer.apply(rel) }
          .select(
            Arel.sql("SUM(IF(`#{Repository.table_name}`.`archived` = 1, 1, 0)) as total_archived_repos"),
            Arel.sql("SUM(IF(`#{Repository.table_name}`.`archived` = 0, 1, 0)) as total_active_repos")
          )

        db_result = ApplicationRecord::SecurityOverviewAnalytics.connection.select_one(query).to_hash.symbolize_keys
        active_count = db_result[:total_active_repos]&.to_i || 0
        archived_count = db_result[:total_archived_repos]&.to_i || 0

        archived_filters, _ = @parser.values_for_qualifier(CoverageQueryParser::ARCHIVED) # archived has no negative qualifier
        total_entries = if archived_filters.empty? || (archived_filters.include?("true") && archived_filters.include?("false"))
          archived_count + active_count
        elsif archived_filters.include?("true")
          archived_count
        else
          active_count
        end

        Result.new(
          active_count:,
          archived_count:,
          total_entries:,
          total_pages: WillPaginate::Collection.new(1, page_size, total_entries).total_pages,
        )
      end
    end
  end
end
