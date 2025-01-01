# typed: true
# frozen_string_literal: true

module Search
  module Memex
    module Nodes
      autoload :Qualifier, "search/memex/nodes/qualifier"
      autoload :ContentQualifier, "search/memex/nodes/content_qualifier"
      autoload :FieldValueQualifier, "search/memex/nodes/field_value_qualifier"
      autoload :FieldValuePresenceQualifier, "search/memex/nodes/field_value_presence_qualifier"
      autoload :FullTextQuery, "search/memex/nodes/full_text_query"
      autoload :LastUpdatedQualifier, "search/memex/nodes/last_updated_qualifier"
      autoload :UpdatedQualifier, "search/memex/nodes/updated_qualifier"
      autoload :ReasonQualifier, "search/memex/nodes/reason_qualifier"
      autoload :Root, "search/memex/nodes/root"
      autoload :StateQualifier, "search/memex/nodes/state_qualifier"
      autoload :StateValueHelpers, "search/memex/nodes/state_value_helpers"
    end
  end
end
