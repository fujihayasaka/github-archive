# typed: true
# frozen_string_literal: true

require_relative "../../fast_test_helper"

class Localization::CurrencyConfiguration::YamlConfigTest < GitHub::TestCase
  def setup
    @config = Localization::CurrencyConfiguration::YamlConfig.new
  end

  test "looks up configuration by money" do
    result = @config.lookup(Billing::Money.new(123, "BRL"))

    expected = {
      delimiter: ".",
      format: "%u %n",
      precision: 2,
      separator: ",",
      significant: false,
      strip_insignificant_zeros: false,
      integer_precision: 0,
      unit: "R$",
    }

    assert_equal expected, result
  end

  test "it raises error when currency is not defined" do
    money = Billing::Money.new(123, "BTC")

    error_class = Localization::CurrencyConfiguration::YamlConfig::ConfigNotFound
    error = assert_raises(error_class) { @config.lookup(money) }

    assert_equal error.message, "Could not find currency by iso code 'BTC'"
  end

  test "#all_currencies returns all the currencies declared in config/money.yml file" do
    currencies = @config.all_currencies

    assert currencies.include?("USD")
    refute currencies.include?("default_values")
    assert_equal 170, currencies.length
  end
end
