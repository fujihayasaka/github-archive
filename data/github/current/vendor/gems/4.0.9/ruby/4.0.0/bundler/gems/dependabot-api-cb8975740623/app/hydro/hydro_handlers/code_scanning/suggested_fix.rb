# frozen_string_literal: true

module HydroHandlers
  module CodeScanning
    class SuggestedFix
      VALID_KEYS = %i(
        description
        dependency_metadata
        files
      ).freeze

      def self.from_message(message)
        attributes = message.value.fetch(:suggested_fix)

        # :suggested_fix is nil in the hydro message if it wasn't provided
        return unless attributes

        new(attributes.slice(*VALID_KEYS))
      end

      attr_reader :attributes

      def initialize(attributes)
        @attributes = attributes
      end

      def description
        attributes.fetch(:description)
      end

      def dependency_metadata
        attributes.fetch(:dependency_metadata, []).map do |attrs|
          DependencyMetadata.new(attrs.slice(*DependencyMetadata::VALID_KEYS))
        end
      end

      def suggested_fix_files
        attributes.fetch(:files, []).map do |attrs|
          SuggestedFixFile.new(attrs.slice(*SuggestedFixFile::VALID_KEYS))
        end
      end
    end
  end
end
