# typed: strict
# frozen_string_literal: true

module DashboardSurface
  module Payloads
    # Shared saved view serialization struct for all dashboard surfaces.
    # Represents a user's saved search shortcut in the sidebar.
    #
    # This is part of the shared dashboard surface infrastructure.
    class SavedView < T::Struct
      const :id, Integer
      const :name, String
      const :description, T.nilable(String)
      const :icon, T.nilable(String)
      const :color, T.nilable(String)
      const :query, String
      const :source, String

      sig { params(saved_view: SearchShortcut).returns(SavedView) }
      def self.serialize(saved_view)
        SavedView.new(
          id: saved_view.id,
          name: saved_view.name,
          description: saved_view.description,
          icon: saved_view.icon,
          color: saved_view.color,
          query: saved_view.compressed_query,
          source: "user"
        )
      end
    end
  end
end
