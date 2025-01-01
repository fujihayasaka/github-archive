# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Mapping
      # This is the interface that each class representing a mapping type must implement.
      module FieldDataType
        extend T::Sig
        extend T::Helpers
        interface!

        # Returns the name of this mapping type.
        #
        # You may need to add to the TypeName enum if you are implementing a new `Type` class.
        #
        # EXAMPLE:
        #
        #  def type
        #    TypeName::Text
        #  end
        sig { abstract.returns(FieldDataTypeName) }
        def name; end

        # Returns a hash with this `Type`'s configuration.
        #
        # This is the object that gets sent to Elasticsearch when the mapping for an index is created. As a result,
        # this should always contain a `type` key (typically populated by calling `type.serialize`). It should also
        # contain any additional configuration that is required for this type.
        #
        # EXAMPLE:
        #
        #   def to_hash
        #     { type: type.serialize, analyzer: "standard" }
        #   end
        sig { abstract.returns(T::Hash[T.untyped, T.untyped]) }
        def to_hash; end
      end
    end
  end
end
