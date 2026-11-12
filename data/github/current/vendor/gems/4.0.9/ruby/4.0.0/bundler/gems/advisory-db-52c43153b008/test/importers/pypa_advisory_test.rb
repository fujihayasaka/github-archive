# frozen_string_literal: true

require "test_helper"

class PypaAdvisoryTest < ActiveSupport::TestCase
  test "finds CVE ID in aliases" do
    raw_payload = generate_raw_payload
    pypa_advisory = PypaAdvisory.new(raw_payload:, path: "vulns/django/PYSEC-2021-9.yaml")
    assert_equal "CVE-2021-3281", pypa_advisory.cve_id
  end

  test "returns nil CVE ID if aliases is not present" do
    raw_payload = generate_raw_payload.except("aliases")
    pypa_advisory = PypaAdvisory.new(raw_payload:, path: "vulns/django/PYSEC-2021-9.yaml")
    assert_nil pypa_advisory.cve_id
  end

  test "finds GHSA ID in aliases" do
    raw_payload = generate_raw_payload
    pypa_advisory = PypaAdvisory.new(raw_payload:, path: "vulns/django/PYSEC-2021-9.yaml")
    assert_equal "GHSA-fvgf-6h6h-3322", pypa_advisory.ghsa_id
  end

  test "returns nil GHSA ID if aliases is not present" do
    raw_payload = generate_raw_payload.except("aliases")
    pypa_advisory = PypaAdvisory.new(raw_payload:, path: "vulns/django/PYSEC-2021-9.yaml")
    assert_nil pypa_advisory.ghsa_id
  end

  test "returns base reference if references are not present" do
    raw_payload = generate_raw_payload.except("references")
    path = "vulns/django/PYSEC-2021-9.yaml"
    pypa_advisory = PypaAdvisory.new(raw_payload:, path:)
    assert_equal 1, pypa_advisory.references.count
    assert_equal PypaAdvisory::FILE_BASE_PATH + path, pypa_advisory.references.first
  end

  test "gracefully handles vulnerabilities with no ranges" do
    raw_payload = generate_raw_payload
    raw_payload["affected"][0].delete("ranges")

    assert_nil raw_payload.dig("affected", 0, "ranges")
    assert_empty PypaAdvisory.new(raw_payload:, path: "vulns/django/PYSEC-2021-9.yaml").vulnerabilities
  end

  def generate_raw_payload
    YAML.load(<<~RAW_PAYLOAD)
      id: PYSEC-2021-9
      details: In Django 2.2 before 2.2.18, 3.0 before 3.0.12, and 3.1 before 3.1.6, the
        django.utils.archive.extract method (used by "startapp --template" and "startproject
        --template") allows directory traversal via an archive with absolute paths or relative
        paths with dot segments.
      affected:
      - package:
          name: django
          ecosystem: PyPI
          purl: pkg:pypi/django
        ranges:
        - type: ECOSYSTEM
          events:
          - introduced: '2.2'
          - fixed: 2.2.18
          - introduced: '3.0'
          - fixed: 3.0.12
          - introduced: '3.1'
          - fixed: 3.1.6
        versions:
        - '2.2'
        - 2.2.1
        - 2.2.2
        - 2.2.3
        - 2.2.4
        - 2.2.5
        - 2.2.6
        - 2.2.7
        - 2.2.8
        - 2.2.9
        - 2.2.10
        - 2.2.11
        - 2.2.12
        - 2.2.13
        - 2.2.14
        - 2.2.15
        - 2.2.16
        - 2.2.17
        - '3.0'
        - 3.0.1
        - 3.0.2
        - 3.0.3
        - 3.0.4
        - 3.0.5
        - 3.0.6
        - 3.0.7
        - 3.0.8
        - 3.0.9
        - 3.0.10
        - 3.0.11
        - '3.1'
        - 3.1.1
        - 3.1.2
        - 3.1.3
        - 3.1.4
        - 3.1.5
      references:
      - type: WEB
        url: https://docs.djangoproject.com/en/3.1/releases/security/
      - type: ARTICLE
        url: https://www.djangoproject.com/weblog/2021/feb/01/security-releases/
      - type: WEB
        url: https://groups.google.com/forum/#!forum/django-announce
      - type: WEB
        url: https://lists.fedoraproject.org/archives/list/package-announce@lists.fedoraproject.org/message/YF52FKEH5S2P5CM4X7IXSYG67YY2CDOO/
      - type: ADVISORY
        url: https://security.netapp.com/advisory/ntap-20210226-0004/
      - type: ADVISORY
        url: https://github.com/advisories/GHSA-fvgf-6h6h-3322
      aliases:
      - CVE-2021-3281
      - GHSA-fvgf-6h6h-3322
      modified: '2021-03-05T19:19:00Z'
      published: '2021-02-02T07:15:00Z'
    RAW_PAYLOAD
  end
end
