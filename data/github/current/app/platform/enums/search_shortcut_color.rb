# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SearchShortcutColor < Platform::Enums::Base
      description "A color for a search shortcut"
      required_capabilities [:mobile_only_schema_mask]

      ::SearchShortcut.colors.keys.each do |key|
        value key.upcase, "#{key.to_s.humanize} search shortcut color", value: key
      end
    end
  end
end
