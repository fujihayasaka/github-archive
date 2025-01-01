# typed: strict
# frozen_string_literal: true

module MoneyHelper
  extend T::Sig
  extend T::Helpers

  include ActionView::Helpers::TagHelper

  sig { params(usd_in_cents: ::Billing::Types::Numeric).returns(String) }
  def money(usd_in_cents)
    converted = Billing::Money.new(usd_in_cents)
    converted.format(no_cents_if_whole: true)
  end

  sig { returns(String) }
  def location_currency_code
    GitHub.tracer.in_span("billing.money_helper") do |span|
      country_code = GitHub::Location.look_up(T.unsafe(self).request.remote_ip)[:country_code]
      currency_code = GitHub::Billing::Currency.currency_of(country_code)
      GitHub.dogstats.increment("billing.currency.money_helper.location_currency_code", tags: ["country_code:#{country_code}"])
      span.add_attributes({ "currency_code" => currency_code, "country_code" => country_code || "nil" })

      currency_code
    end
  end

  sig { params(price: ::Billing::Types::Numeric).returns(String) }
  def price_with_localization(price)
    content_tag(:span, price_with_localization_hash(price)[:default_currency], class: "default-currency") +
      content_tag(:span, price_with_localization_hash(price)[:local_currency], class: "local-currency")
  end

  sig { params(price: ::Billing::Types::Numeric).returns(T::Hash[Symbol, String]) }
  def price_with_localization_hash(price)
    @price_with_localization_hash ||= T.let({}, T.nilable(T::Hash[::Billing::Types::Numeric, T::Hash[Symbol, String]]))
    @price_with_localization_hash[price] ||= {
      default_currency: money(price).to_s,
      local_currency: money(price).to_s
    }
  end
end
