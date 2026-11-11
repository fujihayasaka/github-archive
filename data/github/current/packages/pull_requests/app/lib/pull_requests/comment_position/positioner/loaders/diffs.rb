# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioner
      module Loaders
        # Efficiently manages diff loading by batching requests for the same commit range
        # and reusing pre-loaded diff data to minimize expensive GitRPC operations.
        #
        # The Diffs loader handles:
        # - Reusing existing loaded GitHub::Diff objects to avoid redundant GitRPC calls
        # - Batching diff requests by commit range to minimize network operations
        # - Managing multiple diff batches for different base/head commit combinations
        # - Providing efficient path-based diff entry lookup with proper error handling
        # - Lazy loading of diff data only when actually needed
        class Diffs
          GitErrors = T.type_alias { T.any(CommentPosition::Errors::DiffNotValid, CommentPosition::Errors::GitUnavailable) }

          # Wraps GitHub::Diff instances to deal with quirks of loading and resolving diff contents. Enables reuse of
          # existing diffs that have been loaded by other domains or areas of the codebase.
          class Delegate
            sig { returns(T.nilable(GitHub::Diff)) }
            attr_accessor :diff

            # Reuse a GitHub::Diff instance as a batch instance if loaded. Do not attempt to reuse Diff instances
            # that are not loaded as they've been mutated in ways that may affect our diff loading.
            sig { params(diff: GitHub::Diff, repository: Repository).returns(T.nilable(Delegate)) }
            def self.reuse(diff, repository:)
              return unless diff.loaded?

              new(
                base_commit_oid: diff.sha1,
                head_commit_oid: diff.sha2,
                paths: diff.paths,
                repository:,
                diff:
              )
            end

            sig { params(repository: Repository, base_commit_oid: String, head_commit_oid: String, paths: T::Array[String], diff: T.nilable(GitHub::Diff)).void }
            def initialize(repository:, base_commit_oid:, head_commit_oid:, paths: [], diff: nil)
              @repository = repository
              @base_commit_oid = base_commit_oid
              @head_commit_oid = head_commit_oid
              @diff = diff
              @paths = T.let(Set.new(paths), T::Set[String])
              @error = T.let(nil, T.nilable(Diffs::GitErrors))
            end

            # Batch load the data for the requested diff.
            #
            # This method only initializes a new instance during load time due to GitHub::Diff#add_path invoking a
            # GitRPC call to load the table of contents for the requested diff range. To prevent side effects
            # during initialization, we defer creating this instance until we're ready to call Diff#load_diff.
            sig { void }
            def load!
              return if loaded?

              @diff = GitHub::Diff.new(@repository, @base_commit_oid, @head_commit_oid)
              @diff.add_paths(@paths.to_a)
              @diff.maximize_single_entry_limits!
              @diff.load_diff
            rescue GitRPC::ObjectMissing, GitRPC::InvalidObject, GitRPC::InvalidRepository => exception
              @error = CommentPosition::Errors::DiffNotValid.new(message: exception.message)
            rescue GitRPC::Error => exception
              @error = CommentPosition::Errors::GitUnavailable.new(message: exception.message)
            end

            # Check if the diff data has been loaded and is ready for use.
            sig { returns(T::Boolean) }
            def loaded? = !pending?

            # Check if the diff data is still pending and needs to be loaded.
            sig { returns(T::Boolean) }
            def pending? = @error.nil? && @diff.nil?

            # Verify if this batch targets the specified commit range.
            sig { params(base_commit_oid: String, head_commit_oid: String).returns(T::Boolean) }
            def targeting?(base_commit_oid:, head_commit_oid:) = @base_commit_oid == base_commit_oid && @head_commit_oid == head_commit_oid

            # Check if the specified path is included in this batch's path collection.
            sig { params(path: String).returns(T::Boolean) }
            def has_path?(path) = @paths.include?(path)

            # Add a new path to this batch's collection for inclusion in diff loading.
            sig { params(path: String).void }
            def add_path(path) = @paths.add(path)

            sig { params(path: String).returns(T.any(GitHub::Diff::Entry, GitErrors, Errors::Path)) }
            def with_path(path:)
              return @error if @error
              @diff&.with_path(path) || Errors::Path.new(path:)
            end
          end

          sig { params(repository: Repository, diffs: T::Array[GitHub::Diff]).void }
          def initialize(repository:, diffs:)
            @repository = repository
            @diffs = T.let(diffs.map { Delegate.reuse(_1, repository:) }.compact, T::Array[Delegate])
          end

          # Retrieve a diff entry for the specified commit range and path.
          sig do
            params(
              base_commit_oid: String,
              head_commit_oid: String,
              path: String).returns(T.any(
                GitHub::Diff::Entry,
                Errors::DiffNotLoaded,
                GitErrors,
                Errors::Path
              ))
          end
          def entry_for(base_commit_oid:, head_commit_oid:, path:)
            loaded_diff_for(base_commit_oid:, head_commit_oid:, path:)&.with_path(path:) || Errors::DiffNotLoaded.new(base_commit_oid:, head_commit_oid:)
          end

          # Add a path to the appropriate diff batch for later loading.
          sig { params(base_commit_oid: String, head_commit_oid: String, path: String).void }
          def add_to_batch(base_commit_oid:, head_commit_oid:, path:)
            # Skip if we already have a loaded diff containing this path
            return if loaded_diff_for(base_commit_oid:, head_commit_oid:, path:)

            # Add the path to an existing or new batch for the commit range
            find_or_create_diff_for(base_commit_oid:, head_commit_oid:).add_path(path)
          end

          # Trigger loading of all pending diff batches.
          sig { void }
          def load_batch! = @diffs.each(&:load!)

          private

          # Find a loaded diff batch that contains the specified path for the given commit range.
          sig { params(base_commit_oid: String, head_commit_oid: String, path: String).returns(T.nilable(Delegate)) }
          def loaded_diff_for(base_commit_oid:, head_commit_oid:, path:)
            @diffs.find { _1.loaded? && _1.targeting?(base_commit_oid:, head_commit_oid:) && _1.has_path?(path) }
          end

          # Find an existing pending batch or create a new one for the specified commit range.
          sig { params(base_commit_oid: String, head_commit_oid: String).returns(Delegate) }
          def find_or_create_diff_for(base_commit_oid:, head_commit_oid:)
            if delegate = @diffs.find { _1.pending? && _1.targeting?(base_commit_oid:, head_commit_oid:) }
              # Reuse a pending to be loaded delegated diff.
              delegate
            else
              # Create and track new batch if no suitable pending diff exists
              Delegate.new(repository: @repository, base_commit_oid:, head_commit_oid:).tap { @diffs << _1 }
            end
          end
        end
      end
    end
  end
end
