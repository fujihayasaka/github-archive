# typed: strict
# frozen_string_literal: true

module Configurable
  module MaxRefUpdates
    extend T::Sig
    extend T::Helpers
    include Kernel

    requires_ancestor { Configurable }

    KEY = "max_ref_updates"

    MIN_REF_COUNT_LIMIT = 2
    MAX_REF_COUNT_LIMIT = 1_000

    sig { params(value: Integer, actor: User).returns(T::Boolean) }
    def set_max_ref_updates(value, actor)
      case value.to_i
      when 0 then
        config.delete(KEY, actor)
      when MIN_REF_COUNT_LIMIT..MAX_REF_COUNT_LIMIT then
        config.set!(KEY, value.to_i, actor)
      else
        raise ArgumentError.new("Must be a whole number between #{MIN_REF_COUNT_LIMIT} and #{MAX_REF_COUNT_LIMIT}")
      end
    end

    sig { returns(Integer) }
    def max_ref_updates
      config.get(KEY).to_i
    end
  end
end
