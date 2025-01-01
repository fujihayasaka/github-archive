# typed: false
# frozen_string_literal: true

require "rubygems/package"
require "tempfile"
require "zlib"

module GitHub
  class Migrator
    module TarUtils

      # Public: Create a gzipped archive with the contents of source_path.
      #
      # source_path  - Pathname or String path to files that need archived.
      # archive_path - Pathname or String path and filename for created archive.
      #
      # Returns Pathname or String archive_path.
      def create_archive(source_path, archive_path)
        options = ["-czf", "#{archive_path}", "-C", "#{source_path}", "."]

        child = Progeny::Command.new("tar", *options)
        raise child.err unless child.success?

        archive_path
      end

      # Public: Extract file(s) from archive to destination path and optionally
      # cleanup extracted files after yielding a block if it is provided.
      #
      # archive_path     - Pathname or String path to archive.
      # destination_path - Pathname or String destination path for files.
      #
      # Returns Pathname or String destination_path (or NilClass if block given).
      def extract_archive(archive_path, destination_path, &block)
        options = ["-xvzf", "#{archive_path}", "-C", "#{destination_path}"]

        FileUtils.mkdir_p(destination_path)

        child = Progeny::Command.new("tar", *options)
        raise child.err unless child.success?

        check_repositories_permissions!(destination_path)

        recursively_rm_symlinks(destination_path) if File.exist?(destination_path)
        recursively_rm_dotfiles(destination_path) if File.exist?(destination_path)
        rm_marshal_files(destination_path) if File.exist?(destination_path)

        if block_given? && File.exist?(destination_path)
          yield # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          FileUtils.rm_rf(destination_path, secure: true)
          nil
        else
          destination_path
        end
      end

      def read_from_archive(pattern)
        Dir["#{migration_path}/#{pattern}"].each do |file_path|
          raise GitHub::Migrator::SecurityException, "InvalidArchive: Archive contained invalid data and could not be processed" unless File.expand_path(file_path).start_with? migration_path.to_s
          File.open(file_path, "r") do |file|
            yield(file)
          end
        end
      end

      def read_file_from_archive(path)
        full_path = File.join(migration_path, path)
        File.open(full_path, "r")
      end

      def raise_on_unsupported_asset!(path)
        full_path = File.join(migration_path, path)
        Dir.glob(full_path).each do |path|
          raise_unsupported_asset_error!("symbolic link file type is not allowed") if File.symlink?(path)
        end
      end

      private

      def raise_unsupported_asset_error!(message)
        raise GitHub::Migrator::UnsupportedUploadableAsset.new(message)
      end

      def recursively_rm_dotfiles(destination_path)
        git_source_dirs = Dir.glob("**/.*.git", File::FNM_DOTMATCH, base: destination_path)

        Dir.glob("**/.*", File::FNM_DOTMATCH, base: destination_path).each do |path|
          next if git_source_dirs.include?(path)

          full_path = File.join(destination_path, path)
          FileUtils.remove_entry_secure(full_path) if full_path[/\/\.[^\.]/] && File.exist?(full_path)
        end
      end

      def recursively_rm_symlinks(destination_path)
        Dir.glob("**/*", File::FNM_DOTMATCH, base: destination_path).each do |path|
          file_path = File.join(destination_path, path)
          File.delete(file_path) if File.symlink?(file_path)
        end
      end

      def rm_marshal_files(destination_path)
        Dir.glob("repositories/**/{language,stacks}-stats.cache", File::FNM_DOTMATCH, base: destination_path).each do |marshal_file|
          full_path = File.join(destination_path, marshal_file)

          FileUtils.rm(full_path)
        end
      end

      def check_repositories_permissions!(destination_path)
        repositories_path = File.join(destination_path, "repositories")
        return unless File.exist?(repositories_path)
        raise_invalid_archive_pemissions!("Archive does not have read permissions set for all directories.") unless File.stat(repositories_path).readable?

        # Check permissions for all directories in the repositories directory
        Dir.glob("**/*/", base: repositories_path).each do |path|
          directory_readable = File.stat(File.join(repositories_path, path)).readable?
          raise_invalid_archive_pemissions!("Archive does not have read permissions set for all directories.") unless directory_readable
        end
      end

      def raise_invalid_archive_pemissions!(message)
        raise GitHub::Migrator::InvalidArchivePermissions.new(message)
      end
    end
  end
end
