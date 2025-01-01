# typed: true
# frozen_string_literal: true

module GitRPC
  class Backend
    class ContributionCaches
      # The abstract super class of the concrete cache file handling sub classes. Each version
      # corresponds to a different iteration of the cache file implementation.
      class AbstractCache
        # backend       - The GitRPC backend instance.
        def initialize(backend, version)
          raise ArgumentError, "version must be specified." if version.nil?
          @backend = backend
          @version = version
        end

        # The head oid of the commit whose ancestry is represented by this cache file's data.
        # Note: calling this method on a new CacheFile instance forces a load from disk.
        #
        # Returns the SHA1 oid as a String.
        def head_oid
          raise NotImplementedError
        end

        # The commits data as it was originally written to disk.
        # Note: calling this method on a new CacheFile instance forces a load from disk.
        #
        # Returns an Array of commit rows as provided by git-gh-graph
        def commits
          raise NotImplementedError
        end

        # Atomically replace the file for a new HEAD and list of commits.
        #
        # head_oid - The new HEAD oid as a String.
        # commits  - The new Array of commits.
        #
        # Returns nothing.
        def write(head_oid, commits)
          raise NotImplementedError
        end

        # Returns the version of this cache file instance.
        attr_reader :version

        # Returns the path for the concrete cache class
        def self.path
          const_get("PATH")
        end

        # Returns the path for the concrete cache class. Convenience instance method
        def path
          self.class.path
        end

        protected

        attr_reader :backend

        # Convenience method to ensure data is as expected. Useful as a write validation step.
        def validate(oid, commits)
          if !::GitRPC::Util.valid_full_oid?(oid)
            raise ContributionCaches::Error, "head_oid is not a valid SHA-1 value."
          end

          if commits.empty?
            raise ContributionCaches::Error, "commit list is empty"
          end
        end
      end
    end
  end
end
