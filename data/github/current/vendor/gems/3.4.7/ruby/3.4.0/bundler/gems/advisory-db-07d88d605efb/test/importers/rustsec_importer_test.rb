# frozen_string_literal: true

require "test_helper"

class RustsecImporterTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "knows its source" do
    assert_equal "rustsec", RustsecImporter.source
    assert_equal "rustsec", RustsecImporter.new.source
  end

  test "can import, by path, a single, specific advisory" do
    advisory_path = "crates/nanorand/RUSTSEC-2020-0089.md"
    importer = RustsecImporter.new(specific_advisory_path: advisory_path)

    import_items = []
    VCR.use_cassette("rustsec_RUSTSEC-2020-0089.yml") do
      importer.each do |import_item|
        import_items << import_item
      end
    end
    assert_equal 1, import_items.length
    import_item = import_items.first
    assert_equal "rustsec/crates/nanorand/RUSTSEC-2020-0089.md", import_item[:identifier]
  end

  test "can do a bulk import of updated advisories" do
    create(:import, source: "rustsec", started_at: "2022-03-22", finished_at: "2022-03-22", bulk: true)

    VCR.use_cassette("rustsec_updated_files") do
      assert RustsecImporter.new.count > 1
    end
  end

  test "does not generate an import object if the type is unmaintained" do
    advisory_path = "crates/nanorand/RUSTSEC-2022-0099.md"
    importer = RustsecImporter.new(specific_advisory_path: advisory_path)
    import_items = []

    VCR.use_cassette("rustsec_RUSTSEC-2022-0099.yml") do
      importer.each do |import_item|
        import_items << import_item
      end
    end

    assert_equal 0, import_items.length
  end
end

class RustsecAdvisoryTest < ActiveSupport::TestCase
  setup do
    @rust_advisory_a = nil
    VCR.use_cassette("rustsec_RUSTSEC-2020-0105.yml") do
      @rust_advisory_a = RustsecAdvisory.initialize_from_path("crates/abi_stable/RUSTSEC-2020-0105.md")
    end
  end

  def expected_importer_objects
    [
      {
        identifier: "rustsec/crates/abi_stable/RUSTSEC-2020-0105.md/CVE-2020-36212",
        cve_id: "CVE-2020-36212",
        ghsa_id: nil,
        rustsec_id: "crates/abi_stable/RUSTSEC-2020-0105.md/CVE-2020-36212",
        raw_payload: expected_raw_payload,
        advisory_payload: expected_advisory_payload,
      },
      {
        identifier: "rustsec/crates/abi_stable/RUSTSEC-2020-0105.md/CVE-2020-36213",
        cve_id: "CVE-2020-36213",
        ghsa_id: nil,
        rustsec_id: "crates/abi_stable/RUSTSEC-2020-0105.md/CVE-2020-36213",
        raw_payload: expected_raw_payload,
        advisory_payload: expected_advisory_payload,
      },
      {
        identifier: "rustsec/crates/abi_stable/RUSTSEC-2020-0105.md/GHSA-vq23-5h4f-vwpv",
        cve_id: nil,
        ghsa_id: "GHSA-vq23-5h4f-vwpv",
        rustsec_id: "crates/abi_stable/RUSTSEC-2020-0105.md/GHSA-vq23-5h4f-vwpv",
        raw_payload: expected_raw_payload,
        advisory_payload: expected_advisory_payload,
      },
      {
        identifier: "rustsec/crates/abi_stable/RUSTSEC-2020-0105.md/GHSA-wqxc-qrq4-w5v4",
        cve_id: nil,
        ghsa_id: "GHSA-wqxc-qrq4-w5v4",
        rustsec_id: "crates/abi_stable/RUSTSEC-2020-0105.md/GHSA-wqxc-qrq4-w5v4",
        raw_payload: expected_raw_payload,
        advisory_payload: expected_advisory_payload,
      },
    ]
  end

  def expected_raw_payload
    {
      "advisory" =>
        {
          id: "RUSTSEC-2020-0105",
          package: "abi_stable",
          aliases: ["CVE-2020-36212", "CVE-2020-36213", "GHSA-vq23-5h4f-vwpv", "GHSA-wqxc-qrq4-w5v4"],
          cvss: "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:H",
          date: "2020-12-21",
          url: "https://github.com/rodrimati1992/abi_stable_crates/issues/44",
          categories: ["memory-corruption"],
        }.stringify_keys,
      "versions" => { "patched" => [">= 0.9.1"] },
      "summary" => "Update unsound DrainFilter and RString::retain",
      "description" => expected_description,
    }
  end

  def expected_advisory_payload
    {
      summary: "Update unsound DrainFilter and RString::retain",
      description: expected_description,
      severity: "high",
      cvss_v3: "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:H",
      cvss_v4: nil,
      references: [
        "https://github.com/rodrimati1992/abi_stable_crates/issues/44",
        "https://rustsec.org/advisories/RUSTSEC-2020-0105.html",
      ],
      vulnerabilities: expected_vulnerabilities,
      withdrawn: false,
    }
  end

  def expected_vulnerabilities
    {
      0 => {
        ecosystem: "rust",
        package_name: "abi_stable",
        vulnerable_version_range: nil,
        first_patched_version: ">= 0.9.1",
      },
    }
  end

  def expected_description
    <<~DESC
      Affected versions of this crate contained code from the Rust standard library that contained soundness bugs rust-lang/rust#60977 (double drop) & rust-lang/rust#78498 (create invalid utf-8 string).

      The flaw was corrected in v0.9.1 by making a similar fix to the one made in the Rust standard library.
    DESC
  end

  test "vulnerabilities list" do
    assert_equal expected_vulnerabilities, @rust_advisory_a.vulnerabilities
  end

  test "generates a full import object, ready for application importer" do
    assert_equal expected_importer_objects, @rust_advisory_a.importer_objects
  end

  # Do not attempt to re-record the cassette used in this test!
  #
  # The data for this test was copied from `test/cassettes/rustsec_RUSTSEC-2020-0105_yml.yml` and then modified to
  # manually include the CVSS 4.0 data manually.  The content in the original file is a from a real advisory. However,
  # the CVSS 4 data that was added is not part of the real advisory. Re-recording this cassette will not result in the
  # expected data.
  test "creates an advisory payload with a cvss_v4 vector string" do
    @rust_advisory_with_cvss_v_4 = nil
    VCR.use_cassette("rustsec_RUSTSEC-2020-0105_with_cvss_v4.yml") do
      @rust_advisory_with_cvss_v_4 = RustsecAdvisory.initialize_from_path("crates/abi_stable/RUSTSEC-2020-0105.md")
    end

    expected_advisory_payload_with_cvss_v_4 = {
      summary: "Update unsound DrainFilter and RString::retain",
      description: expected_description,
      severity: "high",
      cvss_v3: nil,
      cvss_v4: "CVSS:4.0/AV:L/AC:L/AT:P/PR:N/UI:A/VC:L/VI:H/VA:L/SC:L/SI:H/SA:L",
      references: [
        "https://github.com/rodrimati1992/abi_stable_crates/issues/44",
        "https://rustsec.org/advisories/RUSTSEC-2020-0105.html",
      ],
      vulnerabilities: expected_vulnerabilities,
      withdrawn: false,
    }

    assert_equal expected_advisory_payload_with_cvss_v_4, @rust_advisory_with_cvss_v_4.advisory_payload
  end

  test "generates one feed entry with no CVE or GHSA if no aliases exist in the advisory" do
    assert_difference -> { FeedEntry.count }, 1 do
      VCR.use_cassette("rustsec_no_aliases") do
        RustsecImporter.import(specific_advisory_path: "crates/abox/RUSTSEC-2020-0121.md")
      end
    end

    feed_entry = FeedEntry.order(:id).last
    assert_equal "rustsec/crates/abox/RUSTSEC-2020-0121.md", feed_entry.identifier
    assert_nil feed_entry.cve_id
    assert_nil feed_entry.ghsa_id
  end

  test "generates one feed entry with no CVE or GHSA if only unknown aliases exist in the advisory" do
    assert_difference -> { FeedEntry.count }, 1 do
      VCR.use_cassette("rustsec_dynamic_aliases", erb: { aliases: ["ABC-2020-35926", "ABC-2020-35927"] }) do
        RustsecImporter.import(specific_advisory_path: "crates/abox/RUSTSEC-2020-0121.md")
      end
    end

    feed_entry = FeedEntry.order(:id).last
    assert_equal "rustsec/crates/abox/RUSTSEC-2020-0121.md", feed_entry.identifier
    assert_nil feed_entry.cve_id
    assert_nil feed_entry.ghsa_id
  end

  test "generates one feed entry with a CVE ID and no GHSA if aliases contains only one CVE" do
    assert_difference -> { FeedEntry.count }, 1 do
      VCR.use_cassette("rustsec_dynamic_aliases", erb: { aliases: ["CVE-2020-35926"] }) do
        RustsecImporter.import(specific_advisory_path: "crates/abox/RUSTSEC-2020-0121.md")
      end
    end

    feed_entry = FeedEntry.order(:id).last
    assert_equal "rustsec/crates/abox/RUSTSEC-2020-0121.md", feed_entry.identifier
    assert_equal "CVE-2020-35926", feed_entry.cve_id
    assert_nil feed_entry.ghsa_id
  end

  test "generates multiple feed entries, one per CVE ID, and no GHSA if aliases contains multiple CVEs" do
    assert_difference -> { FeedEntry.count }, 2 do
      VCR.use_cassette("rustsec_dynamic_aliases", erb: { aliases: ["CVE-2020-35926", "CVE-2020-35927"] }) do
        RustsecImporter.import(specific_advisory_path: "crates/abox/RUSTSEC-2020-0121.md")
      end
    end

    feed_entry_1, feed_entry_2 = FeedEntry.order(:id).last(2)
    assert_equal "rustsec/crates/abox/RUSTSEC-2020-0121.md/CVE-2020-35926", feed_entry_1.identifier
    assert_equal "rustsec/crates/abox/RUSTSEC-2020-0121.md/CVE-2020-35927", feed_entry_2.identifier
    assert_equal "CVE-2020-35926", feed_entry_1.cve_id
    assert_equal "CVE-2020-35927", feed_entry_2.cve_id
    assert_nil feed_entry_1.ghsa_id
    assert_nil feed_entry_2.ghsa_id
  end

  test "generates one feed entry with a GHSA ID and no CVE if aliases contains only one GHSA" do
    assert_difference -> { FeedEntry.count }, 1 do
      VCR.use_cassette("rustsec_dynamic_aliases", erb: { aliases: ["GHSA-v5m7-53cv-f3hx"] }) do
        RustsecImporter.import(specific_advisory_path: "crates/abox/RUSTSEC-2020-0121.md")
      end
    end

    feed_entry = FeedEntry.order(:id).last
    assert_equal "rustsec/crates/abox/RUSTSEC-2020-0121.md", feed_entry.identifier
    assert_equal "GHSA-v5m7-53cv-f3hx", feed_entry.ghsa_id
    assert_nil feed_entry.cve_id
  end

  test "generates multiple feed entries, one per GHSA ID, and no CVE if aliases contains multiple GHSAs" do
    assert_difference -> { FeedEntry.count }, 2 do
      VCR.use_cassette("rustsec_dynamic_aliases", erb: { aliases: ["GHSA-v5m7-53cv-f3hx", "GHSA-v5m7-53cv-f3hw"] }) do
        RustsecImporter.import(specific_advisory_path: "crates/abox/RUSTSEC-2020-0121.md")
      end
    end

    feed_entry_1, feed_entry_2 = FeedEntry.order(:id).last(2)
    assert_equal "rustsec/crates/abox/RUSTSEC-2020-0121.md/GHSA-v5m7-53cv-f3hx", feed_entry_1.identifier
    assert_equal "rustsec/crates/abox/RUSTSEC-2020-0121.md/GHSA-v5m7-53cv-f3hw", feed_entry_2.identifier
    assert_equal "GHSA-v5m7-53cv-f3hx", feed_entry_1.ghsa_id
    assert_equal "GHSA-v5m7-53cv-f3hw", feed_entry_2.ghsa_id
    assert_nil feed_entry_1.cve_id
    assert_nil feed_entry_2.cve_id
  end

  test "generates one feed entry with CVE ID and GHSA ID when aliases contains one of each" do
    assert_difference -> { FeedEntry.count }, 1 do
      VCR.use_cassette("rustsec_dynamic_aliases", erb: { aliases: ["CVE-2020-35926", "GHSA-v5m7-53cv-f3hw"] }) do
        RustsecImporter.import(specific_advisory_path: "crates/abox/RUSTSEC-2020-0121.md")
      end
    end

    feed_entry = FeedEntry.order(:id).last
    assert_equal "rustsec/crates/abox/RUSTSEC-2020-0121.md", feed_entry.identifier
    assert_equal "CVE-2020-35926", feed_entry.cve_id
    assert_equal "GHSA-v5m7-53cv-f3hw", feed_entry.ghsa_id
  end

  test "generates multiple feed entries, one per unique alias if aliases contains multiple CVEs and one GHSA" do
    assert_difference -> { FeedEntry.count }, 3 do
      VCR.use_cassette("rustsec_dynamic_aliases", erb: { aliases: ["CVE-2020-35926", "CVE-2020-35927", "GHSA-v5m7-53cv-f3hw"] }) do
        RustsecImporter.import(specific_advisory_path: "crates/abox/RUSTSEC-2020-0121.md")
      end
    end

    feed_entry_1, feed_entry_2, feed_entry_3 = FeedEntry.order(:id).last(3)
    assert_equal "rustsec/crates/abox/RUSTSEC-2020-0121.md/CVE-2020-35926", feed_entry_1.identifier
    assert_equal "rustsec/crates/abox/RUSTSEC-2020-0121.md/CVE-2020-35927", feed_entry_2.identifier
    assert_equal "rustsec/crates/abox/RUSTSEC-2020-0121.md/GHSA-v5m7-53cv-f3hw", feed_entry_3.identifier
    assert_equal "CVE-2020-35926", feed_entry_1.cve_id
    assert_equal "CVE-2020-35927", feed_entry_2.cve_id
    assert_equal "GHSA-v5m7-53cv-f3hw", feed_entry_3.ghsa_id
    assert_nil feed_entry_1.ghsa_id
    assert_nil feed_entry_2.ghsa_id
    assert_nil feed_entry_3.cve_id
  end

  test "generates multiple feed entries, one per unique alias if aliases contains multiple GHSAs and one CVE" do
    assert_difference -> { FeedEntry.count }, 3 do
      VCR.use_cassette("rustsec_dynamic_aliases", erb: { aliases: ["CVE-2020-35926", "GHSA-v5m7-53cv-f3hx", "GHSA-v5m7-53cv-f3hw"] }) do
        RustsecImporter.import(specific_advisory_path: "crates/abox/RUSTSEC-2020-0121.md")
      end
    end

    feed_entry_1, feed_entry_2, feed_entry_3 = FeedEntry.order(:id).last(3)
    assert_equal "rustsec/crates/abox/RUSTSEC-2020-0121.md/CVE-2020-35926", feed_entry_1.identifier
    assert_equal "rustsec/crates/abox/RUSTSEC-2020-0121.md/GHSA-v5m7-53cv-f3hx", feed_entry_2.identifier
    assert_equal "rustsec/crates/abox/RUSTSEC-2020-0121.md/GHSA-v5m7-53cv-f3hw", feed_entry_3.identifier
    assert_equal "CVE-2020-35926", feed_entry_1.cve_id
    assert_equal "GHSA-v5m7-53cv-f3hx", feed_entry_2.ghsa_id
    assert_equal "GHSA-v5m7-53cv-f3hw", feed_entry_3.ghsa_id
    assert_nil feed_entry_1.ghsa_id
    assert_nil feed_entry_2.cve_id
    assert_nil feed_entry_3.cve_id
  end

  test "generates multiple feed entries, one per unique alias if aliases contains multiple CVEs and multiple GHSAs" do
    assert_difference -> { FeedEntry.count }, 4 do
      VCR.use_cassette("rustsec_dynamic_aliases", erb: { aliases: ["CVE-2020-35926", "CVE-2020-35927", "GHSA-v5m7-53cv-f3hx", "GHSA-v5m7-53cv-f3hw"] }) do
        RustsecImporter.import(specific_advisory_path: "crates/abox/RUSTSEC-2020-0121.md")
      end
    end

    feed_entry_1, feed_entry_2, feed_entry_3, feed_entry_4 = FeedEntry.order(:id).last(4)
    assert_equal "rustsec/crates/abox/RUSTSEC-2020-0121.md/CVE-2020-35926", feed_entry_1.identifier
    assert_equal "rustsec/crates/abox/RUSTSEC-2020-0121.md/CVE-2020-35927", feed_entry_2.identifier
    assert_equal "rustsec/crates/abox/RUSTSEC-2020-0121.md/GHSA-v5m7-53cv-f3hx", feed_entry_3.identifier
    assert_equal "rustsec/crates/abox/RUSTSEC-2020-0121.md/GHSA-v5m7-53cv-f3hw", feed_entry_4.identifier
    assert_equal "CVE-2020-35926", feed_entry_1.cve_id
    assert_equal "CVE-2020-35927", feed_entry_2.cve_id
    assert_equal "GHSA-v5m7-53cv-f3hx", feed_entry_3.ghsa_id
    assert_equal "GHSA-v5m7-53cv-f3hw", feed_entry_4.ghsa_id
    assert_nil feed_entry_1.ghsa_id
    assert_nil feed_entry_2.ghsa_id
    assert_nil feed_entry_3.cve_id
    assert_nil feed_entry_4.cve_id
  end

  test "raises an error if specific path is not a valid Rustsec ID" do
    assert_raise(RustsecAdvisory::RustsecAdvisoryError) do
      RustsecAdvisory.initialize_from_path("crate/abi_stable/GHSA-xfhh-rx56-rxcr.md")
    end
    assert_raise(RustsecAdvisory::RustsecAdvisoryError) do
      RustsecAdvisory.initialize_from_path("crates/pty/RUSTSEC-0000-0000.md")
    end
  end
end
