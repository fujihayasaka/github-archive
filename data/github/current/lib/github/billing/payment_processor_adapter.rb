# typed: strict
# frozen_string_literal: true

module GitHub::Billing
  # Base class for all payment processor adapters to translate from PaymentMethod to
  # disperate payment processor APIs
  class PaymentProcessorAdapter
    extend T::Sig

    sig { params(attributes: T.nilable(T::Hash[T.any(String, Symbol), T.untyped])).void }
    def initialize(attributes = nil)
      attributes ||= {}
      attributes.each_key do |name|
        instance_variable_set :"@#{name}", attributes[name]
      end
    end
  end
end
