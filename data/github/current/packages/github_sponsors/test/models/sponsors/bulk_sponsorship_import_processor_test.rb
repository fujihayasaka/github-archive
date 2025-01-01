# typed: true
# frozen_string_literal: true

require "test_helper"

class Sponsors::BulkSponsorshipImportProcessorTest < GitHub::TestCase
  include HydroTestHelpers

  context ".call" do
    test "returns an error result when a required column is missing in the given file" do
      path = "test/fixtures/files/sponsors/bulk-sponsorships-missing-columns.csv"
      result = File.open(Rails.root.join(path)) do |file|
        Sponsors::BulkSponsorshipImportProcessor.call(file: file)
      end

      assert_instance_of Sponsors::BulkSponsorshipImportProcessor::Result, result
      refute_predicate result, :valid?
      assert_equal ["Not all required columns exist in the given CSV file. Missing: Sponsorship amount in USD"],
        result.errors
      assert_empty result.amounts_by_sponsorable_login_array
    end

    test "returns an error result when an empty file is given" do
      result = File.open(Rails.root.join("test/fixtures/files/sponsors/empty-bulk-sponsorships.csv")) do |file|
        Sponsors::BulkSponsorshipImportProcessor.call(file: file)
      end

      assert_instance_of Sponsors::BulkSponsorshipImportProcessor::Result, result
      refute_predicate result, :valid?
      assert_equal ["The CSV file you uploaded was empty."], result.errors
      assert_empty result.amounts_by_sponsorable_login_array
    end

    test "returns an error result when file has no data rows" do
      result = File.open(Rails.root.join("test/fixtures/files/sponsors/bulk-sponsorships-header-only.csv")) do |file|
        Sponsors::BulkSponsorshipImportProcessor.call(file: file)
      end

      assert_instance_of Sponsors::BulkSponsorshipImportProcessor::Result, result
      refute_predicate result, :valid?
      assert_equal ["The CSV file you uploaded didn't specify any sponsorships."], result.errors
      assert_empty result.amounts_by_sponsorable_login_array
    end

    test "returns a successful result when given file provides the right data in the expected format" do
      result = File.open(Rails.root.join("test/fixtures/files/sponsors/bulk-sponsorships.csv")) do |file|
        Sponsors::BulkSponsorshipImportProcessor.call(file: file)
      end

      assert_instance_of Sponsors::BulkSponsorshipImportProcessor::Result, result
      assert_predicate result, :valid?
      assert_empty result.errors
      assert_equal([
        { sponsorable_login: "maintainer1", amount: "5" },
        { sponsorable_login: " @Maintainer2 ", amount: "8" },
        { sponsorable_login: "maintainer2", amount: "10" },
        { sponsorable_login: "maintainer3", amount: "$12.00" },
        { sponsorable_login: "mAIntainer4", amount: "3" },
        { sponsorable_login: "maintainer5", amount: "$10.00" },
        { sponsorable_login: "maintainer5", amount: "$100.00" },
      ], result.amounts_by_sponsorable_login_array)
    end

    test "uses default values when only required columns are in the given file" do
      path = "test/fixtures/files/sponsors/bulk-sponsorships-required-columns-only.csv"
      result = File.open(Rails.root.join(path)) do |file|
        Sponsors::BulkSponsorshipImportProcessor.call(file: file)
      end

      assert_instance_of Sponsors::BulkSponsorshipImportProcessor::Result, result
      assert_predicate result, :valid?
      assert_empty result.errors
      assert_equal([
        { sponsorable_login: "maintainer1", amount: "20" },
        { sponsorable_login: " @Maintainer2 ", amount: "50" },
        { sponsorable_login: "maintainer3", amount: "500" },
      ], result.amounts_by_sponsorable_login_array)
    end

    test "processes LF line endings" do
      expected_file_read = "Maintainer username,Sponsorship amount in USD\nmaintainer1,10\nmaintainer2,20"
      File.any_instance.stubs(:read).returns(expected_file_read)

      result = File.open(Rails.root.join("test/fixtures/files/sponsors/bulk-sponsorships.csv")) do |file|
        Sponsors::BulkSponsorshipImportProcessor.call(file: file)
      end

      assert_instance_of Sponsors::BulkSponsorshipImportProcessor::Result, result
      assert_predicate result, :valid?
      assert_empty result.errors
      assert_equal([
        { sponsorable_login: "maintainer1", amount: "10" },
        { sponsorable_login: "maintainer2", amount: "20" },
      ], result.amounts_by_sponsorable_login_array)
    end

    test "processes CR line endings" do
      expected_file_read = "Maintainer username,Sponsorship amount in USD\rmaintainer1,10\rmaintainer2,20"
      File.any_instance.stubs(:read).returns(expected_file_read)

      result = File.open(Rails.root.join("test/fixtures/files/sponsors/bulk-sponsorships.csv")) do |file|
        Sponsors::BulkSponsorshipImportProcessor.call(file: file)
      end

      assert_instance_of Sponsors::BulkSponsorshipImportProcessor::Result, result
      assert_predicate result, :valid?
      assert_empty result.errors
      assert_equal([
        { sponsorable_login: "maintainer1", amount: "10" },
        { sponsorable_login: "maintainer2", amount: "20" },
      ], result.amounts_by_sponsorable_login_array)
    end

    test "processes CRLF line endings" do
      expected_file_read = "Maintainer username,Sponsorship amount in USD\r\nmaintainer1,10\r\nmaintainer2,20"
      File.any_instance.stubs(:read).returns(expected_file_read)

      result = File.open(Rails.root.join("test/fixtures/files/sponsors/bulk-sponsorships.csv")) do |file|
        Sponsors::BulkSponsorshipImportProcessor.call(file: file)
      end

      assert_instance_of Sponsors::BulkSponsorshipImportProcessor::Result, result
      assert_predicate result, :valid?
      assert_empty result.errors
      assert_equal([
        { sponsorable_login: "maintainer1", amount: "10" },
        { sponsorable_login: "maintainer2", amount: "20" },
      ], result.amounts_by_sponsorable_login_array)
    end

    # https://github.com/github/sponsors/issues/4447
    test "processes mixed LF and CRLF line endings" do
      expected_file_read = "Maintainer username,Sponsorship amount in USD\r\nmaintainer1,10\nmaintainer2,20"
      File.any_instance.stubs(:read).returns(expected_file_read)

      result = File.open(Rails.root.join("test/fixtures/files/sponsors/bulk-sponsorships.csv")) do |file|
        Sponsors::BulkSponsorshipImportProcessor.call(file: file)
      end

      assert_instance_of Sponsors::BulkSponsorshipImportProcessor::Result, result
      assert_predicate result, :valid?
      assert_empty result.errors
      assert_equal([
        { sponsorable_login: "maintainer1", amount: "10" },
        { sponsorable_login: "maintainer2", amount: "20" },
      ], result.amounts_by_sponsorable_login_array)
    end
  end

  context "instrument_file_import_failure" do
    test "sends proper hydro payload when file has incorrect format" do
      path = "test/fixtures/files/rails.svg"
      result = File.open(Rails.root.join(path)) do |file|
        Sponsors::BulkSponsorshipImportProcessor.call(file: file)
      end

      assert_instance_of Sponsors::BulkSponsorshipImportProcessor::Result, result
      refute_predicate result, :valid?

      expected_message = {
        file_error: :INCORRECT_FORMAT,
        frequency: :ONE_TIME,
        included_headers: []
      }
      assert_hydro_published(expected_message, schema: "github.sponsors.v1.BulkSponsorshipsImport")
      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.BulkSponsorshipsImport")
    end

    test "sends proper hydro payload when file is empty" do
      path = "test/fixtures/files/sponsors/empty-bulk-sponsorships.csv"
      result = File.open(Rails.root.join(path)) do |file|
        Sponsors::BulkSponsorshipImportProcessor.call(file: file)
      end

      assert_instance_of Sponsors::BulkSponsorshipImportProcessor::Result, result
      refute_predicate result, :valid?

      expected_message = {
        file_error: :EMPTY,
        frequency: :ONE_TIME,
        included_headers: []
      }
      assert_hydro_published(expected_message, schema: "github.sponsors.v1.BulkSponsorshipsImport")
      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.BulkSponsorshipsImport")
    end

    test "sends proper hydro payload when file is missing required columns" do
      path = "test/fixtures/files/sponsors/bulk-sponsorships-missing-columns.csv"
      result = File.open(Rails.root.join(path)) do |file|
        Sponsors::BulkSponsorshipImportProcessor.call(file: file)
      end

      assert_instance_of Sponsors::BulkSponsorshipImportProcessor::Result, result
      refute_predicate result, :valid?

      expected_message = {
        file_error: :MISSING_COLUMNS,
        frequency: :ONE_TIME,
        included_headers: [:MAINTAINER_USERNAME]
      }
      assert_hydro_published(expected_message, schema: "github.sponsors.v1.BulkSponsorshipsImport")
      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.BulkSponsorshipsImport")
    end

    test "sends recurring frequency in hydro payload when passed in" do
      path = "test/fixtures/files/rails.svg"
      result = File.open(Rails.root.join(path)) do |file|
        Sponsors::BulkSponsorshipImportProcessor.call(file: file, frequency: :recurring)
      end

      assert_instance_of Sponsors::BulkSponsorshipImportProcessor::Result, result
      refute_predicate result, :valid?

      expected_message = {
        file_error: :INCORRECT_FORMAT,
        frequency: :RECURRING,
        included_headers: []
      }
      assert_hydro_published(expected_message, schema: "github.sponsors.v1.BulkSponsorshipsImport")
      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.BulkSponsorshipsImport")
    end
  end
end
