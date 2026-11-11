# frozen_string_literal: true

require "test_helper"

class GoImporterTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @error_list = nil
  end

  test "knows its source" do
    assert_equal "go", GoImporter.source
    assert_equal "go", GoImporter.new.source
  end

  test "can import a specific advisory with one CVE/GHSA by advisory_id using common interface" do
    advisory_id = "GO-2020-0036"
    importer = GoImporter.new(specific_advisory_id: advisory_id)
    import_items = import_and_collect_import_items("go_GO-2020-0036", importer)

    assert_equal 1, import_items.length
    import_item = import_items.first
    assert_equal "golang/GO-2020-0036", import_item[:identifier]
    assert_equal "GHSA-wxc4-f4m6-wwqv", import_item[:ghsa_id]
    assert_includes import_item[:advisory_payload][:references], "https://pkg.go.dev/vuln/GO-2020-0036"
    vulnerability_hash = { 0 => {
      ecosystem: "go",
      package_name: "gopkg.in/yaml.v2",
      vulnerable_version_range: "< 2.2.8",
      first_patched_version: "2.2.8",
    }, 1 => {
      ecosystem: "go",
      package_name: "github.com/go-yaml/yaml",
      vulnerable_version_range: "> 0",
      first_patched_version: nil,
    } }
    assert_equal vulnerability_hash, import_item[:advisory_payload][:vulnerabilities]
  end

  test "can import a specific advisory with `cve_metadata` field by advisory_id" do
    advisory_id = "GO-2020-0033"
    importer = GoImporter.new(specific_advisory_id: advisory_id)
    import_items = import_and_collect_import_items("go_GO-2020-0033", importer)

    assert_equal 1, import_items.length
    import_item = import_items.first

    assert_equal "golang/GO-2020-0033", import_item[:identifier]
    assert_nil import_item[:ghsa_id]
    assert_equal "CVE-2020-36559", import_item[:cve_id]
  end

  test "can import a specific advisory with multiple CVEs by advisory_id" do
    advisory_id = "GO-2022-0536"
    importer = GoImporter.new(specific_advisory_id: advisory_id)
    import_items = import_and_collect_import_items("go_GO-2022-0536", importer)

    assert_equal 2, import_items.length

    import_items.each do |item|
      # These GO advisories don't have GHSA ids assigned during import.
      assert_nil item[:ghsa_id]
      assert_nil item[:advisory_payload][:ghsa_id]
    end

    assert_equal "golang/GO-2022-0536/CVE-2019-9512", import_items.first[:identifier]
    assert_equal "golang/GO-2022-0536/CVE-2019-9514", import_items.second[:identifier]

    assert_equal "CVE-2019-9512", import_items.first[:cve_id]
    assert_equal "CVE-2019-9514", import_items.second[:cve_id]
  end

  test "can import a specific advisory with multiple GHSAs by advisory_id" do
    advisory_id = "GO-2022-0386"
    importer = GoImporter.new(specific_advisory_id: advisory_id)
    import_items = import_and_collect_import_items("go_GO-2022-0386", importer)

    assert_equal 4, import_items.length
    assert_equal ["golang/GO-2022-0386/CVE-2021-3127",
                  "golang/GO-2022-0386/GHSA-j756-f273-xhp4",
                  "golang/GO-2022-0386/GHSA-62mh-w5cv-p88c",
                  "golang/GO-2022-0386/GHSA-9r5x-fjv3-q6h4"],
      import_items.pluck(:identifier)

    ghsas_in_import_items = import_items.filter_map { |import_item| import_item[:ghsa_id] if import_item.include? :ghsa_id }
    assert_includes ghsas_in_import_items, "GHSA-j756-f273-xhp4"
    assert_includes ghsas_in_import_items, "GHSA-62mh-w5cv-p88c"
  end

  test "does not import a specific advisory if it contains only restricted packages" do
    # GO-2022-0189 is a test advisory that affects only the restricted toolchain package
    # https://go.dev/doc/security/vuln/database#examples
    advisory_id = "GO-2022-0189"
    importer = GoImporter.new(specific_advisory_id: advisory_id)
    import_items = import_and_collect_import_items("go_GO-2022-0189", importer)

    assert_empty import_items, "Expected import_items to be empty but it contained #{import_items.size} items"
  end

  test "can do a bulk import" do
    importer = GoImporter.new(backfill: true)
    stub_failbot_reporting!

    VCR.use_cassette("golang_bulk_import") do
      assert_difference -> { FeedEntry.count }, 432 do
        importer.import
      end
    end

    assert_no_reserved_packages_names_in_feed_entries
    assert_no_failbot_reports
  end

  test "delta import works" do
    importer = GoImporter.new(backfill: true)
    stub_failbot_reporting!

    # golang_delta_initial_import is a hand modified version of golang_bulk_import
    # we remove all entries after 12/30 to simulate a delta import operation.
    # (this also includes all modules that had a modified date > 12/30)
    Timecop.freeze(2023, 12, 30) do
      VCR.use_cassette("golang_delta_initial_import") do
        importer.import
      end
    end

    assert_equal 398, FeedEntry.count

    # golang_delta_import is a "normal" looking bulk import as of 3/2/2024.
    # running this after the initial import should result in records published after 12/30/2023 showing up.
    VCR.use_cassette("golang_delta_import") do
      importer = GoImporter.new(backfill: false)
      importer.import
    end

    assert_equal 432, FeedEntry.count

    assert_no_reserved_packages_names_in_feed_entries
    assert_no_failbot_reports
  end

  test "doesn't bother importing anything if the database hasn't been modified since the last update" do
    importer = GoImporter.new(backfill: true)
    VCR.use_cassette("golang_noop_initial_import") do
      assert_difference -> { FeedEntry.count }, 432 do
        importer.import
      end
    end

    WebMock.assert_requested(:get, "#{GoImporter::BASE_URI}/#{GoImporter::INDEX_URI_PATH}", times: 1)
    WebMock.assert_not_requested(:get, "#{GoImporter::BASE_URI}/#{GoImporter::METADATA_URI_PATH}")
    WebMock.reset!

    delta_importer = GoImporter.new(backfill: false)
    VCR.use_cassette("golang_noop_delta_import") do
      assert_no_difference -> { FeedEntry.count } do
        delta_importer.import
      end
    end

    WebMock.assert_requested(:get, "#{GoImporter::BASE_URI}/#{GoImporter::METADATA_URI_PATH}", times: 1)
    WebMock.assert_not_requested(:get, "#{GoImporter::BASE_URI}/#{GoImporter::INDEX_URI_PATH}")
  end

  test "verify resolve changes works without error for goimporter output" do
    Failbot.expects(:report!).never
    # There's a note in ApplicationJob about how resque Failbot.reports,
    # but doing that in resque means we have to look elsewhere in a local test.
    # If you see an error here, you want to inspect what is getting logged.
    ::GitHub::Telemetry::Logs.logger.expects("error").never

    perform_enqueued_jobs(only: [ResolveFeedEntryJob]) do
      VCR.use_cassette("resolve_feed_check_golang_results") do
        importer = GoImporter.new(specific_advisory_id: "GO-2022-0755")
        importer.import
      end

      VCR.use_cassette("resolve_feed_check_golang_results_delta") do
        # delta is a hand edited version of go_resolve_feed_check_results:
        # We make sure the feed entry will show up a little different and result in an update.
        importer = GoImporter.new(specific_advisory_id: "GO-2022-0755")
        importer.import
      end
    end
  end

  def assert_no_reserved_packages_names_in_feed_entries
    all_vulnerabilities = FeedEntry.all.to_a.filter_map(&:advisory_payload).filter_map do |ap|
      ap["vulnerabilities"]
    end
    all_package_names = all_vulnerabilities.map do |vuln_hash|
      vuln_hash.map do |_key, value|
        value["package_name"]
      end
    end.flatten
    GoImporter::RESERVED_PACKAGE_NAMES.each do |name|
      refute all_package_names.include?(name)
    end
  end

  def stub_failbot_reporting!
    @error_list = []
    Failbot.stubs(:report!).with do |error, _hash|
      @error_list << error
    end
  end

  def assert_no_failbot_reports
    raise("Failbot reporting was not stubbed. Use `stub_failbot_reporting!`") unless @error_list.is_a?(Array)

    assert_empty @error_list
  end

  def import_and_collect_import_items(vcr_cassette_name, importer)
    import_items = []
    VCR.use_cassette(vcr_cassette_name) do
      importer.each do |import_item|
        import_items << import_item
      end
      yield importer if block_given?
    end
    import_items
  end
end
