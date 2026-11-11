# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Mapping
      # Static options for the name of an normalizer that can be used to process a keyword field.
      #
      # These are used as the value of the `normalizer` property of the `Keyword` mapping type. We define these
      # statically so that we can guarantee that we don't use any normalizers that we've accidentally forgotten to
      # configure.
      #
      # For more details, see:
      # https://www.elastic.co/guide/en/elasticsearch/reference/8.17/normalizer.html
      class Normalizer < T::Enum
        enums do
          Lowercase = new
        end
      end
    end
  end
end
