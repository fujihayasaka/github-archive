# typed: strict
# frozen_string_literal: true

# Shim for ObjectSpace methods from the `objspace` C extension.
# These methods are added when `require "objspace"` is called.
module ObjectSpace
  class << self
    sig { params(obj: BasicObject).returns(T.nilable(Integer)) }
    def allocation_generation(obj); end

    sig { params(obj: BasicObject).returns(T.nilable(String)) }
    def allocation_sourcefile(obj); end

    sig { params(obj: BasicObject).returns(T.nilable(Integer)) }
    def allocation_sourceline(obj); end
  end
end
