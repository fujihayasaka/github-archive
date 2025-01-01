# frozen_string_literal: true

require "json"
require "test_helper"

class CVEItemTest < ActiveSupport::TestCase
  def setup
    @raw_cve_item = JSON.parse(file_fixture("nvd_modified_feed_sample.json").read).fetch("vulnerabilities").first["cve"]
    @cve_item = CVEItem.new(@raw_cve_item)
  end

  test "gets the correct NVD identifier" do
    assert_equal "nvd/CVE-2022-24096", @cve_item.identifier
  end

  test "gets the correct CVE ID" do
    assert_equal "CVE-2022-24096", @cve_item.cve_id
  end

  test "creates an advisory payload" do
    expected_advisory_payload = {
      summary: nil,
      description: "Adobe After Effects versions 22.2 (and earlier) and 18.4.4 (and earlier) are affected by an Heap-based Buffer Overflow vulnerability that could result in arbitrary code execution in the context of the current user. Exploitation of this issue requires user interaction in that a victim must open a malicious file.",
      severity: "high",
      references: ["https://nvd.nist.gov/vuln/detail/CVE-2022-24096", "https://helpx.adobe.com/security/products/after_effects/apsb22-17.html"],
      cwe_ids: ["CWE-787", "CWE-122"],
      cvss_v3: "CVSS:3.1/AV:L/AC:L/PR:N/UI:R/S:U/C:H/I:H/A:H",
      cvss_v4: nil,
      vulnerabilities: {},
      withdrawn: false,
    }
    assert_equal expected_advisory_payload, @cve_item.advisory_payload
  end

  test "creates an advisory payload with an empty cvss_v3 vector string if not found" do
    @raw_cve_item["metrics"]["cvssMetricV31"].first["cvssData"].delete("vectorString")

    expected_advisory_payload = {
      summary: nil,
      description: "Adobe After Effects versions 22.2 (and earlier) and 18.4.4 (and earlier) are affected by an Heap-based Buffer Overflow vulnerability that could result in arbitrary code execution in the context of the current user. Exploitation of this issue requires user interaction in that a victim must open a malicious file.",
      severity: "high",
      references: ["https://nvd.nist.gov/vuln/detail/CVE-2022-24096", "https://helpx.adobe.com/security/products/after_effects/apsb22-17.html"],
      cwe_ids: ["CWE-787", "CWE-122"],
      cvss_v3: nil,
      cvss_v4: nil,
      vulnerabilities: {},
      withdrawn: false,
    }
    assert_equal expected_advisory_payload, @cve_item.advisory_payload
  end

  test "creates an advisory payload with a cvss_v4 vector string" do
    raw_cve_item_with_cvss_v_4 = JSON.parse(file_fixture("nvd_v5_modified_feed_sample.json").read).fetch("vulnerabilities").first["cve"]
    cve_item_with_cvss_v_4 = CVEItem.new(raw_cve_item_with_cvss_v_4)

    expected_advisory_payload = {
      summary: nil,
      description: "Concrete CMS versions 9 through 9.3.2 and below 8.5.18 are vulnerable to Stored XSS in getAttributeSetName().  A rogue administrator could inject malicious code. The Concrete CMS team gave this a CVSS v3.1 rank of 2 with vector  AV:N/AC:H/PR:H/UI:R/S:U/C:L/I:N/A:N https://nvd.nist.gov/vuln-metrics/cvss/v3-calculator  and a CVSS v4.0 rank of 1.8 with vector  CVSS:4.0/AV:N/AC:H/AT:N/PR:H/UI:A/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N https://www.first.org/cvss/calculator/4.0#CVSS:4.0/AV:N/AC:H/AT:N/PR:H/UI:A/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N . Thanks, m3dium for reporting.",
      severity: "low",
      references: ["https://nvd.nist.gov/vuln/detail/CVE-2024-7394", "https://github.com/concretecms/concretecms/pull/12166", "https://github.com/concretecms/concretecms/commit/c08d9671cec4e7afdabb547339c4bc0bed8eab06", "https://documentation.concretecms.org/9-x/developers/introduction/version-history/933-release-notes?pk_vid=e367a434ef4830491723055753d52041", "https://documentation.concretecms.org/developers/introduction/version-history/8518-release-notes?pk_vid=e367a434ef4830491723055758d52041"],
      cwe_ids: ["CWE-79", "CWE-20"],
      cvss_v3: "CVSS:3.1/AV:N/AC:L/PR:H/UI:R/S:C/C:L/I:L/A:N",
      cvss_v4: "CVSS:4.0/AV:N/AC:H/AT:N/PR:H/UI:A/VC:L/VI:N/VA:N/SC:N/SI:N/SA:N/E:X/CR:X/IR:X/AR:X/MAV:X/MAC:X/MAT:X/MPR:X/MUI:X/MVC:X/MVI:X/MVA:X/MSC:X/MSI:X/MSA:X/S:X/AU:X/R:X/V:X/RE:X/U:X",
      vulnerabilities: {},
      withdrawn: false,
    }
    assert_equal expected_advisory_payload, cve_item_with_cvss_v_4.advisory_payload
  end

  test "creates an importer object" do
    expected_importer_object = {
      identifier: "nvd/CVE-2022-24096",
      cve_id: "CVE-2022-24096",
      raw_payload: @raw_cve_item,
      advisory_payload: @cve_item.advisory_payload,
    }

    assert_equal expected_importer_object, @cve_item.importer_object
  end
end
