# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class ReleaseArchiver < BaseArchiver

      # Public: Save assets for a release.
      #
      # release - Release instance.
      def save(release)
        release.release_assets.each do |asset|
          save_asset(asset)
        end
      end

      private

      def asset_namespace
        "releases"
      end

      def logger_fn
        "gh-migrator-save-release-asset"
      end
    end
  end
end
