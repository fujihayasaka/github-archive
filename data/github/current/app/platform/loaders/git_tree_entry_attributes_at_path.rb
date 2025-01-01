# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    # Returns the result of a default invocation of ls_tree at a given oid for
    # a number of paths.  Useful for reading things like blob oids at arbitrary
    # paths without slurping the whole tree.
    class GitTreeEntryAttributesAtPath < Platform::Loader
      # Struct to contain raw results from git.
      LsTreeResult = Struct.new(:mode, :type, :oid, :path)

      def self.load(repository, oid, path)
        self.for(repository, oid).load(path)
      end

      def self.load_all(repository, oid, paths)
        loader = self.for(repository, oid)
        Promise.all(paths.map { |path| loader.load(path) })
      end

      def initialize(repository, oid)
        @repository = repository
        @oid = oid
      end

      def fetch(paths)
        result = @repository.rpc.ls_tree(@oid, path: paths)
        result["entries"].map { |arr| LsTreeResult.new(*arr) }.index_by(&:path)
      end
    end
  end
end
