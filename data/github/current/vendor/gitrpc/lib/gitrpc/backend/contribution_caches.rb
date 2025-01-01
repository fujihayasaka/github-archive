# frozen_string_literal: true
# typed: true

require_relative "contribution_caches/v1"
require_relative "contribution_caches/v2"

module GitRPC
  class Backend

    # A sort of manager for the cache classes and files, in the vein of GitHub's CommitCollection.
    class ContributionCaches

      # Raised when attempting to write invalid data or cache file is corrupt
      class Error < StandardError; end

      FIRST_VERSION = 1

      LATEST_VERSION = 2

      def initialize(backend)
        @backend = backend
      end

      # Finds the appropriate cache implementation for the specified version, instantiates and
      # returns it.
      #
      # Returns GitRPC::Backend::ContributionCaches::V{1..}
      def new_instance(version:)
        fail ArgumentError, "invalid version" if version < FIRST_VERSION || version > LATEST_VERSION
        cache_class_for_version(version).new(backend)
      end

      # Walk backwards from the requested version until we find a cache file that exists.
      #
      # Returns GitRPC::Backend::ContributionCaches::V{1..} or nil if no existing cache file
      #   can be found.
      def find_existing_cache(version:)
        version.downto(FIRST_VERSION).each do |v|
          if backend.fs_exist?(file_path(version: v))
            return new_instance(version: v)
          end
        end

        nil
      end

      # Removes all versions of the cache file from disk. Subsequent requests for the cached
      # data will therefore trigger a complete rebuild.
      #
      # Returns nil
      def clear
        LATEST_VERSION.downto(FIRST_VERSION).each do |v|
          backend.fs_delete(file_path(version: v))
        end

        nil
      end

      # Returns the relative cache file path for the specified version.
      def file_path(version:)
        cache_class_for_version(version).path
      end

      private

      attr_reader :backend

      def cache_class_for_version(version)
        ContributionCaches.const_get("V#{version}")
      end
    end
  end
end
