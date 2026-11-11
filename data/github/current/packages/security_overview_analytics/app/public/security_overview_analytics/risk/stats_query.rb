# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Risk
    class StatsQuery < AbstractQuery
      include GitHub::Memoizer

      Summary = ::SecurityCenter::Risk::StatsSummaryComponent::Data
      Data = ::SecurityCenter::Risk::StatComponent::Data
      DataItem = ::SecurityCenter::Risk::StatComponent::DataItem

      class Result < T::Struct
        const :items, T::Array[Summary]
      end

      sig { returns(Result) }
      def perform
        return Result.new(items: []) if visible_features.empty?

        GitHub.dogstats.distribution_time("security_center.risk_stats_data_query.run.dist", tags: datadog_tags) do
          query_data
        end
      end

      private

      sig { returns(Result) }
      def query_data
        items =
          if @repos_filterer.is_a?(Dashboards::OrgReposFilterer) && @repos_filterer.allowed_repo_ids_by_feature.present?
            # Non-admin org members have limited access to repositories by each feature type.
            # We have to query these separately so the stats match what you can actually see.
            [
              query_data_by_feature(:dependabot_alerts),
              query_data_by_feature(:code_scanning),
              query_data_by_feature(:secret_scanning),
            ].flatten
          else
            # Org owners and security managers aren't subject to repo accessibility restrictions
            # Because of that, they also get a _much_ simpler single query for these stats
            query_data_by_feature(nil)
          end

        Result.new(
          items:
        )
      end

      sig { params(feature_type: T.nilable(Symbol)).returns(T::Array[Summary]) }
      def query_data_by_feature(feature_type)
        repo_metadata_rel = \
          case feature_type
          when :dependabot_alerts
            @repos_filterer.dbot_repo_metadata_rel
          when :code_scanning
            @repos_filterer.cs_repo_metadata_rel
          when :secret_scanning
            @repos_filterer.ss_repo_metadata_rel
          else
            @repos_filterer.any_feature_repo_metadata_rel
          end

        select_fields = [
          Arel.sql("COUNT(*) AS total_repo_count")
        ]
        if visible_features.include?(:dependabot_alerts) && (feature_type.nil? || feature_type == :dependabot_alerts)
          select_fields.concat([
            Arel.sql("SUM(IF(`#{FeatureStatus.table_name}`.`dependabot_alerts_total_count` > 0, 1, 0)) AS dependabot_alerts_affected_repo_count"),
            Arel.sql("SUM(`#{FeatureStatus.table_name}`.`dependabot_alerts_total_count`) AS dependabot_alerts_total_count"),
            Arel.sql("SUM(`#{FeatureStatus.table_name}`.`dependabot_alerts_critical_count`) AS dependabot_alerts_critical_count"),
            Arel.sql("SUM(`#{FeatureStatus.table_name}`.`dependabot_alerts_high_count`) AS dependabot_alerts_high_count"),
            Arel.sql("SUM(`#{FeatureStatus.table_name}`.`dependabot_alerts_medium_count`) AS dependabot_alerts_medium_count"),
            Arel.sql("SUM(`#{FeatureStatus.table_name}`.`dependabot_alerts_low_count`) AS dependabot_alerts_low_count"),
          ])
        end
        if visible_features.include?(:code_scanning) && (feature_type.nil? || feature_type == :code_scanning)
          select_fields.concat([
            Arel.sql("SUM(IF(`#{FeatureStatus.table_name}`.`code_scanning_alerts_total_count` > 0, 1, 0)) AS code_scanning_alerts_affected_repo_count"),
            Arel.sql("SUM(`#{FeatureStatus.table_name}`.`code_scanning_alerts_total_count`) AS code_scanning_alerts_total_count"),
            Arel.sql("SUM(`#{FeatureStatus.table_name}`.`code_scanning_alerts_critical_count`) AS code_scanning_alerts_critical_count"),
            Arel.sql("SUM(`#{FeatureStatus.table_name}`.`code_scanning_alerts_high_count`) AS code_scanning_alerts_high_count"),
            Arel.sql("SUM(`#{FeatureStatus.table_name}`.`code_scanning_alerts_medium_count`) AS code_scanning_alerts_medium_count"),
            Arel.sql("SUM(`#{FeatureStatus.table_name}`.`code_scanning_alerts_low_count`) AS code_scanning_alerts_low_count"),
            Arel.sql("SUM(`#{FeatureStatus.table_name}`.`code_scanning_alerts_info_count`) AS code_scanning_alerts_info_count"),
          ])
        end
        if visible_features.include?(:secret_scanning) && (feature_type.nil? || feature_type == :secret_scanning)
          select_fields.concat([
            Arel.sql("SUM(IF(`#{FeatureStatus.table_name}`.`secret_scanning_alerts_total_count` > 0, 1, 0)) AS secret_scanning_alerts_affected_repo_count"),
            Arel.sql("SUM(`#{FeatureStatus.table_name}`.`secret_scanning_alerts_total_count`) AS secret_scanning_alerts_total_count"),
          ])
        end

        query = Repository
          .joins(:feature_status_summary)
          .then { |rel| rel.where(repository_id: repo_metadata_rel.select(:repository_id)) }
          .then { |rel| @features_filterer.apply(rel) }
          .select(*select_fields)

        db_result = ApplicationRecord::SecurityOverviewAnalytics.connection.select_one(query).to_hash.symbolize_keys
        total_repo_count = db_result[:total_repo_count]&.to_i || 0

        items = T.let([], T::Array[Summary])

        if db_result.key?(:dependabot_alerts_affected_repo_count)
          items << to_summary_view_model(
            :dependabot_alerts,
            [
              to_repos_data_view_model(
                :dependabot_alerts,
                db_result[:dependabot_alerts_affected_repo_count]&.to_i || 0,
                total_repo_count,
              ),
              to_alerts_data_view_model(
                :dependabot_alerts,
                db_result[:dependabot_alerts_total_count]&.to_i || 0,
                {
                  critical: db_result[:dependabot_alerts_critical_count]&.to_i || 0,
                  high: db_result[:dependabot_alerts_high_count]&.to_i || 0,
                  moderate: db_result[:dependabot_alerts_medium_count]&.to_i || 0,
                  low: db_result[:dependabot_alerts_low_count]&.to_i || 0,
                },
              )
            ]
          )
        end

        if db_result.key?(:code_scanning_alerts_affected_repo_count)
          items << to_summary_view_model(
            :code_scanning,
            [
              to_repos_data_view_model(
                :code_scanning,
                db_result[:code_scanning_alerts_affected_repo_count]&.to_i || 0,
                total_repo_count,
              ),
              to_alerts_data_view_model(
                :code_scanning,
                db_result[:code_scanning_alerts_total_count]&.to_i || 0,
                {
                  critical: db_result[:code_scanning_alerts_critical_count]&.to_i || 0,
                  high: db_result[:code_scanning_alerts_high_count]&.to_i || 0,
                  medium: db_result[:code_scanning_alerts_medium_count]&.to_i || 0,
                  low: db_result[:code_scanning_alerts_low_count]&.to_i || 0,
                  informational: db_result[:code_scanning_alerts_info_count]&.to_i || 0,
                },
              )
            ]
          )
        end

        if db_result.key?(:secret_scanning_alerts_affected_repo_count)
          items << to_summary_view_model(
            :secret_scanning,
            [
              to_repos_data_view_model(
                :secret_scanning,
                db_result[:secret_scanning_alerts_affected_repo_count]&.to_i || 0,
                total_repo_count,
              ),
              to_alerts_data_view_model(
                :secret_scanning,
                db_result[:secret_scanning_alerts_total_count]&.to_i || 0,
                # Secret scanning doesn't have a severity breakdown
              )
            ]
          )
        end

        items
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
        affected_stat_item = T.must(primary_stat.items.first)

        Summary.new(
          title: feature_display_name_for(feature_type),
          affected_percentage: percentage(affected_stat_item.count, primary_stat.count),
          stats_data:,
        )
      end

      sig do
        params(
          feature_type: Symbol,
          affected_count: Integer,
          total_count: Integer,
        )
        .returns(Data)
      end
      def to_repos_data_view_model(feature_type, affected_count, total_count)
        feature_display_name = feature_display_name_for(feature_type)
        unaffected_count = total_count - affected_count

        Data.new(
          title: "Repositories",
          count: total_count,
          href: risk_path_url(feature_type, ">0"),
          items: [
            DataItem.new(
              aria_label: "#{affected_count} affected repositories with #{feature_display_name} alerts",
              color_key: :affected,
              count: affected_count,
              href: risk_path_url(feature_type, ">0"),
              name: "affected",
              percentage: percentage(affected_count, total_count),
            ),
            DataItem.new(
              aria_label: "#{unaffected_count} unaffected repositories with #{feature_display_name} alerts",
              color_key: :unaffected,
              count: unaffected_count,
              href: risk_path_url(feature_type, "not-enabled,0"),
              name: "unaffected",
              percentage: percentage(unaffected_count, total_count),
            )
          ],
        )
      end

      sig do
        params(
          feature_type: Symbol,
          open_alerts_count: Integer,
          open_alerts_count_by_severity: T.nilable(T::Hash[Symbol, Integer]),
        )
        .returns(Data)
      end
      def to_alerts_data_view_model(feature_type, open_alerts_count, open_alerts_count_by_severity = nil)
        feature_display_name = feature_display_name_for(feature_type)

        # Remove any zero-value severities. If there are no alerts of any severity,
        # we want to fall through to the "0 alerts" item below
        open_alerts_count_by_severity&.delete_if { |_, v| v.nil? || v.zero? }

        Data.new(
          title: "Open alerts",
          count: open_alerts_count,
          href: risk_path_url(feature_type, ">0"),
          items: \
            if open_alerts_count_by_severity.present?
              open_alerts_count_by_severity.map do |severity, alert_count|
                DataItem.new(
                  aria_label: "#{alert_count} #{severity} open #{feature_display_name} alerts",
                  color_key: severity,
                  count: alert_count,
                  href: feature_severity_filter_url(feature_type, severity),
                  name: severity.to_s,
                  percentage: percentage(alert_count, open_alerts_count),
                )
              end
            else
              [
                # for features where we don't have severity breakdown, show the total count as a single segment
                DataItem.new(
                  aria_label: "#{open_alerts_count} alerts open #{feature_display_name} alerts",
                  color_key: :critical,
                  count: open_alerts_count,
                  href: risk_path_url(feature_type, ">0"),
                  name: "alerts",
                  percentage: percentage(open_alerts_count, open_alerts_count),
                )
              ]
            end,
        )
      end

      sig { params(feature: Symbol, value: String).returns(String) }
      def risk_path_url(feature, value)
        query = @parser.add_or_replace(qualifier_for(feature), value)
        if @scope.is_a? Business
          UrlHelpers.security_center_risk_enterprise_path(@scope, { query: })
        else
          UrlHelpers.security_center_risk_path(@scope, { query: })
        end
      end

      sig { params(feature: Symbol, severity: Symbol).returns(String) }
      def feature_severity_filter_url(feature, severity)
        query = @parser.add_or_replace(qualifier_for(feature), ">0")

        # We lack support for augmenting a query with multiple qualifiers, as each method returns the resulting string.
        # We don't actually want to remove or replace this severity value; only add value if it doesn't already exist.
        query = @parser.class.new(query).add_or_remove(RiskQueryParser::HAS_SEVERITY, severity.to_s) unless @parser.pair_exists?(RiskQueryParser::HAS_SEVERITY, severity.to_s)

        if @scope.is_a? Business
          UrlHelpers.security_center_risk_enterprise_path(@scope, { query: })
        else
          UrlHelpers.security_center_risk_path(@scope, { query: })
        end
      end

      sig { params(feature_type: Symbol).returns(Symbol) }
      def qualifier_for(feature_type)
        case feature_type
        when :dependabot_alerts then RiskQueryParser::DEPENDABOT_ALERTS
        when :code_scanning then RiskQueryParser::CODE_SCANNING
        when :secret_scanning then RiskQueryParser::SECRET_SCANNING
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
