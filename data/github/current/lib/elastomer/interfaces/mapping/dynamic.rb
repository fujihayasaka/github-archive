# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Mapping
      # Static options for how Elasticsearch should behave when it encounters an "unmapped" field (i.e. a field
      # for which it does not have a schema).
      #
      # These options are used as the value of the `dynamic` property of an Object type. Although Dynamic::True is
      # the Elasticsearch default, we recommend that you use Dynamic::Strict to prevent Elasticsearch from assigning
      # an unexpected type to a field.
      #
      # For more details, see: https://www.elastic.co/guide/en/elasticsearch/reference/current/dynamic.html
      class Dynamic < T::Enum
        extend T::Sig

        enums do
          True = new("true") # Elasticsearch default
          Runtime = new("runtime")
          Strict = new("strict")
          False = new("false")
        end
      end
    end
  end
end
