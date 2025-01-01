# typed: true
# frozen_string_literal: true

module GitHub
  class Experiment
    # Models the enum of possible experiment outcomes.
    module Outcome

      # This is the only method that gets mixed in when you
      # `include Outcome`.  The rest are module methods.
      def outcome
        T.bind(self, Scientist::Result)
        if matched?
          Match
        elsif ignored?
          Ignore
        else
          Mismatch
        end
      end

      # The list of possible experiment outcomes.
      KNOWN = Set.new([
        Match = Class.new,
        Mismatch = Class.new,
        Ignore = Class.new,
      ]).freeze

      # Raised when asserting on or trying to serialize or
      # deserialize an unknown argument.
      Unknown = Class.new(ArgumentError)

      # Extend Match | Mismatch | Ignore with to_s and inspect
      module EnumMethods
        include Kernel

        TO_STRING = {
          Match => "match",
          Mismatch => "mismatch",
          Ignore => "ignore"
        }.freeze

        def to_s
          TO_STRING.fetch(self) { fail Unknown, self.inspect }
        end

        def inspect
          T.bind(self, Class)
          name
        end
      end

      KNOWN.each { |enum| enum.extend(EnumMethods) }

      # Coerce an input to Match | Mismatch | Ignore or raise.
      def self.coerce!(input)
        if input == "match" || input == Match
          Match
        elsif input == "mismatch" || input == Mismatch
          Mismatch
        elsif input == "ignore" || input == Ignore
          Ignore
        else
          raise Unknown, "unable to coerce #{input.inspect} to Outcome enum"
        end
      end
    end
  end
end
