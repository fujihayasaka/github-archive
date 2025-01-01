# typed: strict
# frozen_string_literal: true

module Copilot::Authorization
  module TradeComplianceHelper

    # Check if the account is trade restricted
    sig { params(account: User).returns(T::Boolean) }
    def account_trade_restricted?(account:)
      return false unless account.has_any_trade_restrictions?

      GitHub.logger.info("User is trade_restricted")
      GitHub.dogstats.increment("copilot.access.trade_restricted")
      true
    end

    # Private: Check if the account is in a country that is blocked for copilot access
    sig { params(account: User, country_code: T.nilable(String), region_name: T.nilable(String), region_code: T.nilable(String), city: T.nilable(String)).returns(T::Boolean) }
    def copilot_access_country_blocked?(account:, country_code:, region_name:, region_code:, city:)
      GitHub.logger.info("Checking if country code is blocked")

      # let's check this against our country list first
      TradeControls::Countries::copilot_auth_blocked_countries(actor: account).each do |country|
        next unless country_code == country.alpha2 # if this matches, you're blocked

        GitHub.logger.info("Country code is blocked", "gh.country_code" => country_code)
        GitHub.dogstats.increment("copilot.access.country_code_blocked")

        Copilot::Instrumenter.instrument_trade_restricted_country_block(
          account,
          country_code,
          region_code,
          region_name,
          city,
        )
        return true
      end

      GitHub.dogstats.increment("copilot.access.not_country_code_blocked")
      false
    end

    # Check if the account's region is blocked from accessing copilot
    # These TradeControls::Country objects look like this:
    #
    # TradeControls::Countries::CRIMEA
    # { alpha2="UA", alpha3="UKR", city=nil, domain="ua", name="Ukraine", region_code="43", region_name="Crimea" }
    #
    # We only care about these fields:
    # alpha2      is the same as the context.country_code
    # region_code is the same as the context.region
    # region_name is the same as the context.region_name
    sig { params(account: User, country_code: T.nilable(String), region_name: T.nilable(String), region_code: T.nilable(String), city: T.nilable(String)).returns(T::Boolean) }
    def copilot_access_region_blocked?(account:, country_code:, region_name:, region_code:, city:)
      GitHub.logger.info("Checking if region is blocked")

      # let's check this against our region list first
      TradeControls::Countries::COPILOT_AUTH_BLOCKED_REGION_LIST.each do |blocked_region|
        # restrict this to country code in case any other country has a matching region
        same_region = region_name == blocked_region.region_name || region_code == blocked_region.region_code
        next if country_code != blocked_region.alpha2 || !same_region

        GitHub.logger.info("Region name / region are blocked", "gh.region" => region_code, "gh.region_name" => region_name)

        GitHub.dogstats.increment("copilot.access.region_name_blocked")

        Copilot::Instrumenter.instrument_trade_restricted_country_block(
          account,
          country_code,
          region_code,
          region_name,
          city,
        )
        return true
      end

      GitHub.dogstats.increment("copilot.access.not_region_blocked")
      false
    end
  end
end
