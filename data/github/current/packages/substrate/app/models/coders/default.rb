# typed: true
# frozen_string_literal: true

module Coders
  # An ActiveRecord Coder that wraps another coder (which itself could be a
  # pipeline of coders).
  # `dump` proxies through to the wrapped coder.
  # `load` proxies through to the wrapped coder _if the value is not-nil_
  # If the value is nil, it short-circuits the wrapped coder and returns
  # the provided default value.
  #
  # This is primarily to handle ActiveRecord's "default value" logic
  # wherein AR will skip decoding if the value is the same as a decoded nil.
  # https://github.com/rails/rails/blob/b2eb1d1c55a59fee1e6c4cba7030d8ceb524267c/activerecord/lib/active_record/type/serialized.rb#L60-L62
  #
  # However, this is also useful to facilitate providing a model-defined
  # defined default value in place of db NULL.
  class Default
    extend Forwardable
    def_delegator :@coder, :dump

    def initialize(coder, default)
      @coder = coder
      @default = default
    end

    def load(value)
      loaded = @coder.load(value) if value.present?
      loaded.presence || @default.dup
    end
  end
end
