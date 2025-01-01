# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module SearchShortcutQueryParsedTerm
      include Platform::Interfaces::Base
      description "A known search shortcut query term"
      required_capabilities [:mobile_only_schema_mask]

      field :name, String, "The name of the query term", null: false
      field :value, String, "The value of the query term", null: false
      field :negative, Boolean, "Whether the query term is negative", null: false
    end
  end
end
