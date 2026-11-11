# typed: strict
# frozen_string_literal: true

module DashboardSurface
  module Loaders
    # Shared loader for user-saved search views (SearchShortcuts).
    # Used by all dashboard surfaces (pulls, issues, repos) to load saved views
    # for the sidebar.
    #
    # This is part of the shared dashboard surface infrastructure.
    class SavedViewLoader
      class SearchType < T::Enum
        enums do
          Issues = new("issues")
          PullRequests = new("pull_requests")
          Repositories = new("repositories")
        end
      end

      sig { params(current_user: T.nilable(User), search_type: SearchType).returns(T::Array[DashboardSurface::Payloads::SavedView]) }
      def self.load_for_user(current_user, search_type)
        current_user&.dashboard&.shortcuts&.where(search_type: search_type.serialize)&.reorder(id: :asc)&.map do |shortcut|
          DashboardSurface::Payloads::SavedView.serialize(shortcut)
        end || []
      end
    end
  end
end
