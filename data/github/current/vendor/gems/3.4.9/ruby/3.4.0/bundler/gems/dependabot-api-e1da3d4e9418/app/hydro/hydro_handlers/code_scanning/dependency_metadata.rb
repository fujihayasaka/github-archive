# frozen_string_literal: true

module HydroHandlers
  module CodeScanning
    class DependencyMetadata
      VALID_KEYS = %i(
        name
        version
      ).freeze

      attr_reader :attributes

      def initialize(attributes)
        @attributes = attributes
      end

      def name
        attributes.fetch(:name)
      end

      def version
        attributes.fetch(:version)
      end

      def to_h
        {
          name: name,
          version: version,
        }
      end
    end
  end
end
