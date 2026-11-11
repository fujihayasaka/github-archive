# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Coverage
    class StatsQuery < AbstractQuery
      include GitHub::Memoizer

      Summary = ::SecurityCenter::Coverage::StatsSummaryComponent::Data
      Data = ::SecurityCenter::Coverage::StatComponent::Data
      DataItem = ::SecurityCenter::Coverage::StatComponent::DataItem

      class Result < T::Struct
        const :items, T::Array[Summary]
      end

      sig { returns(Result) }
      def perform
        return Result.new(items: []) if visible_features.empty?

        GitHub.dogstats.distribution_time("security_center.coverage_stats_data_query.run.dist", tags: datadog_tags) do
          query_data
        end
      end

      private

      sig { returns(Result) }
      def query_data
        query = Repository
          .joins(:feature_status_summary)
          .where(repository_id: @repos_filterer.any_feature_repo_metadata_rel.select(:repository_id))
          .then { |rel| @features_filterer.apply(rel) }
          .select(
            Arel.sql("COUNT(*) AS total_repo_count"),
            Arel.sql("SUM(IF(`#{FeatureStatus.table_name}`.`dependabot_alerts_status` = 'ENABLED', 1, 0)) AS dependabot_alerts_enrolled_count"),
            Arel.sql("SUM(IF(`#{FeatureStatus.table_name}`.`dependabot_security_updates_status` = 'ENABLED', 1, 0)) AS dependabot_security_updates_enrolled_count"),
            Arel.sql("SUM(IF(`#{FeatureStatus.table_name}`.`code_scanning_alerts_status` = 'ENABLED', 1, 0)) AS code_scanning_alerts_enrolled_count"),
            Arel.sql("SUM(IF(`#{FeatureStatus.table_name}`.`code_scanning_pr_reviews_status` = 'ENABLED', 1, 0)) AS code_scanning_pr_reviews_enrolled_count"),
            Arel.sql("SUM(IF(`#{FeatureStatus.table_name}`.`code_scanning_auto_codeql_status` = 'ENABLED', 1, 0)) AS code_scanning_auto_codeql_enrolled_count"),
            Arel.sql("SUM(IF(`#{FeatureStatus.table_name}`.`secret_scanning_alerts_status` = 'ENABLED', 1, 0)) AS secret_scanning_alerts_enrolled_count"),
            Arel.sql("SUM(IF(`#{FeatureStatus.table_name}`.`secret_scanning_push_protection_status` = 'ENABLED', 1, 0)) AS secret_scanning_push_protection_enrolled_count"),
          )

        db_result = ApplicationRecord::SecurityOverviewAnalytics.connection.select_one(query).to_hash.symbolize_keys
        total_repo_count = db_result[:total_repo_count]&.to_i || 0

        items = T.let([], T::Array[Summary])

        if visible_features.include?(:dependabot_alerts)
          items << to_summary_view_model(
            :dependabot_alerts,
            [
              to_data_view_model(
                :dependabot_alerts,
                db_result[:dependabot_alerts_enrolled_count]&.to_i || 0,
                total_repo_count,
              ),
              to_data_view_model(
                :dependabot_security_updates,
                db_result[:dependabot_security_updates_enrolled_count]&.to_i || 0,
                total_repo_count,
              ),
            ]
          )
        end

        if visible_features.include?(:code_scanning)
          items << to_summary_view_model(
            :code_scanning,
            [
              to_data_view_model(
                :code_scanning,
                db_result[:code_scanning_alerts_enrolled_count]&.to_i || 0,
                total_repo_count,
              ),
              to_data_view_model(
                :code_scanning_pr_reviews,
                db_result[:code_scanning_pr_reviews_enrolled_count]&.to_i || 0,
                total_repo_count,
              ),
            ]
          )
        end

        if visible_features.include?(:secret_scanning)
          items << to_summary_view_model(
            :secret_scanning,
            [
              to_data_view_model(
                :secret_scanning,
                db_result[:secret_scanning_alerts_enrolled_count]&.to_i || 0,
                total_repo_count,
              ),
              to_data_view_model(
                :secret_scanning_push_protection,
                db_result[:secret_scanning_push_protection_enrolled_count]&.to_i || 0,
                total_repo_count,
              ),
            ]
          )
        end

        Result.new(items:)
      end

      sig do
        params(
          feature_type: Symbol,
          stats_data: T::Array[Data],
        )
        .returns(Summary)
      end
      def to_summary_view_model(feature_type, stats_data)
        primary_stat = T.must(stats_data.first)

        Summary.new(
          title: feature_display_name_for(feature_type),
          enabled_percentage: percentage(primary_stat.enabled.count, primary_stat.eligible_count),
          stats_data: stats_data,
        )
      end

      sig do
        params(
          feature_type: Symbol,
          enabled_count: Integer,
          total_count: Integer,
        )
        .returns(Data)
      end
      def to_data_view_model(feature_type, enabled_count, total_count)
        feature_display_name = feature_display_name_for(feature_type)
        coverage_display_name = coverage_display_name_for(feature_type)
        disabled_count = total_count - enabled_count

        Data.new(
          feature_type: coverage_display_name,
          eligible_count: total_count,
          enabled: DataItem.new(
            count: enabled_count,
            href: coverage_path_url(feature: feature_type, enabled: true),
            aria_label: "#{enabled_count} enabled repositories for #{feature_display_name} #{coverage_display_name}",
          ),
          disabled: DataItem.new(
            count: disabled_count,
            href: coverage_path_url(feature: feature_type, enabled: false),
            aria_label: "#{disabled_count} not enabled repositories for #{feature_display_name} #{coverage_display_name}",
          )
        )
      end

      sig { params(feature: Symbol, enabled: T::Boolean).returns(String) }
      def coverage_path_url(feature:, enabled:)
        query = @parser.add_or_replace(qualifier_for(feature), enabled ? "enabled" : "not-enabled")
        if @scope.is_a? Business
          UrlHelpers.security_center_coverage_enterprise_path(@scope, { query: })
        else
          UrlHelpers.security_center_coverage_path(@scope, { query: })
        end
      end

      sig { params(feature_type: Symbol).returns(Symbol) }
      def qualifier_for(feature_type)
        case feature_type
        when :dependabot_alerts then CoverageQueryParser::DEPENDABOT_ALERTS
        when :dependabot_security_updates then CoverageQueryParser::DEPENDABOT_SECURITY_UPDATES
        when :code_scanning then CoverageQueryParser::CODE_SCANNING
        when :code_scanning_pr_reviews then CoverageQueryParser::CODE_SCANNING_PR_ALERTS
        when :code_scanning_auto_codeql then CoverageQueryParser::CODE_SCANNING_DEFAULT_SETUP
        when :secret_scanning then CoverageQueryParser::SECRET_SCANNING
        when :secret_scanning_push_protection then CoverageQueryParser::SECRET_SCANNING_PUSH_PROTECTION
        else raise ArgumentError, "Unknown feature type: #{feature_type}"
        end
      end

      sig { params(n: Integer, d: Integer).returns(Integer) }
      def percentage(n, d)
        return 0 if d.zero?
        (n * 100) / d
      end
    end
  end
end
