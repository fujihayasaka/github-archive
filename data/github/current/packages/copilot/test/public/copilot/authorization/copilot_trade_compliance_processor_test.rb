# typed: true
# frozen_string_literal: true

require "test_helper"

module Copilot::Authorization
  class CopilotTradeComplianceProcessorTest < GitHub::TestCase
    include HydroTestHelpers
    include CopilotTestHelper # automatically disables Copilot feature flags

    fixtures do
      skip unless GitHub.copilot_enabled?
      @user = create(:user)
    end

    setup do
      self.perform_enqueued_jobs = [::TradeControls::ComplianceCheckJob]
      @event_message = {
        user: @user,
        country_name: "United States",
        country_code: "US",
        region_name: "California",
        city: "San Francisco",
      }
    end

    context "trade restrictions" do
      test "triggers a trade controls check but doesn't restrict the user because the country isn't in sanctioned countries" do
        user = create(:user)
        message = {
          user: Hydro::EntitySerializer.user(user),
          country_code: "RU",
          region_name: "Moscow",
        }
        hydro_publisher.publish(message, schema: "copilot.v0.CopilotTradeCompliance")

        run_processor(Copilot::Authorization::CopilotTradeComplianceProcessor.new, allowed_primary_query_count: 10)

        user.reload
        refute user.has_full_trade_restrictions?, "Expected user to not have full trade restrictions"
      end

      test "triggers a trade controls check and restrict the user because the country is in sanctioned countries" do
        country = T.must(TradeControls::Countries::SANCTIONED.first)
        user = create(:user)
        message = {
          user: Hydro::EntitySerializer.user(user),
          country_code: country.alpha2,
          region_name: country.region_name,
          region_code: country.region_code,
        }
        hydro_publisher.publish(message, schema: "copilot.v0.CopilotTradeCompliance")

        run_processor(Copilot::Authorization::CopilotTradeComplianceProcessor.new, allowed_primary_query_count: 10)

        user.reload
        assert user.has_full_trade_restrictions?, "Expected user to have full trade restrictions"
      end

      context "trade_restricted" do
        test "trade_restricted" do
          country = T.must(TradeControls::Countries::SANCTIONED.first)
          user = create(:user, :fully_trade_restricted)
          message = {
            user: Hydro::EntitySerializer.user(user),
            country_code: country.alpha2,
            region_name: country.region_name,
            region_code: country.region_code,
          }
          hydro_publisher.publish(message, schema: "copilot.v0.CopilotTradeCompliance")
          Copilot::Instrumenter.expects(:instrument_trade_restricted_country_block).never

          run_processor(Copilot::Authorization::CopilotTradeComplianceProcessor.new, allowed_primary_query_count: 10)

          user.reload
          assert user.has_full_trade_restrictions?, "Expected user to have full trade restrictions"
        end

        TradeControls::Countries::SANCTIONED.each do |country|
          test "trade_restricted_country for #{country.name}" do
            user = create(:user)
            disable_feature_flag(:sdn_copilot_vnext, user)
            message = {
              user: Hydro::EntitySerializer.user(user),
              country_code: country.alpha2,
              region_name: country.region_name,
              region_code: country.region_code,
            }
            hydro_publisher.publish(message, schema: "copilot.v0.CopilotTradeCompliance")

            run_processor(Copilot::Authorization::CopilotTradeComplianceProcessor.new, allowed_primary_query_count: 10)

            user.reload
            assert user.has_full_trade_restrictions?, "Expected user to have full trade restrictions"
          end
        end
      end
    end
  end
end
