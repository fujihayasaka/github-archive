module Snapshots
  class Manifest
    attr_reader :path, :oid, :dependencies

    def initialize(path: , oid:, dependencies:)
      @path = path
      @oid = oid
      @dependencies = dependencies
    end

    def ==(other)
      @path == other.path && @oid == other.oid && @dependencies == other.dependencies
    end
  end
end
