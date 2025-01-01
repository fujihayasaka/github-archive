# typed: strict
# frozen_string_literal: true

module ReactPayload
  class Base
    extend T::Helpers

    abstract!

    sig { abstract.returns(T::Hash[String, T.untyped]) }
    def payload; end

    sig { abstract.returns(String) }
    def route_id; end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def as_json
      {
        self.route_id => payload,
      }
    end
  end
end
