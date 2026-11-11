# typed: strict
# frozen_string_literal: true

module Sponsors
  class BulkSponsorshipImportProcessor
    class Result
      sig do
        params(
          amounts_by_sponsorable_login_array: T::Array[{ sponsorable_login: String, amount: T.any(String, Integer) }],
          included_headers: T::Array[String],
        ).returns(Result)
      end
      def self.success(amounts_by_sponsorable_login_array:, included_headers:)
        new(amounts_by_sponsorable_login_array: amounts_by_sponsorable_login_array, included_headers: included_headers)
      end

      sig { params(errors: T::Array[String]).returns(Result) }
      def self.failure(errors:)
        new(errors: errors)
      end

      # Public: Represents data from "Maintainer username" and "Sponsorship amount in USD" columns in the CSV file.
      sig { returns T::Array[{ sponsorable_login: String, amount: T.any(String, Integer) }] }
      attr_reader :amounts_by_sponsorable_login_array

      # Public: Header names that were included in the CSV file. Will only include known values that we might expect
      # to see.
      sig { returns T::Array[String] }
      attr_reader :included_headers

      # Public: Human-readable error messages.
      sig { returns T::Array[String] }
      attr_reader :errors

      sig do
        params(
          amounts_by_sponsorable_login_array: T::Array[{ sponsorable_login: String, amount: T.any(String, Integer) }],
          errors: T::Array[String],
          included_headers: T::Array[String],
        ).void
      end
      def initialize(amounts_by_sponsorable_login_array: [], errors: [], included_headers: [])
        @amounts_by_sponsorable_login_array = amounts_by_sponsorable_login_array
        @errors = errors
        @included_headers = included_headers
      end

      # Public: Was the given CSV file parsed successfully and contained the necessary data? Does not reflect whether
      # the contained data constitutes valid sponsorships; can be used with Sponsors::BulkSponsorshipValidator
      # and Sponsors::BulkSponsorshipRow for that.
      sig { returns T::Boolean }
      def valid?
        errors.empty?
      end
    end
  end
end
