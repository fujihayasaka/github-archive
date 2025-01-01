# typed: true
# frozen_string_literal: true

require_relative "../fast_test_helper"

class Localization::MoneyFormatterTest < GitHub::TestCase
  test "it properly formats BRL" do
    money = Billing::Money.new(123456, "BRl")

    assert_equal "R$ 1.234,56", format(money)
  end

  test "takes options" do
    money = Billing::Money.new(123456, "BRl")

    assert_equal "R$ 1.235", format(money, precision: 0)
  end

  test "reduces precision to zero when value is integer" do
    money = Billing::Money.new(100, "BRl")

    assert_equal "R$ 1", format(money)
  end

  test "does not reduce precision to zero when value is integer when user opts out" do
    money = Billing::Money.new(100, "BRl")

    assert_equal "R$ 1,00", format(money, integer_precision: 2)
  end

  test "will not include the currency when unit: false" do
    money = Billing::Money.new(100, "BRl")

    assert_equal "1,00", format(money, integer_precision: 2, unit: false)
  end

  test "#symbol_first? returns true when symbol goes first" do
    money = Billing::Money.new(100, "BRl")

    assert formatter.symbol_first?(money)
  end

  test "#symbol_first? returns true when symbol goes last" do
    money = Billing::Money.new(100, "RUB")

    refute formatter.symbol_first?(money)
  end

  def format(*args)
    formatter.format(*args)
  end

  def formatter
    null_rounder = Class.new do
      def round(value)
        value
      end
    end
    Localization::MoneyFormatter.new(rounder: null_rounder.new)
  end
end
