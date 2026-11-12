# frozen_string_literal: true

require "test_helper"

class FriendsOfPHPImporterTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "knows its source" do
    assert_equal "friends_of_php", FriendsOfPHPImporter.source
    assert_equal "friends_of_php", FriendsOfPHPImporter.new.source
  end

  test "can import just a single specific advisory, by path" do
    advisory_path = "api-platform/core/CVE-2019-1000011.yaml"
    importer = FriendsOfPHPImporter.new(specific_advisory_path: advisory_path)

    import_items = []
    VCR.use_cassette("friends_of_php_CVE-2019-1000011.yaml") do
      importer.each do |import_item|
        import_items << import_item
      end
    end
    assert_equal 1, import_items.length
    import_item = import_items.first
    assert_equal "friends_of_php/api-platform/core/CVE-2019-1000011.yaml", import_item[:identifier]
  end

  test "associates separate files which reference same CVE under same advisory review" do
    # several distinct files which have the same cve id
    advisory_paths = [
      "symfony/security-http/CVE-2019-10911.yaml",
      "symfony/security/CVE-2019-10911.yaml",
      "symfony/symfony/CVE-2019-10911.yaml",
    ]
    VCR.use_cassette("friends_of_php_CVE-2019-10911.yaml") do
      perform_enqueued_jobs(only: [ResolveFeedEntryJob, ImportJob]) do
        advisory_paths.each do |path|
          FriendsOfPHPImporter.new(specific_advisory_path: path).import(report_to_slack: false)
        end
      end
    end
    assert advisory_review = AdvisoryReview.find_by(cve_id: "CVE-2019-10911")
    assert_equal [
      "friends_of_php/symfony/security-http/CVE-2019-10911.yaml",
      "friends_of_php/symfony/security/CVE-2019-10911.yaml",
      "friends_of_php/symfony/symfony/CVE-2019-10911.yaml",
    ], advisory_review.feed_entries.pluck(:identifier).sort
  end

  test "feed entry gets attached to existing advisory review with matching CVE ID if record has CVE ID" do
    advisory_review = create :advisory_review, :closed, cve_id: "CVE-2018-17057", feed_entry_count: 1
    assert advisory_review.closed?

    VCR.use_cassette("friends_of_php_CVE-2018-17057.yaml") do
      perform_enqueued_jobs(only: [ResolveFeedEntryJob]) do
        FriendsOfPHPImporter.new(specific_advisory_path: "wallabag/tcpdf/CVE-2018-17057.yaml").import
      end
    end

    advisory_review.reload
    assert advisory_review.feed_entries.pluck(:identifier).include?("friends_of_php/wallabag/tcpdf/CVE-2018-17057.yaml")
    assert advisory_review.open?
  end

  test "can do a bulk import of updated advisories" do
    create(:import, source: "friends_of_php", started_at: "2022-03-17", finished_at: "2022-03-17", bulk: true)

    VCR.use_cassette("friends_of_php_updated_files") do
      assert FriendsOfPHPImporter.new.count > 1
    end
  end
end

class FriendsOfPHPAdvisoryTest < ActiveSupport::TestCase
  setup do
    @php_advisory_a = VCR.use_cassette("friends_of_php_CVE-2019-1000011.yaml") do
      FriendsOfPHPAdvisory.initialize_from_path("api-platform/core/CVE-2019-1000011.yaml")
    end
  end

  test "identifier is based on path" do
    assert_equal \
      "friends_of_php/api-platform/core/CVE-2019-1000011.yaml",
      @php_advisory_a.identifier
  end

  test "ensure no advisory created on non-yaml file" do
    VCR.use_cassette("friends_of_php_validator_php") do
      assert_raises do
        FriendsOfPHPAdvisory.initialize_from_path("validator.php")
      end
    end
  end

  test "ensure no advisory created on moved" do
    VCR.use_cassette("friends_of_php_moved_advisory_php") do
      assert_raises do
        FriendsOfPHPAdvisory.initialize_from_path("guzzlehttp/psr7/GHSA-q7rv-6hp3-vh96.yaml")
      end
    end
  end

  test "ensure no advisory created on non-advisory yaml file" do
    VCR.use_cassette("friends_of_php_github_action_yaml") do
      assert_raises do
        FriendsOfPHPAdvisory.initialize_from_path(".github/workflows/php.yaml")
      end
    end
  end

  test "vulnerabilities list for simple case where each range has unique patch version" do
    expected_vulnerabilities = {
      0 => {
        ecosystem: "composer",
        package_name: "api-platform/core",
        vulnerable_version_range: ">= 2.2.0, < 2.2.10",
        first_patched_version: "2.2.10",
      },
      1 => {
        ecosystem: "composer",
        package_name: "api-platform/core",
        vulnerable_version_range: ">= 2.3.0, < 2.3.6",
        first_patched_version: "2.3.6",
      },
    }
    assert_equal expected_vulnerabilities, @php_advisory_a.vulnerabilities
  end

  test "vulnerabilities list for case where ranges need to be combined" do
    test_advisory = VCR.use_cassette("friends_of_php_CVE-2019-10909.yaml") do
      FriendsOfPHPAdvisory.initialize_from_path("symfony/symfony/CVE-2019-10909.yaml")
    end
    expected_vulnerabilities = {
      0 => {
        ecosystem: "composer",
        package_name: "symfony/symfony",
        vulnerable_version_range: ">= 2.7.0, < 2.7.51",
        first_patched_version: "2.7.51",
      },
      1 => {
        ecosystem: "composer",
        package_name: "symfony/symfony",
        vulnerable_version_range: ">= 2.8.0, < 2.8.50",
        first_patched_version: "2.8.50",
      },
      2 => {
        ecosystem: "composer",
        package_name: "symfony/symfony",
        vulnerable_version_range: ">= 3.0.0, < 3.4.26",
        first_patched_version: "3.4.26",
      },
      3 => {
        ecosystem: "composer",
        package_name: "symfony/symfony",
        vulnerable_version_range: ">= 4.0.0, < 4.1.12",
        first_patched_version: "4.1.12",
      },
      4 => {
        ecosystem: "composer",
        package_name: "symfony/symfony",
        vulnerable_version_range: ">= 4.2.0, < 4.2.7",
        first_patched_version: "4.2.7",
      },
    }
    assert_equal expected_vulnerabilities, test_advisory.vulnerabilities
  end

  test "generates a full import object, ready for application importer" do
    expected_importer_object = {
      identifier: "friends_of_php/api-platform/core/CVE-2019-1000011.yaml",
      cve_id: "CVE-2019-1000011",
      friends_of_php_id: "api-platform/core/CVE-2019-1000011.yaml",
      raw_payload: {
        "title" => "CVE-2019-1000011: Access control bypass in GraphQL mutations",
        "link" => "https://github.com/api-platform/core/pull/2441",
        "cve" => "CVE-2019-1000011",
        "branches" => {
          "2.2.x" => {
            "time" => Time.zone.parse("2019-01-15 17:30:00 +0000"),
            "versions" => [">=2.2.0", "<2.2.10"],
          },
          "2.3.x" => {
            "time" => Time.zone.parse("2019-01-15 17:30:00 +0000"),
            "versions" => [">=2.3.0", "<2.3.6"],
          },
        },
        "reference" => "composer://api-platform/core",
      },
      advisory_payload: {
        summary: "CVE-2019-1000011: Access control bypass in GraphQL mutations",
        description: nil,
        severity: nil,
        references: [
          "https://github.com/api-platform/core/pull/2441",
          "https://github.com/FriendsOfPHP/security-advisories/blob/master/api-platform/core/CVE-2019-1000011.yaml",
        ],
        vulnerabilities: {
          0 => {
            ecosystem: "composer",
            package_name: "api-platform/core",
            vulnerable_version_range: ">= 2.2.0, < 2.2.10",
            first_patched_version: "2.2.10",
          },
          1 => {
            ecosystem: "composer",
            package_name: "api-platform/core",
            vulnerable_version_range: ">= 2.3.0, < 2.3.6",
            first_patched_version: "2.3.6",
          },
        },
        withdrawn: false,
      },
    }
    assert_equal expected_importer_object, @php_advisory_a.importer_object
  end
end

# This is all the difference cases that are needed to be covered:
# I got this by running this in repo: $  grep -h -r "versions: " . | egrep -o "\[.*]" | gsed "s/'//g"  | gsed -E 's/[0-9.]+/x/g' | sort | uniq
# ---
# - [<=x-alphax]
# - [<=x]
# - [<x]
# - [>x, <x]
# - [>=x, <x]
# - [>=x, <=x]
# - [>=x-alphax, <=x-alphax]

class FriendsOfPHPAdvisoryVersionRangeTest < ActiveSupport::TestCase
  {
    ["<2.1.1"] => [  # input string
      "< 2.1.1",     # expected version range
      "2.1.1", # expected first patched version, nil if none
    ],
    ["<=1.0.0-alpha11"] => [
      "<= 1.0.0-alpha11",
      nil,
    ],
    ["<=1.8.1"] => [
      "<= 1.8.1",
      nil,
    ],
    [">0.7.1", "<1.0.4"] => [
      "> 0.7.1, < 1.0.4",
      "1.0.4",
    ],
    [">=3.0.0", "<=3.5.2"] => [
      ">= 3.0.0, <= 3.5.2",
      nil,
    ],
    [">=1.0.0", "<1.0.17"] => [
      ">= 1.0.0, < 1.0.17",
      "1.0.17",
    ],
    [">=2.0.0-alpha1", "<=2.0.0-alpha7"] => [
      ">= 2.0.0-alpha1, <= 2.0.0-alpha7",
      nil,
    ],
  }.each_pair do |range_pair, (expected_vulnerable_version_range, expected_first_patched_version)|
    test "should parse range pair: #{range_pair} correctly" do
      rp = FriendsOfPHPAdvisory::VersionRange.new(range_pair)
      assert_equal expected_vulnerable_version_range, rp.vulnerable_version_range
      if expected_first_patched_version
        assert_equal expected_first_patched_version, rp.first_patched_version
      else
        assert_nil rp.first_patched_version
      end
    end
  end
end
