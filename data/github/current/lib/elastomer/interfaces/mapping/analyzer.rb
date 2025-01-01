# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Mapping
      # Static options for the name of an analyzer that can be used to process a text field.
      #
      # These are used as the value of the `analyzer` property of the `Text` mapping type. We define these statically
      # so that we can guarantee that we don't use any analyzers that we've accidentally forgotten to configure.
      #
      # For more details on analysis, see:
      # https://www.elastic.co/guide/en/elasticsearch/reference/current/analysis.html
      #
      # For more on how an analyzer works, see:
      # https://www.elastic.co/guide/en/elasticsearch/reference/current/analyzer-anatomy.html
      class Analyzer < T::Enum
        extend T::Sig

        enums do
          Standard = new
          Texty = new
          SearchAsYouType = new("search_as_you_type")
          SearchAsYouTypeKeyword = new("search_as_you_type_keyword")
        end
      end
    end
  end
end
