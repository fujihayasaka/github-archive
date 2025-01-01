# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module SearchShortcutQueryBasicTerm
      include Platform::Interfaces::Base
      description "A search shortcut query term"
      mobile_only true

      field :term, String, "The text of a term of a search shortcut query", null: false
    end
  end
end
