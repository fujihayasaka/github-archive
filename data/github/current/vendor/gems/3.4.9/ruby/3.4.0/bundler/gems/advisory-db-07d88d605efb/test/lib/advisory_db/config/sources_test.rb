# frozen_string_literal: true

require "test_helper"

class SourcesTest < ActiveSupport::TestCase
  test "Source list has expected order" do
    # The order of expected sources should never change
    # Also, the values should never be removed, only added to
    # When a source is deprecated, it should still persist in the expected source list
    # The reason for this is that AdvisoryDB.sources is used an enum in FeedEntry model
    # Change the order/contents of an enum changes the values assigned to records, which we do not want.
    # SO, make sure that sources are only ever added to :)
    expected_sources = [
      "nvd",
      "white_source",
      "cve_list",
      "friends_of_php",
      "rubysec",
      "repository_advisories",
      "cve_review",
      "backfill",
      "npm",
      "rustsec",
      "advisory_improvement",
      "pypa_advisory",
      "malware_advisory",
      "go",
      # Add new source here!
      #
      # munger is a test source, added only for testing in test/test_helper.rb
      # therefore, munger should always be the final source in this test
      "munger",
    ]
    assert_equal expected_sources, AdvisoryDB.sources
  end

  test "importer_sources does not include sources which do not currently have an importer" do
    refute AdvisoryDB.importer_sources.include?("npm")
  end

  test "all importer_sources have importers" do
    assert AdvisoryDB.importer_sources.count > 0

    AdvisoryDB.importer_sources.each do |importer_source|
      importer_class = ApplicationImporter.importer_for_source(importer_source)
      assert importer_class.method_defined?(:import)
    end
  end

  test "sources_subject_to_blocklist is only the nvd source currently" do
    assert_equal ["nvd"], AdvisoryDB.sources_subject_to_blocklist
  end

  test "untursted_sources is only the advisory_improvement source currently" do
    assert_equal ["advisory_improvement"], AdvisoryDB.untrusted_sources
  end
end
