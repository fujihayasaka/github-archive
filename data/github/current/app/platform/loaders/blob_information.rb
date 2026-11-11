# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class BlobInformation < Platform::Loader
      def self.load(repository, blob_oid)
        self.for(repository).load(blob_oid)
      end

      def initialize(repository)
        @repository = repository
      end

      def fetch(blob_oids)
        repository.read_objects(
          blob_oids, "blob", true).map do |info|
          [info["oid"], info]
        end.to_h
      end

      private

      attr_reader :repository
    end
  end
end
