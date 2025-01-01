# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning
  module Models
    class Location
      sig { returns(T.nilable(String)) }
      attr_reader :commit_oid
      sig { returns(T.nilable(String)) }
      attr_reader :blob_oid
      sig { returns(T.nilable(String)) }
      attr_reader :path
      sig { returns(Integer) }
      attr_reader :start_line
      sig { returns(Integer) }
      attr_reader :end_line
      sig { returns(Integer) }
      attr_reader :start_line_byte_position
      sig { returns(Integer) }
      attr_reader :end_line_byte_position

      sig do
        params(
          commit_oid: T.nilable(String),
          blob_oid: T.nilable(String),
          path: T.nilable(String),
          start_line: Integer,
          end_line: Integer,
          start_line_byte_position: Integer,
          end_line_byte_position: Integer).void
      end
      def initialize(commit_oid: "", blob_oid: "", path: "", start_line: 0, end_line: 0, start_line_byte_position: 0, end_line_byte_position: 0)
        @commit_oid = commit_oid
        @blob_oid = blob_oid
        @path = path
        @start_line = start_line
        @end_line = end_line
        @start_line_byte_position = start_line_byte_position
        @end_line_byte_position = end_line_byte_position
      end

      sig { params(hash: T.nilable(Hash)).returns(Location) }
      def self.from_hash(hash)
        return new if hash.nil?

        hash = hash.with_indifferent_access
        new(
          commit_oid: hash[:commit_oid] || "",
          blob_oid: hash[:blob_oid] || "",
          path: hash[:path] || "",
          start_line: hash[:start_line] || 0,
          end_line: hash[:end_line] || 0,
          start_line_byte_position: hash[:start_line_byte_position] || 0,
          end_line_byte_position: hash[:end_line_byte_position] || 0,
        )
      end
    end
  end
end
