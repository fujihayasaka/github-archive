# frozen_string_literal: true

require "test_helper"

class NVDImporterTest < ActiveSupport::TestCase
  CVE_ID_PATTERN = AdvisoryDBToolkit::CVEIDValidator::CONTAINING_STRING_PATTERN

  def verify_cve_attributes(attributes)
    assert_kind_of Hash, attributes

    identifier = attributes.fetch(:identifier)
    assert_kind_of String, identifier
    assert_match %r{\Anvd/#{CVE_ID_PATTERN}\z}o, identifier

    cve_id = attributes.fetch(:cve_id)
    assert_kind_of String, cve_id
    assert_match(/\A#{CVE_ID_PATTERN}\z/o, cve_id)

    raw_payload = attributes.fetch(:raw_payload)
    assert_kind_of Hash, raw_payload
    assert_predicate raw_payload, :present?

    advisory_payload = attributes.fetch(:advisory_payload)
    assert_kind_of Hash, advisory_payload
    assert_predicate advisory_payload, :present?

    summary = advisory_payload.fetch(:summary)
    assert_nil summary

    description = advisory_payload.fetch(:description)
    assert_kind_of String, description
    assert_predicate description, :present?

    severity = advisory_payload.fetch(:severity)
    if severity
      assert_kind_of String, severity
      assert_includes AdvisoryDB.severities, severity
    else
      assert_nil severity
    end

    references = advisory_payload.fetch(:references)
    assert_kind_of Array, references
    references.each do |reference|
      assert_kind_of String, reference
      assert_match %r{\Ahttps?://}i, reference
    end
    # We set the first reference to the canonical CVE URL.
    assert_match %r{\Ahttps://nvd.nist.gov/vuln/detail/CVE-\d+-\d+\z},
      references.first

    vulnerabilities = advisory_payload.fetch(:vulnerabilities)
    assert_kind_of Hash, vulnerabilities
    refute_predicate vulnerabilities, :present?

    withdrawn = advisory_payload.fetch(:withdrawn)
    assert_equal false, withdrawn

    [identifier, cve_id]
  end

  test "knows its source" do
    assert_equal "nvd", NVDImporter.source
    assert_equal "nvd", NVDImporter.new.source
  end

  test "does not allow invalid CVE IDs" do
    assert_raises ArgumentError do
      NVDImporter.new(cve_id: "ABC-123")
    end
  end

  test "imports a specific CVE" do
    cve_id = "CVE-2019-0001"
    importer = NVDImporter.new(cve_id: cve_id)
    VCR.use_cassette("nvd_CVE-2019-0001") do
      importer.each do |attributes|
        verify_cve_attributes(attributes)
      end
    end

    assert_equal 1, importer.count
  end

  test "raises error for non-existent cve" do
    cve_id = "CVE-2019-9999999999"
    importer = NVDImporter.new(cve_id: cve_id)
    VCR.use_cassette("nvd_CVE-2019-9999999999") do
      assert_raises NVDImporter::NVDImporterError do
        importer.import
      end
    end
  end

  test "iterates over all CVE feed entry attributes" do
    create(:import, source: "nvd", started_at: "2023-03-27", finished_at: "2023-03-27", bulk: true)
    Timecop.freeze(2023, 3, 28) do
      identifiers = []
      cve_ids = []
      importer = NVDImporter.new

      VCR.use_cassette("nvd_modified") do
        importer.each do |attributes|
          identifier, cve_id = verify_cve_attributes(attributes)
          identifiers << identifier
          cve_ids << cve_id
        end

        # This count seems arbitrary, but the NVD modified api response contained 339 entries when recorded by VCR.
        assert_equal 339, importer.count

        # Make sure the entire set of identifiers and CVE IDs are unique.
        assert_equal identifiers, identifiers.uniq
        assert_equal cve_ids, cve_ids.uniq
      end
    end
  end

  test "when results are paginated we get all the advisories" do
    create(:import, source: "nvd", started_at: "2023-03-10", finished_at: "2023-03-10", bulk: true)

    Timecop.freeze(2023, 3, 29) do
      identifiers = []
      cve_ids = []
      importer = NVDImporter.new

      VCR.use_cassette("nvd_paginated") do
        importer.each do |attributes|
          identifier, cve_id = verify_cve_attributes(attributes)
          identifiers << identifier
          cve_ids << cve_id
        end

        # The NVD modified api response contained 18 entries when recorded by VCR.
        assert_equal 2591, importer.count

        # Make sure the entire set of identifiers and CVE IDs are unique.
        assert_equal identifiers, identifiers.uniq
        assert_equal cve_ids, cve_ids.uniq
      end
    end
  end

  test "raises NVDUnavailableError when a 503 response is received" do
    cve_id = "CVE-2019-0001"
    importer = NVDImporter.new(cve_id: cve_id)
    VCR.use_cassette("nvd_CVE-2019-0001-unavailable") do
      assert_raises NVDImporter::NVDUnavailableError do
        importer.import
      end
    end
  end
end
