# frozen_string_literal: true

require "test_helper"

class PypaAdvisoryImporterTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  test "knows its source" do
    assert_equal "pypa_advisory", PypaAdvisoryImporter.source
    assert_equal "pypa_advisory", PypaAdvisoryImporter.new.source
  end

  test "can import just a single specific advisory, by path" do
    advisory_path = "vulns/wasmtime/PYSEC-2021-87.yaml"
    importer = PypaAdvisoryImporter.new(specific_advisory_path: advisory_path)

    import_items = []
    VCR.use_cassette("pypa_vuln_PYSEC-2021-87") do
      importer.each do |import_item|
        import_items << import_item
      end
    end
    assert_equal 1, import_items.length
    import_item = import_items.first
    assert_equal "pypa_advisory/vulns/wasmtime/PYSEC-2021-87.yaml", import_item[:identifier]
  end

  test "feed entry gets attached to existing advisory review with matching CVE ID if record has CVE ID" do
    advisory_review = create :advisory_review, :closed, cve_id: "CVE-2018-7750", feed_entry_type: :cve_feed_entry
    assert advisory_review.closed?

    VCR.use_cassette("pypa_CVE-2018-7750") do
      perform_enqueued_jobs(only: [ResolveFeedEntryJob, ImportJob]) do
        PypaAdvisoryImporter.new(specific_advisory_path: "vulns/paramiko/PYSEC-2018-19.yaml").import(report_to_slack: false)
      end
    end

    advisory_review.reload
    assert advisory_review.feed_entries.pluck(:identifier).include?("pypa_advisory/vulns/paramiko/PYSEC-2018-19.yaml")
    assert advisory_review.open?
  end

  test "feed entry gets attached to existing advisory review with matching GHSA ID if record has GHSA ID" do
    advisory_review = create :advisory_review, :closed, ghsa_id: "GHSA-g67g-hvc3-xmvf", feed_entry_type: :cve_feed_entry
    assert advisory_review.closed?

    VCR.use_cassette("pypa_GHSA-g67g-hvc3-xmvf") do
      perform_enqueued_jobs(only: [ResolveFeedEntryJob, ImportJob]) do
        PypaAdvisoryImporter.new(specific_advisory_path: "vulns/omero-web/PYSEC-2021-372.yaml").import(report_to_slack: false)
      end
    end

    advisory_review.reload
    assert advisory_review.feed_entries.pluck(:identifier).include?("pypa_advisory/vulns/omero-web/PYSEC-2021-372.yaml")
    assert advisory_review.open?
  end

  test "feed entries for two differing advisories get attached to the same CVE" do
    advisory_review = create :advisory_review, :closed, cve_id: "CVE-2021-32811", feed_entry_type: :cve_feed_entry
    assert advisory_review.closed?

    VCR.use_cassette("pypa_PYSEC-2021-368_and_PYSEC-2021-370") do
      perform_enqueued_jobs(only: [ResolveFeedEntryJob, ImportJob]) do
        PypaAdvisoryImporter.new(specific_advisory_path: "vulns/zope/PYSEC-2021-368.yaml").import(report_to_slack: false)
        PypaAdvisoryImporter.new(specific_advisory_path: "vulns/accesscontrol/PYSEC-2021-370.yaml").import(report_to_slack: false)
      end
    end

    advisory_review.reload
    assert advisory_review.feed_entries.pluck(:identifier).include?("pypa_advisory/vulns/zope/PYSEC-2021-368.yaml")
    assert advisory_review.feed_entries.pluck(:identifier).include?("pypa_advisory/vulns/accesscontrol/PYSEC-2021-370.yaml")
    assert_equal(
      [
        { "ecosystem" => "pip", "first_patched_version" => "4.6.3", "package_name" => "zope", "vulnerable_version_range" => ">= 4.0, < 4.6.3" },
        { "ecosystem" => "pip", "first_patched_version" => "5.3", "package_name" => "zope", "vulnerable_version_range" => ">= 5.0, < 5.3" },
      ],
      advisory_review.advisory_payload["vulnerabilities"].values.select { |vuln| vuln["package_name"] == "zope" },
    )
    assert_equal(
      [
        { "ecosystem" => "pip", "first_patched_version" => "4.3", "package_name" => "accesscontrol", "vulnerable_version_range" => ">= 4.0, < 4.3" },
        { "ecosystem" => "pip", "first_patched_version" => "5.2", "package_name" => "accesscontrol", "vulnerable_version_range" => ">= 5.0, < 5.2" },
      ],
      advisory_review.advisory_payload["vulnerabilities"].values.select { |vuln| vuln["package_name"] == "accesscontrol" },
    )
    assert advisory_review.open?
  end

  test "can do a bulk import of updated advisories" do
    create(:import, source: "pypa_advisory", started_at: "2022-03-16", finished_at: "2022-03-16", bulk: true)

    VCR.use_cassette("pypa_updated_files") do
      assert PypaAdvisoryImporter.new.count > 1
    end
  end
end

class PypaAdvisoryTest < ActiveSupport::TestCase
  setup do
    @pypa_advisory_a = VCR.use_cassette("pypa_vuln_PYSEC-2021-87") do
      PypaAdvisory.initialize_from_path("vulns/wasmtime/PYSEC-2021-87.yaml")
    end
    @pypa_nonfixed_advisory = VCR.use_cassette("pypa_vuln_PYSEC-2020-226") do
      PypaAdvisory.initialize_from_path("vulns/cabot/PYSEC-2020-226.yaml")
    end
    @pypa_advisory_b = VCR.use_cassette("pypa_vuln_PYSEC-2021-9") do
      PypaAdvisory.initialize_from_path("vulns/django/PYSEC-2021-9.yaml")
    end
    @pypa_advisory_with_ghsa = VCR.use_cassette("pypa_vuln_PYSEC-2021-372") do
      PypaAdvisory.initialize_from_path("vulns/omero-web/PYSEC-2021-372.yaml")
    end
  end

  test "ensure no advisory created on bad url" do
    VCR.use_cassette("pypa_invalid_files") do
      assert_raises do
        PypaAdvisory.initialize_from_path("vulns/wasmtime/PYSEC-2021-87-101-not-real.yoml")
      end
    end
  end

  test "ensure no advisory created on transient advisory" do
    VCR.use_cassette("pypa_invalid_files") do
      assert_raises do
        PypaAdvisory.initialize_from_path("vulns/asterix-decoder/PYSEC-0000-CVE-2021-44144.yaml")
      end
    end
  end

  test "ensure no advisory created on id allocator file" do
    VCR.use_cassette("pypa_invalid_files") do
      assert_raises do
        PypaAdvisory.initialize_from_path("vulns/.id-allocator")
      end
    end
  end

  test "identifier is based on path" do
    assert_equal \
      "pypa_advisory/vulns/wasmtime/PYSEC-2021-87.yaml",
      @pypa_advisory_a.identifier
  end

  test "CVE is clean" do
    assert_equal \
      "CVE-2021-32629",
      @pypa_advisory_a.cve_id
  end

  test "simple vulnerabilities test" do
    expected_vulnerabilities = {
      0 => {
        ecosystem: "pip",
        package_name: "wasmtime",
        vulnerable_version_range: ">= 0, < 0.27.0",
        first_patched_version: "0.27.0",
      },
    }
    assert_equal expected_vulnerabilities, @pypa_advisory_a.vulnerabilities
  end

  test "Ensure payload references pypa_advisory url" do
    expected_references = [
      "https://github.com/bytecodealliance/wasmtime/commit/95559c01aaa7c061088a433040f31e8291fb09d0",
      "https://github.com/bytecodealliance/wasmtime/security/advisories/GHSA-hpqh-2wqx-7qp5",
      "https://www.fastly.com/security-advisories/memory-access-due-to-code-generation-flaw-in-cranelift-module",
      "https://crates.io/crates/cranelift-codegen",
      "https://github.com/pypa/advisory-database/tree/main/vulns/wasmtime/PYSEC-2021-87.yaml",
    ]
    assert_equal expected_references.sort, @pypa_advisory_a.references.sort
  end

  test "Parse advisory with unfixed vulnerability" do
    expected_vulnerabilities = { 0 => {
      ecosystem: "pip",
      package_name: "cabot",
      vulnerable_version_range: ">= 0",
      first_patched_version: nil,
    } }
    assert_equal expected_vulnerabilities, @pypa_nonfixed_advisory.vulnerabilities
  end

  test "Get GHSA id and CVE id from pysec advisory" do
    assert_equal \
      "GHSA-g67g-hvc3-xmvf",
      @pypa_advisory_with_ghsa.ghsa_id

    assert_equal \
      "CVE-2021-41132",
      @pypa_advisory_with_ghsa.cve_id
  end

  test "Parse advisory with multiple fix ranges for a given vulnerability" do
    expected_vulnerabilities = {
      0 => {
        ecosystem: "pip",
        package_name: "django",
        vulnerable_version_range: ">= 2.2, < 2.2.18",
        first_patched_version: "2.2.18",
      },
      1 => {
        ecosystem: "pip",
        package_name: "django",
        vulnerable_version_range: ">= 3.0, < 3.0.12",
        first_patched_version: "3.0.12",
      },
      2 => {
        ecosystem: "pip",
        package_name: "django",
        vulnerable_version_range: ">= 3.1, < 3.1.6",
        first_patched_version: "3.1.6",
      },
    }
    assert_equal expected_vulnerabilities, @pypa_advisory_b.vulnerabilities
  end
end
