# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SearchShortcutType < Platform::Enums::Base
      description "The type of search for a search shortcut"
      required_capabilities [:mobile_only_schema_mask]

      ::SearchShortcut.search_types.keys.each do |key|
        value key.upcase, "#{key.to_s.humanize} search shortcut type", value: key
      end
    end
  end
end
