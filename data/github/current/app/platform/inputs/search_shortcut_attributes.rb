# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class SearchShortcutAttributes < Platform::Inputs::Base
      description "Search shortcut attributes."
      mobile_only true

      argument :name, String, "The name of the shortcut.", required: true
      argument :query, String, "The search query for the shortcut.", required: false, default_value: ""
      argument :description, String, "The description for the shortcut.", required: false, default_value: ""
      argument :search_type, Enums::SearchShortcutType, "The search type for the shortcut.", required: true
      argument :icon, Enums::SearchShortcutIcon, "The icon for the shortcut.", required: true
      argument :color, Enums::SearchShortcutColor, "The color for the shortcut.", required: true
      argument :scoping_repository, Inputs::RepositoryNameWithOwner, <<~DESC, required: false
        The repository acting as a scope for filtering shortcut query terms.
      DESC
    end
  end
end
