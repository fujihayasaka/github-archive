# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Mapping
      module FieldDataTypes
        autoload :Boolean, "elastomer/interfaces/mapping/field_data_types/boolean"
        autoload :Date, "elastomer/interfaces/mapping/field_data_types/date"
        autoload :Float, "elastomer/interfaces/mapping/field_data_types/float"
        autoload :Integer, "elastomer/interfaces/mapping/field_data_types/integer"
        autoload :KeywordMultiField, "elastomer/interfaces/mapping/field_data_types/keyword_multi_field"
        autoload :Keyword, "elastomer/interfaces/mapping/field_data_types/keyword"
        autoload :Long, "elastomer/interfaces/mapping/field_data_types/long"
        autoload :Object, "elastomer/interfaces/mapping/field_data_types/object"
        autoload :Text, "elastomer/interfaces/mapping/field_data_types/text"
      end
    end
  end
end
