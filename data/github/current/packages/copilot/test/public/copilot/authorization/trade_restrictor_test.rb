# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::Authorization::TradeRestrictorTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  context "trade restrictions" do
    test "triggers a trade controls check but doesn't restrict the user because the country isn't in sanctioned countries", skip_enterprise: true do
      user = create(:user)
      context = Context.new
      context.push(country_code: "RU")
      context.push(region: "55")
      context.push(region_name: "Moscow")

      perform_enqueued_jobs(only: ::TradeControls::ComplianceCheckJob) do
        trade_restrictor = Copilot::Authorization::TradeRestrictor.new(Copilot::User.new(user))
        assert trade_restrictor.restricted?(context, {})
        assert_equal :TRADE_RESTRICTED_COUNTRY, trade_restrictor.restriction_type
        user.reload
        refute user.has_full_trade_restrictions?, "Expected user to not have full trade restrictions"
      end
    end

    test "triggers a trade controls check and restrict the user because the country is in sanctioned countries", skip_enterprise: true do
      user = create(:user)
      context = Context.new
      context.push(country_code: nil)
      context.push(region: nil)
      context.push(region_name: nil)

      country = T.must(TradeControls::Countries::SANCTIONED.first)

      GitHub::Location.stubs(:look_up).returns({ country_code: country.alpha2, region_name: country.region_name, region: country.region_code })
      GitHub.context.push(actor_ip: "127.0.0.1")

      perform_enqueued_jobs(only: ::TradeControls::ComplianceCheckJob) do
        trade_restrictor = Copilot::Authorization::TradeRestrictor.new(Copilot::User.new(user))
        assert trade_restrictor.restricted?(context, {})
        user.reload
        assert_equal :TRADE_RESTRICTED_COUNTRY, trade_restrictor.restriction_type
        assert user.has_full_trade_restrictions?, "Expected user to have full trade restrictions"
      end
    end

    context "trade_restricted" do
      test "trade_restricted" do
        user = create(:user, :fully_trade_restricted)
        trade_restrictor = Copilot::Authorization::TradeRestrictor.new(Copilot::User.new(user))
        assert trade_restrictor.restricted?(Context.new, {})
        assert_equal :TRADE_RESTRICTED, trade_restrictor.restriction_type
      end

      TradeControls::SdnScreeningTestHelper::COPILOT_AUTH_BLOCKED_COUNTRY_LIST.each do |country|
        test "trade_restricted_country for #{country.name}" do
          user = create(:user)
          disable_feature_flag(:sdn_copilot_vnext, user)
          context = Context.new
          context.push(country_code: country.alpha2)
          context.push(region: country.alpha3)
          context.push(region_name: country.name)

          trade_restrictor = Copilot::Authorization::TradeRestrictor.new(Copilot::User.new(user))
          assert trade_restrictor.restricted?(context, {})
          user.reload
          assert_equal :TRADE_RESTRICTED_COUNTRY, trade_restrictor.restriction_type
        end
      end

      test "trade_restricted_country sdn_copilot_vnext for Iran returns false" do
        user = create(:user)
        enable_feature_flag(:sdn_copilot_vnext, user)
        context = Context.new
        context.push(country_code: TradeControls::Countries::IRAN.alpha2)
        context.push(region: TradeControls::Countries::IRAN.alpha3)
        context.push(region_name: TradeControls::Countries::IRAN.name)

        trade_restrictor = Copilot::Authorization::TradeRestrictor.new(Copilot::User.new(user))
        refute trade_restrictor.restricted?(context, {})
        user.reload
        assert_equal :UNKNOWN_LOCATION, trade_restrictor.restriction_type
      end
    end
  end
end if GitHub.copilot_enabled?
