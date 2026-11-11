# typed: strict
# frozen_string_literal: true

module Exporter
  # Service class to extract a tar.gz archive to a destination directory.
  #
  # Uses GitHub::Migrator::TarUtils for secure extraction with proper cleanup
  # of symlinks, dotfiles, and marshal files.
  class ArchiveExtractor
    include GitHub::Migrator::TarUtils

    sig { params(archive_path: String, destination_dir: Pathname).void }
    def initialize(archive_path:, destination_dir:)
      @archive_path = T.let(archive_path, String)
      @destination_dir = T.let(destination_dir, Pathname)
    end

    sig { void }
    def extract
      extract_archive(@archive_path, @destination_dir)
    end
  end
end
