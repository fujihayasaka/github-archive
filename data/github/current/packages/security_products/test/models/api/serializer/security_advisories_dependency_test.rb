# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class SecurityAdvisorySerializerTest < Api::SerializerTestCase
  context "#security_advisory_hash" do
    test "includes minimal required information" do
      record = create(:security_advisory)
      output = security_advisory(record)

    end

    test "returns nil when given nil" do
      record = nil

      output = security_advisory(record)

      assert_nil output
    end

    test "handles vulnerability records gracefully" do
      vulnerability = create(:published_vulnerability)
      advisory = vulnerability.becomes(SecurityAdvisory)
      advisory_output = security_advisory(advisory)

      vulnerability_output = assert_nothing_raised do
        security_advisory(vulnerability)
      end

      assert_equal advisory_output, vulnerability_output
    end

    test "returns nil when given an undisclosed advisory" do
      record = create(:vulnerability, :preview)

      output = security_advisory(record)

      assert_nil output
    end

    test "includes a CVE identifier when available" do
      record = create(:published_vulnerability, cve_id: "CVE-2018-1234")

      output = security_advisory(record)

      identifiers = output["identifiers"]
      assert_kind_of Array, identifiers
      assert_equal 2, identifiers.count
      assert_kind_of Hash, identifiers[0]
      assert_equal "GHSA", identifiers[0]["type"]
      assert_kind_of String, identifiers[0]["value"]
      assert_kind_of Hash, identifiers[1]
      assert_equal "CVE", identifiers[1]["type"]
      assert_equal "CVE-2018-1234", identifiers[1]["value"]
    end

    test "includes CVSS vector string when available" do
      record = create(:security_advisory, cvss_v3: "CVSS:3.1/AV:P/AC:L/PR:N/UI:N/S:C/C:H/I:H/A:H")
      output = security_advisory(record)

      assert_equal "CVSS:3.1/AV:P/AC:L/PR:N/UI:N/S:C/C:H/I:H/A:H", output["cvss"]["vector_string"]
      assert_equal 7.7, output["cvss"]["score"]
    end

    test "cvss_severities includes CVSS v3 when available" do
      record = create(:security_advisory, cvss_v3: "CVSS:3.1/AV:P/AC:L/PR:N/UI:N/S:C/C:H/I:H/A:H")
      output = security_advisory(record)

      assert_equal "CVSS:3.1/AV:P/AC:L/PR:N/UI:N/S:C/C:H/I:H/A:H", output["cvss_severities"]["cvss_v3"]["vector_string"]
      assert_equal 7.7, output["cvss_severities"]["cvss_v3"]["score"]
    end

    test "cvss_severities includes CVSS v4 when available" do
      record = create(:security_advisory, cvss_v4: "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:N/VA:N/SC:N/SI:N/SA:N")
      output = security_advisory(record)

      assert_equal "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:N/VA:N/SC:N/SI:N/SA:N", output["cvss_severities"]["cvss_v4"]["vector_string"]
      assert_equal 8.7, output["cvss_severities"]["cvss_v4"]["score"]
    end

    test "includes CWEs when available" do
      cwe1 = create(:cwe)
      cwe2 = create(:cwe)
      record = create(:security_advisory, cwes: [cwe1, cwe2])
      output = security_advisory(record)

      assert_equal 2, output["cwes"].size
      assert_equal CWE.all.map(&:cwe_id).sort.first, output["cwes"].map { |cwe| cwe["cwe_id"] }.sort.first
      assert_equal CWE.all.map(&:name).sort.first, output["cwes"].map { |cwe| cwe["name"] }.sort.first
    end

    test "handles advisories with moderate `severity`" do
      record = create(:security_advisory, severity: "moderate")
      output1 = security_advisory(record, use_medium_severity: true)
      output2 = security_advisory(record, use_medium_severity: false)

      assert_equal "medium", output1["severity"]
      assert_equal "moderate", output2["severity"]
    end
  end

  context "#security_vulnerability_hash" do
    test "returns nil when given nil" do
      record = nil

      output = security_vulnerability(record)

      assert_nil output
    end

    test "returns nil when given an advisory is unreviewed" do
      record = create(:vulnerability, :unreviewed)

      output = security_advisory(record)

      assert_nil output
    end

    test "handles vulnerable version range records gracefully" do
      range = create(:vulnerable_version_range)
      vulnerability = range.becomes(SecurityVulnerability)
      vulnerability_output = security_vulnerability(vulnerability)

      range_output = assert_nothing_raised do
        security_vulnerability(range)
      end

      assert_equal vulnerability_output, range_output
    end

    test "drops first patched version when given an unpatched vulnerability" do
      record = create(:security_vulnerability, :unpatched)

      output = security_vulnerability(record)

      assert_includes output.keys, "first_patched_version"
      assert_nil output["first_patched_version"]
    end
  end
end
