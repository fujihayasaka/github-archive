# typed: true
# frozen_string_literal: true

module Coders
  # Creates an ActiveRecord Coder which is the composition of all the given
  # coders such that:
  #   `.dump` is the left-associative composition of each coder's `dump` and
  #   `.load` is the right-associative composition of each coder's `load`.
  #
  # Example: x = Composed.new(A, B, C) =>
  #   x.dump(val) == C.dump(B.dump(A.dump(val)))
  #   x.load(val) == A.load(B.load(C.load(val)))
  class Composed
    extend Forwardable

    def_delegator :@dumper, :call, :dump
    def_delegator :@loader, :call, :load

    def initialize(coders)
      @dumper = coders.map { |c| c.method(:dump) }.reduce(:>>)
      @loader = coders.map { |c| c.method(:load) }.reduce(:<<)
    end
  end
end
