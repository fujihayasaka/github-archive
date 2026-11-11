# frozen_string_literal: true

require "test_helper"

class AdvisoryImprovementImporterTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "knows its source" do
    assert_equal "advisory_improvement", AdvisoryImprovementImporter.source
  end

  test "Makes a feed entry if one does not already exist" do
    improvement_data = create(:advisory_improvement_data)
    assert_difference -> { FeedEntry.count }, 1 do
      AdvisoryImprovementImporter.new(advisory_improvement_data: improvement_data).import
    end
    new_feed_entry = FeedEntry.last
    assert_equal "advisory_improvement", new_feed_entry.source
    assert_equal "advisory_improvement/#{improvement_data.actor_id}/#{improvement_data.ghsa_id}", new_feed_entry.identifier
  end
end

class AdvisoryImprovementDataTest < ActiveSupport::TestCase
  test "#importer_object" do
    ghsa_id = "GHSA-95qh-cr8q-7j8v"
    advisory = create(:advisory, ghsa_id: ghsa_id)
    improvement_data = create(:advisory_improvement_data, ghsa_id: ghsa_id)

    expected_importer_obj = {
      identifier: "advisory_improvement/1234/GHSA-95qh-cr8q-7j8v",
      ghsa_id: ghsa_id,
      cve_id: advisory.cve_id,
      raw_payload: {
        "ghsa_id" => "GHSA-95qh-cr8q-7j8v",
        "summary" => "This is a test advisory title",
        "description" => "This is a test advisory description",
        "source_code_location" => "",
        "severity" => "low",
        "cvss_v3" => "",
        "cvss_v4" => "",
        "cwe_ids" => [],
        "references" => [],
        "affected_products" => [],
        "actor_id" => 1234,
        "actor_login" => "testuser",
        "pr_number" => nil,
      },
      advisory_payload: {
        summary: "This is a test advisory title",
        description: "This is a test advisory description",
        source_code_location: "",
        severity: "low",
        cvss_v3: nil,
        cvss_v4: nil,
        references: [],
        cwe_ids: [],
        vulnerabilities: {},
        withdrawn: false,
      },
    }
    assert_equal(expected_importer_obj, improvement_data.importer_object)
  end

  # the form has two options for specifying a "severity".
  # - Option a) user can specify a basic severity (low/moderate/high/critical)
  # - Option b) user can specify a cvss vector string.  Generally we would expect the basic severity to be blank when this happens
  # When cvss is used, the severity should be set in accordance with the calculated severity
  # this test makes sure that is happening, by sending both severity and cvss_v3 (which is practice should never happen)
  test "when cvss_v3 is specified, then severity is set based on the cvss_v3, even if severity is specified and disagrees with cvss" do
    # The given cvss string evaluates to "moderate" severity.  The given severity of critical should be ignored
    cvss_vector = "CVSS:3.0/AV:N/AC:L/PR:L/UI:N/S:U/C:L/I:N/A:N"
    improvement_data = create(:advisory_improvement_data, severity: "critical", cvss_v3: cvss_vector)

    expected_importer_obj = {
      identifier: "advisory_improvement/#{improvement_data.actor_id}/#{improvement_data.ghsa_id}",
      ghsa_id: improvement_data.ghsa_id,
      cve_id: nil,
      raw_payload: {
        "ghsa_id" => improvement_data.ghsa_id,
        "summary" => "This is a test advisory title",
        "description" => "This is a test advisory description",
        "source_code_location" => "",
        "severity" => "critical", # raw payload preserves exactly what was sent in
        "cvss_v3" => cvss_vector,
        "cvss_v4" => "",
        "cwe_ids" => [],
        "references" => [],
        "affected_products" => [],
        "actor_id" => 1234,
        "actor_login" => "testuser",
        "pr_number" => nil,
      },
      advisory_payload: {
        summary: "This is a test advisory title",
        description: "This is a test advisory description",
        source_code_location: "",
        severity: "moderate", # advisory payload calculates the severity based on cvss
        cvss_v3: cvss_vector,
        cvss_v4: nil,
        references: [],
        cwe_ids: [],
        vulnerabilities: {},
        withdrawn: false,
      },
    }
    assert_equal(expected_importer_obj, improvement_data.importer_object)
  end

  test "constructs vulnerabilities from the affected products" do
    affected_products = [
      {
        package_ecosystem: "npm",
        package_name: "nodemon",
        vulnerable_version_range: "< 1.0.0",
        first_patched_version: "1.0.0",
      },
      {
        package_ecosystem: "go",
        package_name: "gomon",
        vulnerable_version_range: "< 1.2.3",
        first_patched_version: "1.2.3",
      },
      {
        package_ecosystem: "nuget",
        package_name: "nugetmon",
        vulnerable_version_range: "< 2.3.4",
        first_patched_version: "2.3.4",
      },
    ]
    improvement_data = create(:advisory_improvement_data, affected_products: affected_products)

    affected_products.each_with_index do |affected_product, index|
      actual_affected_product = improvement_data.vulnerabilities[index]

      assert_equal affected_product[:package_ecosystem], actual_affected_product[:ecosystem]
      assert_equal affected_product[:package_name], actual_affected_product[:package_name]
      assert_equal affected_product[:vulnerable_version_range], actual_affected_product[:vulnerable_version_range]
      assert_equal affected_product[:first_patched_version], actual_affected_product[:first_patched_version]
    end
  end
end
