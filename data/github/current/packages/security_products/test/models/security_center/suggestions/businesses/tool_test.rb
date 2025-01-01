# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Suggestions
    module Businesses
      class ToolTest < GitHub::TestCase
        include ::SecurityCenter::TestFixtures
        include ::SecurityCenter::TurboscanTestSetup

        fixtures do
          create_business_level_fixtures
        end

        setup do
          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: true,
            secret_scanning_enabled_for_instance?: true,
            dependabot_alerts_enabled_for_instance?: true,
          )

          @security_features_parser = ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser.new(
            query: ::Search::Queries::SecurityCenter::QueryParser.new(""),
            scope: @business,
            authorized_orgs: @business.organizations.to_a,
          )
        end

        test "Tool suggestions reflect instance-enabled features" do
          GitHub::Turboscan
            .expects(:tool_names_for_org)
            .never

          ::SecurityCenter::SecurityFeatures.expects(:visible_features).once.with(@business).returns([
            ::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS,
            ::SecurityCenter::SecurityFeatures::SECRET_SCANNING,
          ])

          expected = [
            Suggestion.new(value: "github", label: "All GitHub tools"),
            Suggestion.new(value: "dependabot", label: "Dependabot"),
            Suggestion.new(value: "secret-scanning", label: "Secret scanning"),
          ]

          suggestions = Tool.new(
            security_features_parser: @security_features_parser,
            value: ""
          ).suggestions

          assert_same_elements(expected, suggestions)
        end
      end
    end
  end
end
