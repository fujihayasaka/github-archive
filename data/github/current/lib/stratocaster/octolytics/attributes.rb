# typed: true
# frozen_string_literal: true

require "set"

module Stratocaster
  module Octolytics
    module Attributes
      # Flattens a hash by prefixing each element with a string.
      #
      # hash: hash to flatten
      # prefix: prefix string (e.g., "user_")
      def self.flatten(hash:, prefix: "")
        hash = StratocasterHash(hash)
        hash.each_with_object({}) do |(k, v), flattened|
          if v.is_a?(Hash)
            flattened.merge!(flatten(hash: v, prefix: "#{prefix}_#{k}"))
          else
            flattened["#{prefix}_#{k}"] = v
          end
        end
      end

      # Coerces a value into a hash that has the structure of most API hashes
      # in the codebase at the current time. In past times, certain values for
      # stratocaster events were an integer ID, not a serialization of the
      # object at the time.
      #
      # This method returns the object if it's already a hash, but if it's
      # an ID, it wraps it in a hash like `{"id": id}`
      #
      # Its name is meant to evoke a likeness to `Array` and `Hash` from
      # Ruby `Kernel`
      def self.StratocasterHash(value)
        case value
        when NilClass
          {}
        when Numeric
          { "id" => value }
        else
          value
        end
      end
      private_class_method :StratocasterHash
    end
  end
end
