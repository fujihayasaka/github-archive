# typed: true
# frozen_string_literal: true

require "test_helper"

module Orgs
  module ApiInsights
    class BaseControllerTest < GitHub::IntegrationTestCase
      fixtures do
        @owner = create(:user)
        @business = create(:business, :metered_ghec)
        @org = create(:organization, admin: @owner, business: @business)
      end

      setup do
        enable_feature_flag(:actions_usage_metrics)
      end

      if !GitHub.single_tenant_enterprise?

        context "default_page_params" do
          test "provides defaults" do
            as @owner
            get "/orgs/#{@org.display_login}/insights/api"

            expected_values = {
              p: 1,
              tr: "desc",
              period: "24h",
              interval: "1h",
              type: "all",
              requests: "all",
              t: "UTC"
            }
            assert_equal expected_values, @controller.send(:default_page_params)
          end

          test "uses query params if valid" do
            as @owner
            get "/orgs/#{@org.display_login}/insights/api?q=foo&p=2&n=asc&tr=asc&rlr=asc&lrl=asc&period=7d&interval=3h&type=installation&requests=rate&t=local"

            expected_values = {
              q: "foo",
              p: 2,
              n: "asc",
              tr: "asc",
              rlr: "asc",
              lrl: "asc",
              period: "7d",
              interval: "3h",
              type: "installation",
              requests: "rate",
              t: "local"
            }
            assert_equal expected_values, @controller.send(:default_page_params)
          end

          test "validates page" do
            as @owner
            get "/orgs/#{@org.display_login}/insights/api?p=-20"

            expected_values = {
              p: 1,
              tr: "desc",
              period: "24h",
              interval: "1h",
              type: "all",
              requests: "all",
              t: "UTC"
            }
            assert_equal expected_values, @controller.send(:default_page_params)
          end

          test "validates sort" do
            as @owner
            get "/orgs/#{@org.display_login}/insights/api?n=foo&tr=bar&rlr=baz&lrl=qux"

            expected_values = {
              p: 1,
              n: "desc",
              tr: "desc",
              rlr: "desc",
              lrl: "desc",
              period: "24h",
              interval: "1h",
              type: "all",
              requests: "all",
              t: "UTC"
            }
            assert_equal expected_values, @controller.send(:default_page_params)
          end

          test "validates period" do
            as @owner
            get "/orgs/#{@org.display_login}/insights/api?period=1w"

            expected_values = {
              p: 1,
              tr: "desc",
              period: "24h",
              interval: "1h",
              type: "all",
              requests: "all",
              t: "UTC"
            }
            assert_equal expected_values, @controller.send(:default_page_params)
          end

          test "validates interval" do
            as @owner
            get "/orgs/#{@org.display_login}/insights/api?interval=20z"

            expected_values = {
              p: 1,
              tr: "desc",
              period: "24h",
              interval: "1h",
              type: "all",
              requests: "all",
              t: "UTC"
            }
            assert_equal expected_values, @controller.send(:default_page_params)
          end

          test "validates type" do
            as @owner
            get "/orgs/#{@org.display_login}/insights/api?type=dogs"

            expected_values = {
              p: 1,
              tr: "desc",
              period: "24h",
              interval: "1h",
              type: "all",
              requests: "all",
              t: "UTC"
            }
            assert_equal expected_values, @controller.send(:default_page_params)
          end

          test "validates requests" do
            as @owner
            get "/orgs/#{@org.display_login}/insights/api?requests=cats"

            expected_values = {
              p: 1,
              tr: "desc",
              period: "24h",
              interval: "1h",
              type: "all",
              requests: "all",
              t: "UTC"
            }
            assert_equal expected_values, @controller.send(:default_page_params)
          end

          test "validates timezone" do
            as @owner
            get "/orgs/#{@org.display_login}/insights/api?t=cats"

            expected_values = {
              p: 1,
              tr: "desc",
              period: "24h",
              interval: "1h",
              type: "all",
              requests: "all",
              t: "UTC"
            }
            assert_equal expected_values, @controller.send(:default_page_params)
          end

          test "does not include table filters if has_table_filters is false" do
            as @owner
            get "/orgs/#{@org.display_login}/insights/api"

            expected_values = {
              p: 1,
              tr: "desc",
              period: "24h",
              interval: "1h",
              t: "UTC"
            }
            assert_equal expected_values, @controller.send(:default_page_params, has_table_filters: false)
          end

          test "provides a default range of 1 hour if from and to are invalid" do
            travel_to "2024-10-01 02:12:34 PDT" do
              as @owner
              get "/orgs/#{@org.display_login}/insights/api?period=custom&from=foo&to=bar"
              expected_values = {
                period: "custom",
                t: "UTC",
                interval: "30m",
                type: "all",
                requests: "all",
                p: 1,
                from: "2024-10-01T08:12:34.000Z",
                to: "2024-10-01T09:12:34.000Z",
                tr: "desc",
              }
              assert_equal expected_values, @controller.send(:default_page_params)
            end
          end

          test "swaps from and to if they are in incorrect order" do
            travel_to "2024-10-01 02:12:34 PDT" do
              as @owner
              get "/orgs/#{@org.display_login}/insights/api?period=custom&to=2024-09-07T08:12:34.123Z&from=2024-09-07T09:12:34.456Z"
              expected_values = {
                period: "custom",
                t: "UTC",
                interval: "30m",
                type: "all",
                requests: "all",
                p: 1,
                from: "2024-09-07T08:12:34.123Z",
                to: "2024-09-07T09:12:34.456Z",
                tr: "desc",
              }
              assert_equal expected_values, @controller.send(:default_page_params)
            end
          end

          test "adds fallback if missing from and to" do
            travel_to "2024-10-01 02:12:34 PDT" do
              as @owner
              get "/orgs/#{@org.display_login}/insights/api?period=custom"
              expected_values = {
                period: "custom",
                t: "UTC",
                interval: "30m",
                type: "all",
                requests: "all",
                p: 1,
                from: "2024-10-01T08:12:34.000Z",
                to: "2024-10-01T09:12:34.000Z",
                tr: "desc",
              }
              assert_equal expected_values, @controller.send(:default_page_params)
            end
          end

          test "clamps dates if in future or before 31 days" do
            travel_to "2024-10-01 02:12:34 PDT" do
              as @owner
              get "/orgs/#{@org.display_login}/insights/api?period=custom&to=2023-10-01T08:12:34.000Z&from=2025-10-01T09:12:34.000Z"
              expected_values = {
                period: "custom",
                t: "UTC",
                interval: "1h",
                type: "all",
                requests: "all",
                p: 1,
                from: "2024-08-31T09:12:34.000Z",
                to: "2024-10-01T09:12:34.000Z",
                tr: "desc",
              }
              assert_equal expected_values, @controller.send(:default_page_params)
            end
          end
        end

        context "min_time_and_max_time" do
          test "returns min and max time for a named period" do
            travel_to "2024-10-01 02:03:04 PDT" do
              as @owner
              get "/orgs/#{@org.display_login}/insights/api?period=30m"

              min, max = @controller.send(:min_time_and_max_time)
              assert_equal Time.now.to_i, max.to_i
              assert_equal (Time.now - 30.minutes).to_i, min.to_i
            end
          end

          test "returns custom min and max time" do
            travel_to "2024-10-01 02:12:34 PDT" do
              as @owner
              get "/orgs/#{@org.display_login}/insights/api?period=custom&from=2024-09-07T08:12:34.123Z&to=2024-09-07T09:12:34.456Z"
              expected_values = {
                period: "custom",
                t: "UTC",
                interval: "30m",
                type: "all",
                requests: "all",
                p: 1,
                from: "2024-09-07T08:12:34.123Z",
                to: "2024-09-07T09:12:34.456Z",
                n: "desc",
                tr: "desc",
                rlr: "desc",
                lrl: "desc",
              }
              min, max = @controller.send(:min_time_and_max_time)
              assert_equal Time.parse("2024-09-07T08:12:34.123Z").to_i, min.to_i
              assert_equal Time.parse("2024-09-07T09:12:34.456Z").to_i, max.to_i
            end
          end
        end

        context "feedback link" do

          test "feedback link is GitHub Discussions" do
            as @owner
            get "/orgs/#{@org.display_login}/insights/api?period=30m"
            assert_equal "https://github.co/api-insights-discussion", @controller.send(:feedback_link)
          end
        end
      end
    end
  end
end
