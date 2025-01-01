# frozen_string_literal: true

require "test_helper"

class RubysecImporterTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "knows its source" do
    assert_equal "rubysec", RubysecImporter.source
    assert_equal "rubysec", RubysecImporter.new.source
  end

  test "can import just a single specific advisory, by path" do
    advisory_path = "gems/yard/CVE-2019-1020001.yml"
    importer = RubysecImporter.new(specific_advisory_path: advisory_path)

    import_items = []
    VCR.use_cassette("rubysec_CVE-2019-1020001.yml") do
      importer.each do |import_item|
        import_items << import_item
      end
    end
    assert_equal 1, import_items.length
    import_item = import_items.first
    assert_equal "rubysec/gems/yard/CVE-2019-1020001.yml", import_item[:identifier]
  end

  test "can do a bulk import of updated advisories" do
    create(:import, source: "rubysec", started_at: "2024-02-11", finished_at: "2024-02-11", bulk: true)

    VCR.use_cassette("rubysec_updated_files") do
      assert RubysecImporter.new.count > 1
    end
  end
end

class RubysecAdvisoryTest < ActiveSupport::TestCase
  setup do
    @ruby_advisory_a = nil

    VCR.use_cassette("rubysec_CVE-2019-1020001.yml") do
      @ruby_advisory_a = RubysecAdvisory.initialize_from_path("gems/yard/CVE-2019-1020001.yml")
    end

    @ruby_advisory_b = nil
    VCR.use_cassette("rubysec_CVE-2018-3777.yml") do
      @ruby_advisory_b = RubysecAdvisory.initialize_from_path("gems/restforce/CVE-2018-3777.yml")
    end

    @ruby_advisory_c = nil
    VCR.use_cassette("rubysec_CVE-2020-13163.yml") do
      @ruby_advisory_c = RubysecAdvisory.initialize_from_path("gems/em-imap/CVE-2020-13163.yml")
    end

    VCR.use_cassette("rubysec_CVE-2024-7106.yml") do
      @ruby_advisory_d = RubysecAdvisory.initialize_from_path("gems/spina/CVE-2024-7106.yml")
    end
  end

  def expected_importer_object
    {
      identifier: "rubysec/gems/yard/CVE-2019-1020001.yml",
      cve_id: "CVE-2019-1020001",
      rubysec_id: "gems/yard/CVE-2019-1020001.yml",
      raw_payload: expected_raw_payload,
      advisory_payload: expected_advisory_payload,
    }
  end

  def expected_raw_payload
    {
      gem: "yard",
      cve: "2019-1020001",
      ghsa: "xfhh-rx56-rxcr",
      url: "https://github.com/lsegal/yard/security/advisories/GHSA-xfhh-rx56-rxcr",
      date: Date.parse("Tue, 02 Jul 2019"),
      title: "Arbitrary path traversal and file access via `yard server`",
      description: expected_description,
      cvss_v2: 5.0,
      cvss_v3: 7.5,
      patched_versions: [">= 0.9.20"],
      related: {
        url: [
          "https://nvd.nist.gov/vuln/detail/CVE-2019-1020001",
          "https://github.com/lsegal/yard/security/advisories/GHSA-xfhh-rx56-rxcr",
        ],
      },
    }.deep_stringify_keys
  end

  def expected_advisory_payload
    {
      summary: "Arbitrary path traversal and file access via `yard server`",
      description: expected_description,
      severity: "high",
      references: [
        "https://github.com/lsegal/yard/security/advisories/GHSA-xfhh-rx56-rxcr",
        "https://github.com/rubysec/ruby-advisory-db/blob/master/gems/yard/CVE-2019-1020001.yml",
      ],
      vulnerabilities: expected_vulnerabilities,
      withdrawn: false,
    }
  end

  def expected_vulnerabilities
    {
      0 => {
        ecosystem: "rubygems",
        package_name: "yard",
        vulnerable_version_range: nil,
        first_patched_version: ">= 0.9.20",
      },
    }
  end

  def expected_vulnerability_with_no_patch_version
    {
      0 => {
        ecosystem: "rubygems",
        package_name: "em-imap",
        vulnerable_version_range: nil,
        first_patched_version: nil,
      },
    }
  end

  def multiple_expected_vulnerabilities
    {
      0 => {
        ecosystem: "rubygems",
        package_name: "restforce",
        vulnerable_version_range: nil,
        first_patched_version: "~> 2.5.4",
      },
      1 => {
        ecosystem: "rubygems",
        package_name: "restforce",
        vulnerable_version_range: nil,
        first_patched_version: ">= 3.0.0",
      },
    }
  end

  def expected_description
    [
      "A path traversal vulnerability was discovered in YARD <= 0.9.19 when using",
      "`yard server` to serve documentation. This bug would allow unsanitized HTTP",
      "requests to access arbitrary files on the machine of a yard server host under",
      "certain conditions.",
      "",
      "The issue is resolved in v0.9.20 and later.",
      "",
    ].join("\n")
  end

  test "identifier is based on filename" do
    assert_equal "rubysec/gems/yard/CVE-2019-1020001.yml", @ruby_advisory_a.identifier
  end

  test "vulnerabilities list" do
    assert_equal expected_vulnerabilities, @ruby_advisory_a.vulnerabilities
  end

  test "generates a full import object, ready for application importer" do
    assert_equal expected_importer_object, @ruby_advisory_a.importer_object
  end

  test "parse advisory with multiple patched versions for a given vulnerability" do
    assert_equal multiple_expected_vulnerabilities, @ruby_advisory_b.vulnerabilities
  end

  test "parse advisory with no patched versions for a given vulnerability" do
    assert_equal expected_vulnerability_with_no_patch_version, @ruby_advisory_c.vulnerabilities
  end

  test "parse advisory with multiple cvss scores including cvss_v4" do
    expected_cvss_scores = { "cvss_v2" => 5.0, "cvss_v3" => 4.3, "cvss_v4" => 6.9 }
    assert_equal expected_cvss_scores, @ruby_advisory_d.importer_object[:raw_payload]&.slice("cvss_v2", "cvss_v3", "cvss_v4")
  end
end
