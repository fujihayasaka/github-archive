# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement
  class FailureReason
    extend T::Helpers
    abstract!

    sig { returns(Symbol) }
    attr_reader :symbol

    sig { params(symbol: Symbol).void }
    def initialize(symbol)
      @symbol = symbol
    end

    sig { abstract.returns(String) }
    def to_s
    end
  end
end
