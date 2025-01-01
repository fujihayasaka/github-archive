# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning
  module Models
    class RepoBlobTokenLocation < TokenLocation
      attr_reader :commit_oid, :blob_oid, :path, :start_line, :end_line, :result_location

      sig do
        params(
          commit_oid:  T.nilable(String),
          blob_oid: T.nilable(String),
          path: T.nilable(String),
          start_line: T.nilable(Integer),
          end_line: T.nilable(Integer),
          result_location: T.nilable(GitHub::TokenScanning::Service::TokenLocation)
        ).void
      end
      def initialize(commit_oid: "", blob_oid: "", path: "", start_line: 0, end_line: 0, result_location: nil)
        @commit_oid = commit_oid
        @blob_oid = blob_oid
        @path = path
        @start_line = start_line
        @end_line = end_line
        @result_location = result_location
      end
    end
  end
end
