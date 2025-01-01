# typed: true
# frozen_string_literal: true

require "csv"

module GitHub::Billing::Currency
  # Public: Initialize exchange rates
  #
  # Returns true when finished, false if already set up
  def self.setup
    if !Money.default_bank.is_a?(Money::Bank::OpenExchangeRatesBank) && GitHub.billing_enabled?
      Money.default_bank = open_exchange_rates_bank
      update_rates
      country_to_currency
      true
    else
      false
    end
  end

  def self.open_exchange_rates_bank
    Money::Bank::OpenExchangeRatesBank.new.tap do |bank|
      bank.app_id = GitHub.open_exchange_rates_app_id

      # setup caching to use GitHub.cache
      bank.cache = proc do |v|
        if v
          GitHub.cache.set(key, v, 1.day)

          ActiveRecord::Base.connected_to(role: :writing) do
            GitHub.kv.set(key, v) # rubocop:todo GitHub/DoNotUseGlobalKv
          end
        else
          result = GitHub.cache.get(key)
          metric = !!result ? "cache.hit" : "cache.miss"
          GitHub.dogstats.increment(metric, tags: ["billing:open_exchange_rates"])
          result
        end
      end
    end
  end

  # Public: Get the currency code for a country
  #
  # country_code - Two character country code
  #
  # Returns a String of the three character currency code
  def self.currency_of(country_code)
    GitHub.dogstats.increment("billing.currency.currency_of", tags: ["country_code:#{country_code}"])

    # get currency for country
    currency = country_to_currency[country_code] || "USD"

    # ensure exchange rate exists
    begin
      currency = default_bank.get_rate("USD", currency) ? currency : "USD"
    rescue Money::Currency::UnknownCurrency
      currency = "USD"
    end

    currency
  end

  # Internal: Return the default exchange bank for Money. Sets up the bank on demand.
  def self.default_bank
    setup unless Money.default_bank.is_a? Money::Bank::OpenExchangeRatesBank
    Money.default_bank
  end

  class << self

  end

  # Internal: Country to currency mapping
  #
  # Returns a Hash
  def self.country_to_currency
    @country_to_currency ||= load_currencies
  end

  # Internal: Load the country data file
  #
  # Returns an Array
  def self.load_currencies
    # Orginally from https://github.com/datasets/country-codes/blob/master/data/country-codes.csv
    # and edited. Not updated since Dec 2013 since ISO no longer provides free data files.
    currency_mapping_csv = CSV.read(File.join(Rails.root, "config/country-codes.csv"))
    GitHub.dogstats.increment("billing.currency.load_currencies")
    currency_mapping_csv.inject({}) do |memo, row|
      # column 2 - ISO3166-1-Alpha-2
      # column -6 - currency_alphabetic_code
      memo[row.fetch(2)] = row.fetch(-6)
      memo
    end
  end

  # Internal: Exchange rate cache key
  #
  # Returns a String
  def self.key
    "currency:exchange_rates"
  end

  # Internal: Whether the exchange rates have been cached
  #
  # Returns a Boolean
  def self.cached?
    !!GitHub.cache.get(key)
  end

  # Public: Updates the rates from either the cache or from the exchange rate service
  #
  # force - if true, updates the rates even if cache exists. Defaults to false
  #
  # Returns Nothing
  def self.update_rates(force: false)
    if force || !cached?
      GitHub.dogstats.increment("billing.update_exchange_rates")
      default_bank.save_rates
    end
    default_bank.update_rates
  rescue StandardError => error
    Failbot.report!(error)
    GitHub.dogstats.increment("billing.update_exchange_rates.errors", tags: ["error:#{error.class}"])

    fallback = ActiveRecord::Base.connected_to(role: :reading) do
      GitHub.kv.get(key).value { nil } # rubocop:todo GitHub/DoNotUseGlobalKv
    end

    if fallback.present?
      GitHub.cache.set(key, fallback, 1.day)
      GitHub.dogstats.increment("billing.update_exchange_rates.fallbacks", tags: ["error:#{error.class}"])
      begin
        default_bank.update_rates
      rescue StandardError => error
        GitHub.dogstats.increment("billing.update_exchange_rates.fallbacks.errors", tags: ["error:#{error.class}"])
        nil
      end
    end

    # always be able to exchange USD -> USD
    default_bank.set_rate("USD", "USD", 1)
  end
end
