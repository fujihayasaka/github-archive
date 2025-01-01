# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class Ref < Platform::Loader
      def self.load(loader, name)
        return Promise.resolve(nil) unless name
        self.for(loader).load(name)
      end

      def initialize(loader)
        @loader = loader
      end

      private

      attr_reader :loader

      def fetch(names)
        Hash[names.zip(loader.qualified_refs(names))]
      end
    end
  end
end
