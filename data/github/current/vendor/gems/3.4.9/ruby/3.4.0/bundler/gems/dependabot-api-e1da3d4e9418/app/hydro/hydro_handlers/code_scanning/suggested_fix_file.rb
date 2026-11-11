# frozen_string_literal: true

module HydroHandlers
  module CodeScanning
    class SuggestedFixFile
      VALID_KEYS = %i(
        file_path
        diff_content
      ).freeze

      attr_reader :attributes

      def initialize(attributes)
        @attributes = attributes
      end

      def file_path
        attributes.fetch(:file_path)
      end

      def diff_content
        attributes.fetch(:diff_content)
      end

      def file_path_hash
        RbNaCl::Hash.sha256(file_path)
      end

      def file_checksum
        Digest::SHA1.digest(diff_content)
      end
    end
  end
end
