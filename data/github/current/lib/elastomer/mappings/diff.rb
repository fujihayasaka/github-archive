# typed: true
# frozen_string_literal: true

require "hashdiff"

module Elastomer
  module Mappings
    # Elastomer::Mappings::Diff compares two mappings and return the added, changed, and removed fields. Fields are
    # represented as a dot-separated path to the field. For example, a field named "field1" in a nested object named
    # "nested" would be represented as "nested.properties.field1".
    #
    # Example:
    #
    #  old_mapping = {
    #    "properties" => {
    #      "field1" => { "type" => "text" },
    #      "field3" => { "type" => "text" },
    #    },
    #  }
    #  new_mapping = {
    #    "properties" => {
    #      "field2" => { "type" => "text" },
    #      "field3" => { "type" => "long" },
    #    },
    #  }
    #  diff = Elastomer::Mappings::Diff.new(old_mapping:, new_mapping:)
    #  diff.added # => ["field2"]
    #  diff.changed # => ["field3.type"]
    #  diff.removed # => ["field1"]
    class Diff
      # The list of fields added in the new mapping.
      #
      # diff.added #=> ["issue", "issue.properties.type"]
      sig { returns(T::Array[Hash]) }
      attr_reader :added

      # The list of fields that changed between the old and new mapping.
      #
      # diff.changed #=> ["issue.properties.id", "issue.properties.assignees.type"]
      sig { returns(T::Array[Hash]) }
      attr_reader :changed

      # The list of fields removed in the new mapping.
      #
      # diff.removed #=> ["issue.id", "issue.properties.assignees"]
      sig { returns(T::Array[Hash]) }
      attr_reader :removed

      sig { params(old_mapping: T::Hash[T.untyped, T.untyped], new_mapping: T::Hash[T.untyped, T.untyped]).void }
      def initialize(old_mapping:, new_mapping:)
        @old_mapping = old_mapping.deep_stringify_keys
        @new_mapping = new_mapping.deep_stringify_keys
        @added = []
        @changed = []
        @removed = []

        old_mapping = @old_mapping.fetch("properties", {})
        new_mapping = @new_mapping.fetch("properties", {})

        diff = Hashdiff.diff(
          old_mapping,
          new_mapping,
          indifferent: true,

          # This option ensures that we avoid an algorithm that is known to perform poorly on hashes larger than 10kb
          # (see https://github.com/liufengyun/hashdiff/issues/49). Our hashes should be much smaller than 10kb,
          # but we disable LCS anyway as a precaution. The only consequence of this is that array diffs are a bit
          # harder to interpret.
          use_lcs: false
        )

        diff.each do |change|
          operation, path, _ = change
          if operation == "+"
            @added << path
          elsif operation == "-"
            @removed << path
          elsif operation == "~"
            @changed << path
          else
            raise Elastomer::Mappings::UnexpectedDiffOperationError.new(operation, path:)
          end
        end
      end

      def changes?
        added.any? || changed.any? || removed.any?
      end
    end
  end
end
