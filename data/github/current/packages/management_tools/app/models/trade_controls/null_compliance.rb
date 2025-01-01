# typed: strict
# frozen_string_literal: true

module TradeControls
  class NullCompliance
    include Compliance

    sig { params(kwargs: T.untyped).void }
    def initialize(**kwargs)
      @reason = T.let("", String)
    end

    sig { override.returns(T.any(String, Symbol)) }
    def reason
      @reason
    end
  end
end
