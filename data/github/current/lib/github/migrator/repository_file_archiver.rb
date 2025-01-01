# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class RepositoryFileArchiver < BaseArchiver

      # Public: Save repository file.
      #
      # repository_file - RepositoryFile instance.
      def save(repository_file)
        save_asset(repository_file)
      end

      private

      def asset_namespace
        "repository_files"
      end

      def path_segment(asset)
        asset.id.to_s
      end

      def logger_fn
        "gh-migrator-save-repository_file"
      end
    end
  end
end
