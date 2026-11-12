# frozen_string_literal: true

require "test_helper"
require "advisory_db_toolkit"

# A simple extended translation smoke test to cover anything that the adapter
# specifically needs to do to create the expected shape to interact with the
# AdvisoryDBToolkit's OSV translator.
module AdvisoryDB
  class OSVGHSAToOSVTest < ActiveSupport::TestCase
    setup do
      @subject = AdvisoryDB::OSV
    end

    test "formats vulnerabilities as individual affected packages using interface methods" do
      advisory = create(:advisory, vulnerability_count: 0)
      osv = @subject.ghsa_to_osv(advisory)
      assert_empty osv["affected"]

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
      # Ignored because it's been withdrawn
      create(:vulnerability,
        advisory: advisory,
        package_ecosystem: "bad ecosystem, don't care",
        withdrawn_at: Time.current)
      osv = @subject.ghsa_to_osv(advisory.reload)
      assert_equal [
        {
          "package" => {
            "ecosystem" => "Maven",
            "name" => "com.google.protobuf:protobuf-kotlin",
          },
          "ranges" => [{
            "type" => "ECOSYSTEM",
            "events" => [{ "introduced" => "3.19.0" }, { "fixed" => "3.19.2" }],
          }],
        },
        {
          "package" => {
            "ecosystem" => "Maven",
            "name" => "com.google.protobuf:protobuf-kotlin",
          },
          "ranges" => [{
            "type" => "ECOSYSTEM",
            "events" => [{ "introduced" => "3.18.0" }, { "fixed" => "3.18.2" }],
          }],
        },
        {
          "package" => {
            "ecosystem" => "Maven",
            "name" => "com.google.protobuf:protobuf-java",
          },
          "ranges" => [{
            "type" => "ECOSYSTEM",
            "events" => [{ "introduced" => "3.19.0" }, { "fixed" => "3.19.2" }],
          }],
        },
        {
          "package" => {
            "ecosystem" => "Maven",
            "name" => "com.google.protobuf:protobuf-java",
          },
          "ranges" => [{
            "type" => "ECOSYSTEM",
            "events" => [{ "introduced" => "3.18.0" }, { "fixed" => "3.18.2" }],
          }],
        },
        {
          "package" => {
            "ecosystem" => "Maven",
            "name" => "com.google.protobuf:protobuf-java",
          },
          "ranges" => [{
            "type" => "ECOSYSTEM",
            "events" => [{ "introduced" => "0" }, { "fixed" => "3.16.1" }],
          }],
        },
        {
          "package" => {
            "ecosystem" => "RubyGems",
            "name" => "google-protobuf",
          },
          "ranges" => [{
            "type" => "ECOSYSTEM",
            "events" => [{ "introduced" => "0" }, { "fixed" => "3.19.2" }],
          }],
        },
      ], osv["affected"]
    end
  end
end
