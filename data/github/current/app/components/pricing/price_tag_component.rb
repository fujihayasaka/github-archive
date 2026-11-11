# typed: true
# frozen_string_literal: true

module Pricing
  class PriceTagComponent < ApplicationComponent
    CURRENCY = "USD"
    RENDER_MODES = [
      :plan_card,
      :comparison_table,
      :monthly_and_annual,
      :default
    ]

    def initialize(plan:, render_mode: :plan_card, personal_plan_comparison: false, monthly_only: true)
      @plan = plan
      @formatter = Localization::MoneyFormatter.new(rounder: Localization::MoneyFormatter::NearestIntegerRoundingStrategy.new)
      @render_mode = render_mode.to_sym
      @personal_plan_comparison = personal_plan_comparison
      @monthly_only = monthly_only

      unless RENDER_MODES.include?(@render_mode)
        raise ArgumentError.new("Invalid render_mode: #{@render_mode}")
      end
    end

    def symbol_first?
      @formatter.symbol_first?(localized_money)
    end

    def localized_unit_cost_monthly
      @formatter.format(localized_money, integer_precision: 0, unit: false)
    end

    def localized_unit_cost_yearly
      formatted_money(plan_yearly_cost_in_cents)
    end

    def currency_symbol
      symbol
    end

    def per_month_suffix
      case @render_mode
      when :monthly_and_annual
        @personal_plan_comparison ? "per month" : "per user / month"
      else
        free? || pro? ? "per month" : "per user/month"
      end
    end

    def per_year_suffix
      case @render_mode
      when :monthly_and_annual
        if free?
          @personal_plan_comparison ? "per month forever" : "per user / forever"
        else
          @personal_plan_comparison ? "per month" : "per user / month"
        end
      else
        free? || pro? ? "per month" : "per user/month"
      end
    end

    def formatted_price
      @formatter.format(localized_money, integer_precision: 0)
    end
    alias to_s formatted_price

    def render_in_plan_card?
      @render_mode == :plan_card
    end

    def render_default?
      @render_mode == :default
    end

    def render_in_comparison_table?
      @render_mode == :comparison_table
    end

    def render_monthly_and_annual?
      @render_mode == :monthly_and_annual
    end

    private

    def formatted_price_in_usd
      @formatter.format(money, integer_precision: 0)
    end

    def formatted_money(money, formatter_preference = @formatter)
      formatter_preference.format(
        localized_money(money),
        integer_precision: 0,
        unit: false,
      )
    end

    def monthly_only?
      @monthly_only
    end

    def free?
      plan_cost_in_cents.zero?
    end

    def pro?
      @plan.name == "pro"
    end

    def localized_money(value_in_cents = nil)
      money(value_in_cents)
    end

    def money(value_in_cents = nil)
      value_in_cents ||= plan_cost_in_cents
      Billing::Money.new(value_in_cents, CURRENCY, bank)
    end

    def symbol
      money.symbol
    end

    memoize def bank
      Money::Bank::VariableExchange.new(Localization::CurrencyExchangeBank.new)
    end

    def plan_cost_in_cents
      @plan.cost * 100
    end

    def plan_yearly_cost_in_cents
      (@plan.yearly_cost * 100).fdiv(12).round(0)
    end

    def plan_name
      @plan.name
    end
  end
end
