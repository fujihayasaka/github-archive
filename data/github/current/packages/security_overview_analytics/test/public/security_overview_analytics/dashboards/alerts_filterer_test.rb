# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Dashboards
    class AlertsFiltererTest < GitHub::TestCase
      include ::SecurityOverviewAnalytics::TestFixtures

      QueryParser = ::Search::Queries::SecurityCenter::QueryParser

      fixtures do
        create_alert_fixtures_with_severity_and_resolution
      end

      setup do
        SecurityOverviewAnalytics::FeatureFlagHelper.stubs(:use_alerts_filterer_class?).returns(true)
      end

      context "cs_alert_rel" do
        context "when no filters are applied" do
          test "it includes codeql and 3rd party tools" do
            rel = AlertsFilterer.new(
              query: QueryParser.new, scope: @org, user: @org_admin
            ).cs_alert_rel([Overview::SecurityFeaturesParser::TOOL_CODEQL, @cs_6.tool, @cs_7.tool].to_set)

            assert_same_elements([@cs_1.id, @cs_2.id, @cs_3.id, @cs_4.id, @cs_5.id, @cs_6.id, @cs_7.id], rel.pluck(:id))
          end
        end

        context "when querying by 'resolution'" do
          test "doesn't apply filter when flag is off" do
            SecurityOverviewAnalytics::FeatureFlagHelper.stubs(:use_alerts_filterer_class?).with(:resolution, @org, @org_admin).returns(false)
            rel = AlertsFilterer.new(
                query: QueryParser.new("resolution:risk-accepted"),
                scope: @org,
                user: @org_admin
              ).cs_alert_rel([Overview::SecurityFeaturesParser::TOOL_CODEQL, @cs_6.tool, @cs_7.tool].to_set)

            assert_same_elements([@cs_1.id, @cs_2.id, @cs_3.id, @cs_4.id, @cs_5.id, @cs_6.id, @cs_7.id], rel.pluck(:id))
          end

          test "it returns all CodeQL alerts with valid resolutions" do
            rel = AlertsFilterer
              .new(
                query: QueryParser.new("resolution:risk-accepted"),
                scope: @org,
                user: @org_admin
              )
              .cs_alert_rel([Overview::SecurityFeaturesParser::TOOL_CODEQL].to_set)

            assert_same_elements([@cs_2.id, @cs_3.id], rel.pluck(:id))
          end

          test "it returns an empty result for invalid resolutions" do
            rel = AlertsFilterer
              .new(
                query: QueryParser.new("resolution:foo"),
                scope: @org,
                user: @org_admin
              )
              .cs_alert_rel([Overview::SecurityFeaturesParser::TOOL_CODEQL].to_set)

            assert_empty rel.pluck(:id)
          end
        end

        context "when querying by 'severity'" do
          test "doesn't apply filter when flag is off" do
            SecurityOverviewAnalytics::FeatureFlagHelper.stubs(:use_alerts_filterer_class?).with(:severity, @org, @org_admin).returns(false)
            rel = AlertsFilterer.new(
                query: QueryParser.new("severity:medium"),
                scope: @org,
                user: @org_admin
              ).cs_alert_rel([Overview::SecurityFeaturesParser::TOOL_CODEQL, @cs_6.tool, @cs_7.tool].to_set)

            assert_same_elements([@cs_1.id, @cs_2.id, @cs_3.id, @cs_4.id, @cs_5.id, @cs_6.id, @cs_7.id], rel.pluck(:id))
          end

          test "it returns all CodeQL alerts with valid severities" do
            rel = AlertsFilterer
              .new(
                query: QueryParser.new("severity:medium,critical"),
                scope: @org,
                user: @org_admin
              )
              .cs_alert_rel([Overview::SecurityFeaturesParser::TOOL_CODEQL].to_set)

            assert_same_elements([@cs_1.id, @cs_3.id, @cs_4.id, @cs_5.id], rel.pluck(:id))
          end

          test "it returns an empty result for invalid severities" do
            rel = AlertsFilterer
              .new(
                query: QueryParser.new("severity:foo"),
                scope: @org,
                user: @org_admin
              )
              .cs_alert_rel([Overview::SecurityFeaturesParser::TOOL_CODEQL].to_set)

            assert_empty rel.pluck(:id)
          end
        end

        context "when querying by tool-centric filters" do
          context "code scanning filters" do
            test "it filters codeql alerts based on rule" do
              rel = AlertsFilterer.new(
                query: ::Search::Queries::SecurityCenter::QueryParser.new("codeql.rule:rule/some-rule"),
                scope: @org,
                user: @org_admin
              ).cs_alert_rel([Overview::SecurityFeaturesParser::TOOL_CODEQL].to_set)

              assert_same_elements([@cs_2.id, @cs_3.id, @cs_4.id, @cs_5.id], rel.pluck(:id))
            end

            test "it filters third party alerts based on rule" do
              rel = AlertsFilterer.new(
                query: ::Search::Queries::SecurityCenter::QueryParser.new("third-party.rule:rule/some-rule"),
                scope: @org,
                user: @org_admin
              ).cs_alert_rel(["tool-1"].to_set)

              assert_same_elements([@cs_6.id], rel.pluck(:id))
            end

            test "it returns an empty result if both codeql and third-party rules are specified" do
              rel = AlertsFilterer.new(
                query: ::Search::Queries::SecurityCenter::QueryParser.new("codeql.rule:rule/some-rule third-party.rule:rule/some-rule"),
                scope: @org,
                user: @org_admin
              ).cs_alert_rel([Overview::SecurityFeaturesParser::TOOL_CODEQL, "tool-1"].to_set)

              assert_empty rel.pluck(:id)
            end

            test "it filters alerts when the rule contains non-alphanumeric characters" do
              rel = AlertsFilterer.new(
                query: ::Search::Queries::SecurityCenter::QueryParser.new("third-party.rule:rule/a,f unkyR\"u/le\'"),
                scope: @org,
                user: @org_admin
              ).cs_alert_rel(["tool-2"].to_set)

              assert_same_elements([@cs_7.id], rel.pluck(:id))
            end
          end

          test "filters specific to secret scanning returns nothing for code scanning" do
            rel = AlertsFilterer
              .new(
                query: ::Search::Queries::SecurityCenter::QueryParser.new("secret-scanning.bypassed:true"),
                scope: @org,
                user: @org_admin
              )
              .cs_alert_rel([Overview::SecurityFeaturesParser::TOOL_CODEQL].to_set)

            assert_empty rel.pluck(:id)
          end

          test "filters specific to dependabot returns nothing for code scanning" do
            rel = AlertsFilterer.new(
              query: ::Search::Queries::SecurityCenter::QueryParser.new("dependabot.ecosystem:npm"),
              scope: @org,
                user: @org_admin
            ).cs_alert_rel([Overview::SecurityFeaturesParser::TOOL_CODEQL].to_set)

            assert_empty rel.pluck(:id)
          end
        end

        context "when querying by slices" do
          test "it filters alerts based on slice" do
            rel = AlertsFilterer.new(
              query: QueryParser.new, scope: @org, user: @org_admin, slice4: 0
            ).cs_alert_rel([Overview::SecurityFeaturesParser::TOOL_CODEQL, @cs_6.tool, @cs_7.tool].to_set)

            assert_same_elements([@cs_4.id], rel.pluck(:id))
          end
        end
      end

      context "dbot_alert_rel" do
        context "when no filters are applied" do
          test "it returns all Dbot alerts" do
            rel = AlertsFilterer.new(
                query: QueryParser.new,
                scope: @org,
                user: @org_admin
              ).dbot_alert_rel

            assert_same_elements([@dbot_1.id, @dbot_2.id, @dbot_4.id, @dbot_5.id, @dbot_6.id], rel.pluck(:id))
          end
        end

        context "when querying by 'resolution'" do
          test "doesn't apply filter when flag is off" do
            SecurityOverviewAnalytics::FeatureFlagHelper.stubs(:use_alerts_filterer_class?).with(:resolution, @org, @org_admin).returns(false)
            rel = AlertsFilterer.new(
                query: QueryParser.new("resolution:risk-accepted"),
                scope: @org,
                user: @org_admin
              ).dbot_alert_rel

            assert_same_elements([@dbot_1.id, @dbot_2.id, @dbot_4.id, @dbot_5.id, @dbot_6.id], rel.pluck(:id))
          end

          test "it returns all Dbot alerts with valid resolutions" do
            rel = AlertsFilterer
              .new(
                query: QueryParser.new("resolution:fixed-or-revoked"),
                scope: @org,
                user: @org_admin
              )
              .dbot_alert_rel

            assert_same_elements([@dbot_1.id], rel.pluck(:id))
          end

          test "it returns an empty result for invalid resolutions" do
            rel = AlertsFilterer
              .new(
                query: QueryParser.new("resolution:foo"),
                scope: @org,
                user: @org_admin
              )
              .dbot_alert_rel

            assert_empty rel.pluck(:id)
          end
        end

        context "when querying by 'severity'" do
          test "doesn't apply filter when flag is off" do
            SecurityOverviewAnalytics::FeatureFlagHelper.stubs(:use_alerts_filterer_class?).with(:severity, @org, @org_admin).returns(false)
            rel = AlertsFilterer.new(
                query: QueryParser.new("severity:medium"),
                scope: @org,
                user: @org_admin
              ).dbot_alert_rel

            assert_same_elements([@dbot_1.id, @dbot_2.id, @dbot_4.id, @dbot_5.id, @dbot_6.id], rel.pluck(:id))
          end

          test "it returns all Dbot alerts with valid severities" do
            rel = AlertsFilterer
              .new(
                query: QueryParser.new("severity:medium,high"),
                scope: @org,
                user: @org_admin
              )
              .dbot_alert_rel

            assert_same_elements([@dbot_2.id], rel.pluck(:id))
          end

          test "it returns an empty result for invalid severities" do
            rel = AlertsFilterer
              .new(
                query: QueryParser.new("severity:foo"),
                scope: @org,
                user: @org_admin
              )
              .dbot_alert_rel

            assert_empty rel.pluck(:id)
          end
        end

        context "when querying by tool-centric filters" do
          context "dependabot filters" do
            test "it filters alerts based on ecosystem" do
              rel = AlertsFilterer.new(
                query: ::Search::Queries::SecurityCenter::QueryParser.new("dependabot.ecosystem:npm"),
                scope: @org,
                user: @org_admin
              ).dbot_alert_rel

              assert_same_elements([@dbot_1.id, @dbot_2.id], rel.pluck(:id))
            end

            test "it filters alerts based on package name" do
              rel = AlertsFilterer.new(
                query: ::Search::Queries::SecurityCenter::QueryParser.new("dependabot.package:package-2"),
                scope: @org,
                user: @org_admin
              ).dbot_alert_rel

              assert_same_elements([@dbot_4.id, @dbot_5.id, @dbot_6.id], rel.pluck(:id))
            end

            test "it filters alerts based on dependency scope" do
              rel = AlertsFilterer.new(
                query: ::Search::Queries::SecurityCenter::QueryParser.new("dependabot.scope:runtime"),
                scope: @org,
                user: @org_admin
              ).dbot_alert_rel

              assert_same_elements([@dbot_1.id, @dbot_2.id], rel.pluck(:id))
            end
          end

          test "filters specific to secret scanning returns nothing for dependabot" do
            rel = AlertsFilterer
              .new(
                query: ::Search::Queries::SecurityCenter::QueryParser.new("secret-scanning.bypassed:true"),
                scope: @org,
                user: @org_admin
              )
              .dbot_alert_rel

            assert_empty rel.pluck(:id)
          end

          test "filters specific to code scanning returns nothing for dependabot" do
            rel = AlertsFilterer.new(
              query: ::Search::Queries::SecurityCenter::QueryParser.new("rule:codeql/javascript-xss"),
              scope: @org,
                user: @org_admin
            ).dbot_alert_rel

            # TODO - purposely putting the wrong assertion here so it'll fail once code scanning filters are implemented
            assert_same_elements([@dbot_1.id, @dbot_2.id, @dbot_4.id, @dbot_5.id, @dbot_6.id], rel.pluck(:id))
          end
        end

        context "when querying by slices" do
          test "it filters alerts based on slice" do
            rel = AlertsFilterer.new(
                query: QueryParser.new,
                scope: @org,
                user: @org_admin,
                slice4: 0
              ).dbot_alert_rel

            assert_same_elements([@dbot_1.id, @dbot_5.id], rel.pluck(:id))
          end
        end
      end

      context "ss_alert_rel" do
        context "when no filters are applied" do
          test "it returns all SS alerts" do
            rel = AlertsFilterer.new(
                query: QueryParser.new,
                scope: @org,
                user: @org_admin
              ).ss_alert_rel

            assert_same_elements([@ss_1.id, @ss_2.id, @ss_3.id, @ss_4.id, @ss_5.id, @ss_6.id], rel.pluck(:id))
          end
        end

        context "when querying by 'resolution'" do
          test "doesn't apply filter when flag is off" do
            SecurityOverviewAnalytics::FeatureFlagHelper.stubs(:use_alerts_filterer_class?).with(:resolution, @org, @org_admin).returns(false)
            rel = AlertsFilterer.new(
                query: QueryParser.new("resolution:risk-accepted"),
                scope: @org,
                user: @org_admin
              ).ss_alert_rel

            assert_same_elements([@ss_1.id, @ss_2.id, @ss_3.id, @ss_4.id, @ss_5.id, @ss_6.id], rel.pluck(:id))
          end

          test "it returns all SS alerts with valid resolutions" do
            rel = AlertsFilterer
              .new(
                query: QueryParser.new("resolution:auto-dismissed"),
                scope: @org,
                user: @org_admin
              )
              .ss_alert_rel

            assert_same_elements([@ss_2.id], rel.pluck(:id))
          end

          test "it returns an empty result for invalid resolutions" do
            rel = AlertsFilterer
              .new(
                query: QueryParser.new("resolution:foo"),
                scope: @org,
                user: @org_admin
              )
              .ss_alert_rel

            assert_empty rel.pluck(:id)
          end
        end

        context "when querying by 'severity'" do
          test "doesn't apply filter when flag is off" do
            SecurityOverviewAnalytics::FeatureFlagHelper.stubs(:use_alerts_filterer_class?).with(:severity, @org).returns(false)
            rel = AlertsFilterer.new(
                query: QueryParser.new("severity:critical"),
                scope: @org,
                user: @org_admin
              ).ss_alert_rel

            assert_same_elements([@ss_1.id, @ss_2.id, @ss_3.id, @ss_4.id, @ss_5.id, @ss_6.id], rel.pluck(:id))
          end

          test "it returns all SS alerts with valid severities" do
            rel = AlertsFilterer
              .new(
                query: QueryParser.new("severity:critical"),
                scope: @org,
                user: @org_admin
              )
              .ss_alert_rel

            assert_same_elements([@ss_1.id, @ss_2.id, @ss_3.id, @ss_4.id, @ss_5.id, @ss_6.id], rel.pluck(:id))
          end

          test "it returns an empty result for invalid severities" do
            rel = AlertsFilterer
              .new(
                query: QueryParser.new("severity:low"),
                scope: @org,
                user: @org_admin
              )
              .ss_alert_rel

            assert_empty rel.pluck(:id)
          end
        end

        context "when querying by tool-centric filters" do
          context "secret scanning filters" do
            test "it filters alerts based on bypassed status" do
              rel = AlertsFilterer.new(
                query: ::Search::Queries::SecurityCenter::QueryParser.new("secret-scanning.bypassed:true"),
                scope: @org,
                user: @org_admin
              ).ss_alert_rel

              assert_same_elements([@ss_1.id, @ss_4.id, @ss_5.id], rel.pluck(:id))
            end

            test "it filters alerts based on validity status" do
              rel = AlertsFilterer.new(
                query: ::Search::Queries::SecurityCenter::QueryParser.new("secret-scanning.validity:inactive,unknown"),
                scope: @org,
                user: @org_admin
              ).ss_alert_rel

              assert_same_elements([@ss_2.id, @ss_3.id, @ss_4.id, @ss_5.id, @ss_6.id], rel.pluck(:id))
            end

            test "it filters alerts based on token provider" do
              rel = AlertsFilterer.new(
                query: ::Search::Queries::SecurityCenter::QueryParser.new("secret-scanning.provider:amazon_aws"),
                scope: @org,
                user: @org_admin
              ).ss_alert_rel

              assert_same_elements([@ss_1.id, @ss_4.id], rel.pluck(:id))
            end

            test "it filters alerts based on token slug" do
              rel = AlertsFilterer.new(
                query: ::Search::Queries::SecurityCenter::QueryParser.new("secret-scanning.secret-type:github_token,cp_1"),
                scope: @org,
                user: @org_admin
              ).ss_alert_rel

              assert_same_elements([@ss_2.id, @ss_3.id, @ss_5.id], rel.pluck(:id))
            end

            context "with aliases" do
              test "it filters alerts based on validity status" do
                rel = AlertsFilterer.new(
                  query: ::Search::Queries::SecurityCenter::QueryParser.new("validity:inactive,unknown"),
                  scope: @org,
                  user: @org_admin
                ).ss_alert_rel

                assert_same_elements([@ss_2.id, @ss_3.id, @ss_4.id, @ss_5.id, @ss_6.id], rel.pluck(:id))
              end

              test "it filters alerts based on token provider" do
                rel = AlertsFilterer.new(
                  query: ::Search::Queries::SecurityCenter::QueryParser.new("provider:amazon_aws"),
                  scope: @org,
                  user: @org_admin
                ).ss_alert_rel

                assert_same_elements([@ss_1.id, @ss_4.id], rel.pluck(:id))
              end

              test "it filters alerts based on token slug" do
                rel = AlertsFilterer.new(
                  query: ::Search::Queries::SecurityCenter::QueryParser.new("secret-type:github_token,cp_1"),
                  scope: @org,
                  user: @org_admin
                ).ss_alert_rel

                assert_same_elements([@ss_2.id, @ss_3.id, @ss_5.id], rel.pluck(:id))
              end
            end
          end

          test "filters specific to code scanning returns nothing for secret scanning" do
            rel = AlertsFilterer.new(
              query: ::Search::Queries::SecurityCenter::QueryParser.new("codeql.rule:javascript-xss"),
              scope: @org,
              user: @org_admin
            ).ss_alert_rel

            assert_empty rel.pluck(:id)
          end

          test "filters specific to dependabot returns nothing for secret scanning" do
            rel = AlertsFilterer.new(
              query: ::Search::Queries::SecurityCenter::QueryParser.new("dependabot.ecosystem:npm"),
              scope: @org,
              user: @org_admin
            ).ss_alert_rel

            assert_empty rel.pluck(:id)
          end
        end

        context "when querying by slices" do
          test "it filters alerts based on slice" do
            rel = AlertsFilterer.new(
                query: QueryParser.new,
                scope: @org,
                user: @org_admin,
                slice4: 0
              ).ss_alert_rel

            assert_same_elements([@ss_1.id, @ss_5.id], rel.pluck(:id))
          end
        end
      end
    end
  end
end
