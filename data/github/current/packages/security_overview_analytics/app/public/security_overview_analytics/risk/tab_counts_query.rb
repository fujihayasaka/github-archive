# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Risk
    class TabCountsQuery < AbstractQuery
      Result = T.type_alias do
        T::Hash[Symbol, T.nilable(Integer)]
      end

      sig { returns(Result) }
      def perform
        return {} if visible_features.empty?

        GitHub.dogstats.distribution_time("security_center.tab_counts_query.run.dist", tags: datadog_tags) do
          query_data
        end
      end

      private

      sig { returns(Result) }
      def query_data
        queries = T.let([], T::Array[ActiveRecord::Relation])
        base_query = Repository.joins(:feature_status_summary)

        if visible_features.include?(:dependabot_alerts)
          queries << base_query
            .where(repository_id: @repos_filterer.dbot_repo_metadata_rel.select(:repository_id))
            .where(archived: false)
            .select(
              Arel.sql("'dependabot_alerts' AS feature_type"),
              Arel.sql("SUM(`#{FeatureStatus.table_name}`.`dependabot_alerts_total_count`) AS total_alert_count"),
            )
        end

        if visible_features.include?(:code_scanning)
          queries << base_query
            .where(repository_id: @repos_filterer.cs_repo_metadata_rel.select(:repository_id))
            .where(archived: false)
            .select(
              Arel.sql("'code_scanning' AS feature_type"),
              Arel.sql("SUM(`#{FeatureStatus.table_name}`.`code_scanning_alerts_total_count`) AS total_alert_count"),
            )
        end

        if visible_features.include?(:secret_scanning)
          queries << base_query
            .where(repository_id: @repos_filterer.ss_repo_metadata_rel.select(:repository_id))
            # FYI: Secret scanning does not exclude archived repositories
            .select(
              Arel.sql("'secret_scanning' AS feature_type"),
              Arel.sql("SUM(`#{FeatureStatus.table_name}`.`secret_scanning_alerts_total_count`) AS total_alert_count"),
            )
        end

        queries
          .map { |query| Repository.connection.select_one(query, async: true) }
          .map(&:value)
          .map(&:symbolize_keys)
          .each_with_object({}) do |result, memo|
            result => { feature_type:, total_alert_count: }
            memo[feature_type.to_sym] = total_alert_count&.to_i || 0
          end
      end
    end
  end
end
