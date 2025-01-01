# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Coverage
    class CoverageCreateViewModelsForStatsTest < GitHub::TestCase
      fixtures do
        @admin = create(:user)
        @org = create(:organization, admin: @admin)
      end

      setup do
        @stats = create_statuses(:dependabot_alerts, :dependabot_security_updates)
      end

      test "it creates view models for stats" do
        view_models = ::SecurityCenter::Coverage::CreateViewModelsForStats.call(
          actor: @admin,
          scope: @org,
          parser: ::Search::Queries::SecurityCenter::CoverageQueryParser.new(""),
          stats: @stats,
        )

        assert_equal 1, view_models.size
        view_model = T.must(view_models[0])

        # stats_data
        stats_data = view_model.stats_data
        assert_equal 2, stats_data.size

        feature = T.must(stats_data[0])
        assert_equal "Alerts", feature.feature_type
        assert_equal 10, feature.enabled.count
        assert_equal 20, feature.disabled.count
        assert_equal 30, feature.eligible_count
        assert_equal "/orgs/#{@org}/security/coverage?query=dependabot-alerts%3Aenabled", feature.enabled.href
        assert_equal "/orgs/#{@org}/security/coverage?query=dependabot-alerts%3Anot-enabled", feature.disabled.href
        assert_equal "10 enabled repositories for Dependabot Alerts", feature.enabled.aria_label
        assert_equal "20 not enabled repositories for Dependabot Alerts", feature.disabled.aria_label

        subfeature = T.must(stats_data[1])
        assert_equal "Security updates", subfeature.feature_type
        assert_equal 20, subfeature.enabled.count
        assert_equal 40, subfeature.disabled.count
        assert_equal 60, subfeature.eligible_count
        assert_equal "/orgs/#{@org}/security/coverage?query=dependabot-security-updates%3Aenabled", subfeature.enabled.href
        assert_equal "/orgs/#{@org}/security/coverage?query=dependabot-security-updates%3Anot-enabled", subfeature.disabled.href
        assert_equal "20 enabled repositories for Dependabot Security updates", subfeature.enabled.aria_label
        assert_equal "40 not enabled repositories for Dependabot Security updates", subfeature.disabled.aria_label

        # summary_data
        assert_equal 33, view_model.enabled_percentage
        assert_equal "Dependabot", view_model.title
      end

      context "Code scanning Default Setup" do
        test "hide Auto CodeQL subfeature" do
          status = create_statuses(:code_scanning, :code_scanning_auto_codeql)

          view_models = ::SecurityCenter::Coverage::CreateViewModelsForStats.call(
            actor: @admin,
            scope: @org,
            parser: ::Search::Queries::SecurityCenter::CoverageQueryParser.new(""),
            stats: status,
          )

          assert_equal 1, view_models.size
          view_model = T.must(view_models[0])

          # stats_data
          assert_equal 1, view_model.stats_data.size
        end
      end

      def create_statuses(feature_type, subfeature_type)
        stat_subfeature = ::SecurityCenter::Coverage::StatsDataQuery::Stat.new(
          disabled_count: 40,
          enabled_count: 20,
          feature_type: subfeature_type,
          subfeature_stats: [],
          total_count: 60
        )

        stat = ::SecurityCenter::Coverage::StatsDataQuery::Stat.new(
          disabled_count: 20,
          enabled_count: 10,
          feature_type: feature_type,
          subfeature_stats: [stat_subfeature],
          total_count: 30
        )

        [stat]
      end
    end
  end
end
