# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Coverage
    class CreateViewModelsForStats
      include GitHub::Memoizer
      private_class_method :new

      CoverageQueryParser = ::Search::Queries::SecurityCenter::CoverageQueryParser

      sig do
        params(
          actor: User,
          scope: T.any(Organization, Business),
          parser: CoverageQueryParser,
          stats: T::Array[SecurityCenter::Coverage::StatsDataQuery::Stat],
        ).returns(T::Array[::SecurityCenter::Coverage::StatsSummaryComponent::Data])
      end
      def self.call(actor:, scope:, parser:, stats:)
        new(actor: actor, scope: scope, parser: parser, stats: stats).call
      end

      sig do
        params(
          actor: User,
          scope: T.any(Organization, Business),
          parser: CoverageQueryParser,
          stats: T::Array[SecurityCenter::Coverage::StatsDataQuery::Stat],
        ).void
      end
      def initialize(actor:, scope:, parser:, stats:)
        @actor = actor
        @scope = scope
        @parser = parser
        @stats = stats
      end

      sig { returns(T::Array[::SecurityCenter::Coverage::StatsSummaryComponent::Data]) }
      def call
        @stats.map do |stat|
          coverage_display_name = RepositorySecurityCenterStatus.coverage_display_name_for(stat.feature_type)
          feature_display_name = RepositorySecurityCenterStatus.feature_display_name_for(stat.feature_type)
          enabled_aria_label = "#{stat.enabled_count} enabled repositories for #{feature_display_name} #{coverage_display_name}"
          disabled_aria_label = "#{stat.disabled_count} not enabled repositories for #{feature_display_name} #{coverage_display_name}"

          stats_data = [
            ::SecurityCenter::Coverage::StatComponent::Data.new(
              feature_type: coverage_display_name,
              eligible_count: stat.total_count,
              enabled: ::SecurityCenter::Coverage::StatComponent::DataItem.new(
                aria_label: enabled_aria_label,
                count: stat.enabled_count,
                href: coverage_path_url(feature: stat.feature_type, enabled: true),
              ),
              disabled: ::SecurityCenter::Coverage::StatComponent::DataItem.new(
                aria_label: disabled_aria_label,
                count: stat.disabled_count,
                href: coverage_path_url(feature: stat.feature_type, enabled: false),
              ),
            )
          ]

          stat.subfeature_stats.each do |subfeature_stat|
            next if subfeature_stat.feature_type == :code_scanning_auto_codeql

            coverage_display_name = RepositorySecurityCenterStatus.coverage_display_name_for(subfeature_stat.feature_type)
            enabled_aria_label = "#{subfeature_stat.enabled_count} enabled repositories for #{feature_display_name} #{coverage_display_name}"
            disabled_aria_label = "#{subfeature_stat.disabled_count} not enabled repositories for #{feature_display_name} #{coverage_display_name}"

            stats_data << ::SecurityCenter::Coverage::StatComponent::Data.new(
              feature_type: coverage_display_name,
              eligible_count: subfeature_stat.total_count,
              enabled: ::SecurityCenter::Coverage::StatComponent::DataItem.new(
                aria_label: enabled_aria_label,
                count: subfeature_stat.enabled_count,
                href: coverage_path_url(feature: subfeature_stat.feature_type, enabled: true),
              ),
              disabled: ::SecurityCenter::Coverage::StatComponent::DataItem.new(
                aria_label: disabled_aria_label,
                count: subfeature_stat.disabled_count,
                href: coverage_path_url(feature: subfeature_stat.feature_type, enabled: false),
              ),
            )
          end

          ::SecurityCenter::Coverage::StatsSummaryComponent::Data.new(
            title: feature_display_name,
            enabled_percentage: percentage(stat.enabled_count, stat.total_count),
            stats_data: stats_data,
          )
        end
      end

      private

      sig { params(feature: Symbol, enabled: T::Boolean).returns(String) }
      def coverage_path_url(feature:, enabled:)
        if @scope.is_a? Business
          urls.security_center_coverage_enterprise_path(
            @scope,
            {
              query: @parser.add_or_replace(qualifier_for(feature), enabled ? "enabled" : "not-enabled")
            }
          )
        else
          urls.security_center_coverage_path(
            @scope,
            {
              query: @parser.add_or_replace(qualifier_for(feature), enabled ? "enabled" : "not-enabled")
            }
          )
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

      sig { returns(UrlHelpers) }
      memoize def urls
        T.cast(Class.new { include UrlHelpers }.new, UrlHelpers)
      end
    end
  end
end
