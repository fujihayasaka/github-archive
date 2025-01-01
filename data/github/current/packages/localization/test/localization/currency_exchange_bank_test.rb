# typed: true
# frozen_string_literal: true

require_relative "../fast_test_helper"

class Localization::CurrencyExchangeBankTest < GitHub::TestCase
  CACHE_KEY = Localization::CurrencyExchangeBank::CURRENCY_CACHE_KEY

  def setup
    clear_cache
    WebMock.disable_net_connect!(allow_localhost: false)
  end

  test "it reads currency from cache" do
    with_cache_enabled do
      warm_cache

      assert_equal 5.3, bank.get_rate("USD", "BRL")
    end
  end

  test "bank is shared across instance" do
    with_cache_enabled do
      warm_cache

      bank.set_rate("USD", "EUR", 5)

      another_bank = Localization::CurrencyExchangeBank.new

      assert_equal 5, another_bank.get_rate("USD", "EUR")
    end
  end

  test "#update_rates requests new rates" do
    with_cache_enabled do
      warm_cache

      bank # implicitly calls the method once

      clear_cache

      Money::Bank::OpenExchangeRatesBank.any_instance.expects(:save_rates).at_least_once
      Money::Bank::OpenExchangeRatesBank.any_instance.expects(:update_rates).at_least_once

      bank.update_rates
    end
  end

  test "loads from cache when rates when param force is passed" do
    with_cache_enabled do
      warm_cache
      bank

      Money::Bank::OpenExchangeRatesBank.any_instance.expects(:save_rates)

      bank.update_rates(force: true)
    end
  end

  test "it handles errors" do
    with_cache_enabled do
      warm_cache
      errors = [
        Money::Bank::NoAppId.new,
        SocketError.new,
        Net::OpenTimeout.new,
      ]

      errors.each do |error|
        Money::Bank::OpenExchangeRatesBank.any_instance.expects(:save_rates).raises(error)
        bank.update_rates(force: true)
      end

      assert true # we passed!
    end
  end

  private

  def bank
    @bank ||= Localization::CurrencyExchangeBank.new
  end

  def warm_cache
    GitHub.cache.write(CACHE_KEY, cached)
  end

  def clear_cache
    GitHub.cache.delete(CACHE_KEY)
  end

  def cached
    {
      "disclaimer" => "Usage subject to terms: https://openexchangerates.org/terms",
      "license" => "https://openexchangerates.org/license",
      "timestamp" => 1614110400,
      "base" => "USD",
      "rates" => {
        "USD" => 1,
        "BRL" => 5.3
      }
    }.to_json
  end
end
