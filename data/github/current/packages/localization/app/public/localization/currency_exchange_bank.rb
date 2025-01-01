# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true
module Localization
  class CurrencyExchangeBank
    CURRENCY_CACHE_KEY = GitHub::Billing::Currency.key

    delegate :get_rate, :set_rate, :each_rate, to: :@bank

    def initialize(bank: self.class.default_bank)
      @bank = bank
      update_rates
    end

    def update_rates(force: false)
      if force || !cached?
        @bank.save_rates
        @bank.update_rates
      end

      # only if there are no rates
      unless @bank.get_rate("USD", "EUR")
        @bank.update_rates
      end
    rescue Money::Bank::NoAppId, SocketError, Net::OpenTimeout
      # always be able to exchange USD -> USD
      @bank.set_rate("USD", "USD", 1)
    end

    private

    def cached?
      GitHub.cache.exist?(CURRENCY_CACHE_KEY)
    end

    class << self
      def default_bank
        @default_bank ||= create_bank
      end

      private

      def create_bank
        Money::Bank::OpenExchangeRatesBank.new.tap do |bank|
          bank.app_id = GitHub.open_exchange_rates_app_id
          bank.ttl_in_seconds = 86400

          # setup caching to use GitHub.cache
          bank.cache = proc do |cache_value|
            if cache_value
              GitHub.cache.write(CURRENCY_CACHE_KEY, cache_value)
            else
              GitHub.cache.read(CURRENCY_CACHE_KEY)
            end
          end
        end
      end
    end
  end
end
