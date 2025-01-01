# typed: true
# frozen_string_literal: true

module Coders
  # An ActiveRecord Coder that fulfills the "identity" property.
  # That is, it complies with the Coder protocol, responding to both
  # .dump and .load methods; each returning the given value.
  #
  # Useful as a base class for Coders that only need to implement
  # one or the other of dump/load, allowing the non-overridden method
  # to act as a pass-through in a coder pipeline.
  # Also useful as a default coder where one is needed but not supplied.
  class Identity
    def dump(value)
      value
    end

    def load(value)
      value
    end
  end
end
