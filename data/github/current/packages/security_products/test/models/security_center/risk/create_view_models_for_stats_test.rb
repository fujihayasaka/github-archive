# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Risk
    class RiskCreateViewModelsForStatsTest < GitHub::TestCase
      fixtures do
        GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?
        @business = create(:global_business)
        @actor = create(:user)
        @org = create(:business_plus_organization, business: @business)
      end

      setup do
        @feature_to_stats = {
          dependabot_alerts: @stat_dependabot_alerts = ::SecurityCenter::Risk::StatsDataQuery::Stat.new(
            affected_repo_count: 10,
            feature_type: :dependabot_alerts,
            open_alerts_count: 20,
            open_alerts_by_severity: { critical: 1, high: 2, medium: 3, low: 4 },
            total_repo_count: 30
          ),
          code_scanning: @stat_code_scanning_alerts = ::SecurityCenter::Risk::StatsDataQuery::Stat.new(
            affected_repo_count: 40,
            feature_type: :code_scanning,
            open_alerts_count: 50,
            open_alerts_by_severity: { critical: 1, high: 2, medium: 3, low: 4 },
            total_repo_count: 60
          ),
          secret_scanning: @stat_secret_scanning_alerts = ::SecurityCenter::Risk::StatsDataQuery::Stat.new(
            affected_repo_count: 70,
            feature_type: :secret_scanning,
            open_alerts_count: 80,
            open_alerts_by_severity: { critical: 1, high: 2, medium: 3, low: 4 },
            total_repo_count: 90
          )
        }

        @stats = @feature_to_stats.values
      end

      context ".call" do
        test "it returns view models" do
          view_models = ::SecurityCenter::Risk::CreateViewModelsForStats.call(
            actor: @actor,
            scope: @org,
            parser: ::Search::Queries::SecurityCenter::RiskQueryParser.new(""),
            stats: @stats
          )
          assert_equal(3, view_models.size)

          view_model_dependabot = T.cast(view_models[0], ::SecurityCenter::Risk::StatsSummaryComponent::Data)
          view_model_code_scanning = T.cast(view_models[1], ::SecurityCenter::Risk::StatsSummaryComponent::Data)
          view_model_secret_scanning = T.cast(view_models[2], ::SecurityCenter::Risk::StatsSummaryComponent::Data)

          assert_equal("Dependabot", view_model_dependabot.title)
          assert_equal("Code scanning", view_model_code_scanning.title)
          assert_equal("Secret scanning", view_model_secret_scanning.title)

          assert_equal(33, view_model_dependabot.affected_percentage)
          assert_equal(66, view_model_code_scanning.affected_percentage)
          assert_equal(77, view_model_secret_scanning.affected_percentage)

          assert_summary_stats(view_model_dependabot.stats_data, :dependabot_alerts)
          assert_summary_stats(view_model_code_scanning.stats_data, :code_scanning)
          assert_summary_stats(view_model_secret_scanning.stats_data, :secret_scanning)
        end
      end

      context "#feature_severity_filter_url" do
        test "returns url with feature and severity terms" do
          sut = create_instance("")
          result = sut.send(:feature_severity_filter_url, :dependabot_alerts, :critical)
          expected = "dependabot-alerts:>0 has-severity:critical"
          assert_equal "/orgs/#{@org}/security/risk?query=#{CGI.escape(expected)}", result
        end

        test "handles duplicate filter pair" do
          sut = create_instance("dependabot-alerts:>0 has-severity:critical")
          result = sut.send(:feature_severity_filter_url, :dependabot_alerts, :critical)
          expected = "dependabot-alerts:>0 has-severity:critical"
          assert_equal "/orgs/#{@org}/security/risk?query=#{CGI.escape(expected)}", result
        end

        test "handles duplicate feature value" do
          sut = create_instance("dependabot-alerts:>0 has-severity:critical")
          result = sut.send(:feature_severity_filter_url, :dependabot_alerts, :high)
          expected = "dependabot-alerts:>0 has-severity:critical,high"
          assert_equal "/orgs/#{@org}/security/risk?query=#{CGI.escape(expected)}", result
        end

        test "handles duplicate severity value" do
          sut = create_instance("dependabot-alerts:>0 has-severity:critical")
          result = sut.send(:feature_severity_filter_url, :code_scanning, :critical)
          expected = "dependabot-alerts:>0 has-severity:critical code-scanning-alerts:>0"
          assert_equal "/orgs/#{@org}/security/risk?query=#{CGI.escape(expected)}", result
        end
      end

      private

      def create_instance(query_string)
        ::SecurityCenter::Risk::CreateViewModelsForStats.send(:new,
          actor: @actor,
          scope: @org,
          parser: ::Search::Queries::SecurityCenter::RiskQueryParser.new(query_string),
          stats: @stats
        )
      end

      sig do
        params(
          summary_stats: T::Array[T.any(SecurityCenter::Risk::StatComponent::Data, SecurityCenter::Risk::RemoteStatComponent::Data)],
          feature: Symbol,
          scope: T.any(Organization, Business)
        ).void
      end
      def assert_summary_stats(summary_stats, feature, scope: @org)
        input_stat = @feature_to_stats[feature]

        assert_equal 2, summary_stats.size

        feature_to_qualifier = {
          dependabot_alerts: ::Search::Queries::SecurityCenter::RiskQueryParser::DEPENDABOT_ALERTS,
          code_scanning: ::Search::Queries::SecurityCenter::RiskQueryParser::CODE_SCANNING,
          secret_scanning: ::Search::Queries::SecurityCenter::RiskQueryParser::SECRET_SCANNING
        }
        query = CGI.escape("#{feature_to_qualifier[feature]}:>0")
        expected_href = if scope.is_a? Organization
          "/orgs/#{@org}/security/risk?query=#{query}"
        else
          "/enterprises/#{@business}/security/risk?query=#{query}"
        end

        # Affected repos
        repos_affected_stat = T.cast(summary_stats[0], ::SecurityCenter::Risk::StatComponent::Data)
        assert_equal(input_stat.total_repo_count, repos_affected_stat.count)
        assert_equal(expected_href, repos_affected_stat.href)
        assert_equal("Repositories", repos_affected_stat.title)
        assert_equal(2, repos_affected_stat.items.length)
        assert_equal("affected", repos_affected_stat.items[0]&.name)
        assert_equal(input_stat.affected_repo_count, repos_affected_stat.items[0]&.count)
        assert_equal("unaffected", repos_affected_stat.items[1]&.name)
        assert_equal(input_stat.total_repo_count - input_stat.affected_repo_count, repos_affected_stat.items[1]&.count)

        # Open alerts
        open_alerts_stat = T.cast(summary_stats[1], ::SecurityCenter::Risk::StatComponent::Data)
        assert_equal(input_stat.open_alerts_count, open_alerts_stat.count)
        assert_equal(expected_href, open_alerts_stat.href)
        assert_equal("Open alerts", open_alerts_stat.title)
        assert_equal(input_stat.open_alerts_by_severity.length, open_alerts_stat.items.length)
        input_stat.open_alerts_by_severity.each_with_index do |(severity, count), index|
          assert_equal(severity.to_s, open_alerts_stat.items[index]&.name)
          assert_equal(count, open_alerts_stat.items[index]&.count)
          assert(open_alerts_stat.items[index]&.href.present?)
        end
      end
    end
  end
end
