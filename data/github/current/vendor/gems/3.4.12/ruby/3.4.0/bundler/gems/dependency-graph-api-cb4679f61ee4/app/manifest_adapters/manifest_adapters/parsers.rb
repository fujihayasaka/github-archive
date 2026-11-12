module ManifestAdapters
  module Parsers

    # Sentinel error indicating the new ecosystem's
    # ManifestAdapters::Parsers::Base subclass does
    # not yet meet the Parser API contract
    class MethodNotImplementedError < StandardError; end

    # Establishes a contract for per-ecosystem ManifestAdapter
    # file Parser subclasses to meet. Per-ecosystem subclasses
    # of ManifestAdapters::Adapter#parse return a Parser that
    # meet this contract for a particular manifest file type.
    #
    # The Parser methods defined below are called here:
    # https://github.com/github/dependency-graph-api/blob/master/app/manifest_adapters/manifest_adapters/adapter.rb
    class Base
      # Returns the declared name of the project the manifest
      # file being parsed represents. Note: some file types
      # do not expose a project name, and can return nil.
      def name
        raise MethodNotImplementedError
      end

      # Returns the declared version of the project the manifest
      # file being parsed represents. Note: some file types do
      # not expose a project version, and can return nil.
      def version
        raise MethodNotImplementedError
      end

      # Returns an Array of Manifest::Dependency records parsed from
      # the parent manifest file. Invalid or unparseable dependencies
      # are included, but flagged as malformed to let the downstream
      # storage processor skip them.
      def dependencies
        raise MethodNotImplementedError
      end

      # Is the whole manifest file malformed? The behavior
      # here is ecosystem dependent, but typically this
      # will only occur if:
      #
      # 1. The manifest file is encoded incorrectly or corrupted
      # 2. Expected global fields like project name and version are missing
      #
      # Note: individual malformed depenencies respond to "malformed?" but
      # usually not cause the parent manifest to be malformed (also ecosystem
      # dependent)
      def malformed?
        raise MethodNotImplementedError
      end
    end

  end
end
