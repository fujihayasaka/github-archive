# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module Shortcutable
      include Interfaces::Base
      description "Represents an object which implements all the properties for a shortcut. Typically a search shortcut or a team search shortcut."

      required_capabilities [:mobile_only_schema_mask]

      field :id, ID, "The id of the shortcut", null: false
      field :name, String, "The name of the shortcut.", null: false
      field :description, String, "The description of the shortcut.", null: false
      field :search_type, Enums::SearchShortcutType, "The type of the shortcut.", null: false
      field :icon, Enums::SearchShortcutIcon, "The icon of the shortcut.", null: false
      field :color, Enums::SearchShortcutColor, "The color of the shortcut.", null: false
      field :query, String, "The filter string of the shortcut.", null: false

      field :query_terms, [Unions::SearchShortcutQueryTermsItem], null: false,
        description: "A parsed set of terms from the query string of this shortcut."

      field :scoping_repository, Objects::Repository, "The repository scoping the shortcut.", null: true

    end
  end
end
