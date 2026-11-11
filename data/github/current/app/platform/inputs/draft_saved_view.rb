# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class DraftSavedView < Platform::Inputs::Base
      description "Inputs for creating a new saved view."

      argument :name, String, "The name of the new collection", required: true
      argument :description, String, "The description of the new collection", required: false
      argument :query, String, "The query of the new collection", required: true
      argument :icon, Enums::SearchShortcutIcon, "The icon of the new collection", required: false
      argument :color, Enums::SearchShortcutColor, "The color of the new collection", required: false
    end
  end
end
