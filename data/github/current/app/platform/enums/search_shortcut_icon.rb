# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SearchShortcutIcon < Platform::Enums::Base
      description "The icon for a search shortcut"
      mobile_only true

      ::SearchShortcut.icons.keys.each do |key|
        value key.upcase, "#{key.to_s.humanize} search shortcut icon", value: key
      end
    end
  end
end
