# typed: strict
# frozen_string_literal: true

module TradeControls
  module LocationTraits
    UKRAINE_BRAINTREE_COUNTRY = T.let(Braintree::Address::CountryNames.find { |c| c[1] == "UA" } || [], T::Array[String])
  end
end
