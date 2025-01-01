# frozen_string_literal: true

require "test_helper"
require "advisory_db_toolkit"

# A simple extended translation smoke test to cover anything that the adapter
# specifically needs to do to create the expected shape to interact with the
# AdvisoryDBToolkit's OSV translator.
module AdvisoryDB
  class OSVOSVToGHSATest < ActiveSupport::TestCase
    setup do
      @subject = AdvisoryDB::OSV
    end

    test "rehydrates vulnerabilities using interface methods" do
      advisory = create(:advisory, vulnerability_count: 0)
      osv_data = @subject.ghsa_to_osv(advisory)
      ghsa = @subject.osv_to_ghsa(osv_data)
      assert_empty ghsa[:vulnerabilities]

      create(:vulnerability,
        advisory: advisory,
        package_ecosystem: "maven",
        package_name: "com.google.protobuf:protobuf-kotlin",
        first_patched_version: "3.19.2",
        vulnerable_version_range: ">= 3.19.0, < 3.19.2")
      create(:vulnerability,
        advisory: advisory,
        package_ecosystem: "maven",
        package_name: "com.google.protobuf:protobuf-kotlin",
        first_patched_version: "3.18.2",
        vulnerable_version_range: ">= 3.18.0, < 3.18.2")
      create(:vulnerability,
        advisory: advisory,
        package_ecosystem: "maven",
        package_name: "com.google.protobuf:protobuf-java",
        first_patched_version: "3.19.2",
        vulnerable_version_range: ">= 3.19.0, < 3.19.2")
      create(:vulnerability,
        advisory: advisory,
        package_ecosystem: "maven",
        package_name: "com.google.protobuf:protobuf-java",
        first_patched_version: "3.18.2",
        vulnerable_version_range: ">= 3.18.0, < 3.18.2")
      create(:vulnerability,
        advisory: advisory,
        package_ecosystem: "maven",
        package_name: "com.google.protobuf:protobuf-java",
        first_patched_version: "3.16.1",
        vulnerable_version_range: "< 3.16.1")
      create(:vulnerability,
        advisory: advisory,
        package_ecosystem: "rubygems",
        package_name: "google-protobuf",
        first_patched_version: "3.19.2",
        vulnerable_version_range: "< 3.19.2")
      osv_data = @subject.ghsa_to_osv(advisory.reload)
      ghsa = @subject.osv_to_ghsa(osv_data)
      assert_equal [{
        package_ecosystem: "maven",
        package_name: "com.google.protobuf:protobuf-kotlin",
        first_patched_version: "3.19.2",
        vulnerable_version_range: ">= 3.19.0, < 3.19.2",
      }, {
        package_ecosystem: "maven",
        package_name: "com.google.protobuf:protobuf-kotlin",
        first_patched_version: "3.18.2",
        vulnerable_version_range: ">= 3.18.0, < 3.18.2",
      }, {
        package_ecosystem: "maven",
        package_name: "com.google.protobuf:protobuf-java",
        first_patched_version: "3.19.2",
        vulnerable_version_range: ">= 3.19.0, < 3.19.2",
      }, {
        package_ecosystem: "maven",
        package_name: "com.google.protobuf:protobuf-java",
        first_patched_version: "3.18.2",
        vulnerable_version_range: ">= 3.18.0, < 3.18.2",
      }, {
        package_ecosystem: "maven",
        package_name: "com.google.protobuf:protobuf-java",
        first_patched_version: "3.16.1",
        vulnerable_version_range: "> 0, < 3.16.1",
      }, {
        package_ecosystem: "rubygems",
        package_name: "google-protobuf",
        first_patched_version: "3.19.2",
        vulnerable_version_range: "> 0, < 3.19.2",
      }], ghsa[:vulnerabilities]
    end

    test "missing vvr's on affected product fail to parse" do
      advisory = create(:advisory, vulnerability_count: 1)

      # Use a set package_ecosystem because other won't translate.
      vuln = advisory.vulnerabilities.first
      vuln.package_ecosystem = "maven"
      vuln.save

      osv_data = @subject.ghsa_to_osv(advisory)
      osv_data["affected"].first["ranges"] = []

      assert_raises AdvisoryDBToolkit::OSV::Transformers::SchemaV1::UnsupportedOSVNoVulnerableVersionRanges do
        @subject.osv_to_ghsa(osv_data)
      end
    end
  end
end
