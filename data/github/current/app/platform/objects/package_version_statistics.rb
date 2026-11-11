# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PackageVersionStatistics < Platform::Objects::Base
      description "Represents a object that contains package version activity statistics such as downloads."

      minimum_accepted_scopes ["read:packages"]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        permission.typed_can_access?("PackageVersion", object)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        # The underlying object is a `Registry::PackageVersion`
        permission.typed_can_see?("PackageVersion", object)
      end

      field :downloads_today, Integer, "Number of times the package was downloaded today.", null: false, visibility: :internal
      field :downloads_this_week, Integer, "Number of times the package was downloaded this week.", null: false, visibility: :internal
      field :downloads_this_month, Integer, "Number of times the package was downloaded this month.", null: false, visibility: :internal
      field :downloads_this_year, Integer, "Number of times the package was downloaded this year.", null: false, visibility: :internal
      field :downloads_total_count, Integer, "Number of times the package was downloaded since it was created.", null: false
    end
  end
end
