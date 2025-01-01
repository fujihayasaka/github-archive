# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    # This module collects types that can be used represent an Elasticsearch schema (a.k.a. a "mapping").
    #
    # For more detailis on the mapping process, see:
    # https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping.html
    module Mapping
      # Generic modules that represent Elasticsearch concepts.
      autoload :Analyzer, "elastomer/interfaces/mapping/analyzer"
      autoload :DateFormat, "elastomer/interfaces/mapping/date_format"
      autoload :Dynamic, "elastomer/interfaces/mapping/dynamic"
      autoload :Routing, "elastomer/interfaces/mapping/routing"
      autoload :FieldDataType, "elastomer/interfaces/mapping/field_data_type"
      autoload :FieldDataTypes, "elastomer/interfaces/mapping/field_data_types"
      autoload :FieldDataTypeName, "elastomer/interfaces/mapping/field_data_type_name"

      # GitHub-specific modules.
      autoload :MemexProjectItem, "elastomer/interfaces/mapping/memex_project_item"
    end
  end
end
