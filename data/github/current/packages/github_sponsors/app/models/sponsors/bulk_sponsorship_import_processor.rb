# typed: strict
# frozen_string_literal: true

module Sponsors
  class BulkSponsorshipImportProcessor
    extend T::Sig
    include GitHub::Memoizer

    SPONSORABLE_LOGIN_FIELD = "Maintainer username"
    DOLLAR_AMOUNT_FIELD = "Sponsorship amount in USD"
    REQUIRED_FIELDS = T.let([SPONSORABLE_LOGIN_FIELD, DOLLAR_AMOUNT_FIELD].freeze, T::Array[String])
    LINE_ENDINGS_REGEX = T.let(/(\r\n)/.freeze, Regexp)

    HEADERS = T.let({
      SPONSORABLE_LOGIN_FIELD => :MAINTAINER_USERNAME,
      DOLLAR_AMOUNT_FIELD => :SPONSORSHIP_AMOUNT_IN_USD,
    }.freeze, T::Hash[String, Symbol])

    # Public: Parses a CSV file for sponsorship information and checks if it has the right format, and if necessary
    # information was included.
    #
    # file - a File or ActionDispatch::Http::UploadedFile that responds to #read, expected to be in
    #        Comma-Separated Value format
    sig do
      params(
        file: T.any(File, ActionDispatch::Http::UploadedFile),
        frequency: Symbol,
      ).returns Sponsors::BulkSponsorshipImportProcessor::Result
    end
    def self.call(file:, frequency: :one_time)
      new(file: file, frequency: frequency).call
    end

    sig do
      params(
        file: T.any(File, ActionDispatch::Http::UploadedFile),
        frequency: Symbol,
      ).void
    end
    def initialize(file:, frequency:)
      @file = file
      @errors = T.let([], T::Array[String])
      @frequency = frequency
    end

    sig { returns Sponsors::BulkSponsorshipImportProcessor::Result }
    def call
      validate_not_empty
      validate_required_columns

      if @errors.any?
        instrument_file_import_failure
        Sponsors::BulkSponsorshipImportProcessor::Result.failure(errors: @errors)
      else
        Sponsors::BulkSponsorshipImportProcessor::Result.success(
          amounts_by_sponsorable_login_array: amounts_by_sponsorable_login_array,
          included_headers: included_headers
        )
      end
    end

    private

    sig { returns T.any(File, ActionDispatch::Http::UploadedFile) }
    attr_reader :file

    sig { void }
    def instrument_file_import_failure
      GlobalInstrumenter.instrument("sponsors.bulk_sponsorships_import",
        file_error: file_error,
        frequency: hydro_frequency,
        included_headers: included_headers,
      )
    end

    sig { returns Symbol }
    def hydro_frequency
      case @frequency
      when :recurring, :one_time then @frequency.upcase
      else
        :UNKNOWN_FREQUENCY
      end
    end

    sig { returns Symbol }
    def file_error
      return :INCORRECT_FORMAT if parsed_csv.nil?
      return :EMPTY if file_empty?
      return :MISSING_COLUMNS if missing_columns?

      :UNKNOWN
    end

    sig { returns T.nilable(CSV::Table) }
    memoize def parsed_csv
      file_contents = file.read
      normalized_file_contents = file_contents.gsub(/#{LINE_ENDINGS_REGEX}/, "\n")
      csv_table = CSV.parse(normalized_file_contents, headers: true)
      T.cast(csv_table, CSV::Table)
    rescue CSV::MalformedCSVError => e
      @errors << "The file you uploaded doesn't have the right format: #{e.message}"
      nil
    end

    sig { returns T.nilable(T::Boolean) }
    def file_empty?
      parsed_csv&.empty?
    end

    sig { void }
    def validate_not_empty
      return unless file_empty?

      file_problem = parsed_csv&.headers.present? ? "didn't specify any sponsorships" : "was empty"
      @errors << "The CSV file you uploaded #{file_problem}."
    end

    sig { returns T::Array[String] }
    def included_headers
      csv = parsed_csv
      return [] unless csv

      headers = REQUIRED_FIELDS.intersection(csv.headers)
      headers.each_with_object([]) { |column_value, included| included << HEADERS[column_value] }
    end

    sig { returns T::Boolean }
    def missing_columns?
      return false unless parsed_csv
      return false if file_empty?

      missing_headers.any?
    end

    sig { returns T::Array[String] }
    def missing_headers
      csv = parsed_csv
      return [] unless csv

      REQUIRED_FIELDS - csv.headers
    end

    sig { void }
    def validate_required_columns
      return unless missing_columns?

      @errors << "Not all required columns exist in the given CSV file. Missing: #{missing_headers.join(", ")}"
    end

    sig { returns T::Array[{ sponsorable_login: String, amount: T.any(String, Integer) }] }
    def amounts_by_sponsorable_login_array
      csv = parsed_csv
      return [] unless csv

      csv.map do |row|
        row = T.cast(row, CSV::Row)
        { sponsorable_login: row[SPONSORABLE_LOGIN_FIELD], amount: row[DOLLAR_AMOUNT_FIELD] }
      end
    end
  end
end
