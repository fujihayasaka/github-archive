# typed: true

# Shim for Ruby 4.0 Ractor::Port API
# https://bugs.ruby-lang.org/issues/21052
class Ractor
  class Port
    sig { void }
    def initialize; end

    sig { returns(T.untyped) }
    def receive; end
  end
end
