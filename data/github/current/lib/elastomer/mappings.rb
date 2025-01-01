# typed: true
# frozen_string_literal: true

module Elastomer
  module Mappings
    autoload :Diff, "elastomer/mappings/diff"
    autoload :GeneratedMapping, "elastomer/mappings/generated_mapping"

    class UpdatesNotSupportedError < StandardError
      def initialize(index_name)
        super("The '#{index_name}' index does not support mapping updates and any changes must be applied by creating a new index.")
      end
    end

    class DestructiveMappingChangeError < StandardError
      def initialize(index_name)
        super("The '#{index_name}' index contains updated or removed fields and cannot safely update the mapping. To apply the changes, create a new index.")
      end
    end

    class UnexpectedDiffOperationError < StandardError
      sig { returns(String) }
      attr_reader :operation

      sig { returns(T.nilable(String)) }
      attr_reader :path

      sig { params(operation: String, path: T.nilable(String)).void }
      def initialize(operation, path: nil)
        @operation = operation
        @path = path

        super("Unexpected diff operation encountered '#{operation}'#{" for path '#{path}'" if path}")
      end
    end
  end
end
