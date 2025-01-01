# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Risk
    class CreateViewModelsForStats
      include GitHub::Memoizer
      private_class_method :new

      RiskQueryParser = ::Search::Queries::SecurityCenter::RiskQueryParser

      sig do
        params(
          actor: User,
          scope: T.any(Organization, Business),
          parser: RiskQueryParser,
          stats: T::Array[SecurityCenter::Risk::StatsDataQuery::Stat]
        ).returns(T::Array[::SecurityCenter::Risk::StatsSummaryComponent::Data])
      end
      def self.call(actor:, scope:, parser:, stats:)
        new(actor: actor, scope: scope, parser: parser, stats: stats).call
      end

      sig do
        params(
          actor: User,
          scope: T.any(Organization, Business),
          parser: RiskQueryParser,
          stats: T::Array[SecurityCenter::Risk::StatsDataQuery::Stat]
        ).void
      end
      def initialize(actor:, scope:, parser:, stats:)
        @actor = actor
        @scope = scope
        @parser = parser
        @stats = stats
      end

      sig { returns(T::Array[::SecurityCenter::Risk::StatsSummaryComponent::Data]) }
      def call
        @stats.map do |stat|
          unaffected_count = stat.total_repo_count - stat.affected_repo_count
          affected_aria_label = "#{stat.affected_repo_count} affected repositories with #{RepositorySecurityCenterStatus.feature_display_name_for(stat.feature_type)} alerts"
          unaffected_aria_label = "#{unaffected_count} unaffected repositories with #{RepositorySecurityCenterStatus.feature_display_name_for(stat.feature_type)} alerts"

          stats_data = T.let([
            ::SecurityCenter::Risk::StatComponent::Data.new(
              count: stat.total_repo_count,
              href: risk_path_url(stat.feature_type),
              title: "Repositories",
              items: [
                ::SecurityCenter::Risk::StatComponent::DataItem.new(
                  aria_label: affected_aria_label,
                  color_key: :affected,
                  count: stat.affected_repo_count,
                  href: risk_path_url(stat.feature_type, ">0"),
                  name: "affected",
                  percentage: percentage(stat.affected_repo_count, stat.total_repo_count),
                ),
                ::SecurityCenter::Risk::StatComponent::DataItem.new(
                  aria_label: unaffected_aria_label,
                  color_key: :unaffected,
                  count: unaffected_count,
                  href: risk_path_url(stat.feature_type, "not-enabled,0"),
                  name: "unaffected",
                  percentage: percentage(stat.total_repo_count - stat.affected_repo_count, stat.total_repo_count),
                ),
              ]
            ),
            ::SecurityCenter::Risk::StatComponent::Data.new(
              count: stat.open_alerts_count,
              href: risk_path_url(stat.feature_type),
              title: "Open alerts",
              items:
                if stat.open_alerts_by_severity.any?
                  stat.open_alerts_by_severity.map do |severity, alert_count|
                    ::SecurityCenter::Risk::StatComponent::DataItem.new(
                      aria_label: "#{alert_count} #{severity} open #{RepositorySecurityCenterStatus.feature_display_name_for(stat.feature_type)} alerts",
                      color_key: severity,
                      count: alert_count,
                      href: feature_severity_filter_url(stat.feature_type, severity),
                      name: severity.to_s,
                      percentage: percentage(alert_count, stat.open_alerts_count),
                    )
                  end
                else
                  [
                    # for features where we don't have severity breakdown, show the total count as a single segment
                    ::SecurityCenter::Risk::StatComponent::DataItem.new(
                      aria_label: "#{stat.open_alerts_count} alerts open #{RepositorySecurityCenterStatus.feature_display_name_for(stat.feature_type)} alerts",
                      color_key: :critical,
                      count: stat.open_alerts_count,
                      href: risk_path_url(stat.feature_type, ">0"),
                      name: "alerts",
                      percentage: percentage(stat.open_alerts_count, stat.open_alerts_count),
                    )
                  ]
                end
            ),
          ], T::Array[T.any(::SecurityCenter::Risk::StatComponent::Data, ::SecurityCenter::Risk::RemoteStatComponent::Data)])

          ::SecurityCenter::Risk::StatsSummaryComponent::Data.new(
            affected_percentage: percentage(stat.affected_repo_count, stat.total_repo_count),
            stats_data: stats_data,
            title: RepositorySecurityCenterStatus.feature_display_name_for(stat.feature_type),
          )
        end
      end

      private

      sig { params(feature: Symbol, value: String).returns(String) }
      def risk_path_url(feature, value = ">0")
        if @scope.is_a? Business
          urls.security_center_risk_enterprise_path(
            @scope,
            {
              query: @parser.add_or_replace(qualifier_for(feature), value)
            }
          )
        else
          urls.security_center_risk_path(
            @scope,
            {
              query: @parser.add_or_replace(qualifier_for(feature), value)
            }
          )
        end
      end

      sig { params(feature: Symbol, severity: Symbol).returns(String) }
      def feature_severity_filter_url(feature, severity)
        query = @parser.add_or_replace(qualifier_for(feature), ">0")

        # We lack support for augmenting a query with multiple qualifiers, as each method returns the resulting string.
        # We don't actually want to remove or replace this severity value; only add value if it doesn't already exist.
        query = @parser.class.new(query).add_or_remove(RiskQueryParser::HAS_SEVERITY, severity.to_s) unless @parser.pair_exists?(RiskQueryParser::HAS_SEVERITY, severity.to_s)

        if @scope.is_a? Business
          urls.security_center_risk_enterprise_path(@scope, { query: query })
        else
          urls.security_center_risk_path(@scope, { query: query })
        end
      end

      sig { params(n: Integer, d: Integer).returns(Integer) }
      def percentage(n, d)
        return 0 if d.zero?
        (n * 100) / d
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

      sig { returns(UrlHelpers) }
      memoize def urls
        T.cast(Class.new { include UrlHelpers }.new, UrlHelpers)
      end
    end
  end
end
