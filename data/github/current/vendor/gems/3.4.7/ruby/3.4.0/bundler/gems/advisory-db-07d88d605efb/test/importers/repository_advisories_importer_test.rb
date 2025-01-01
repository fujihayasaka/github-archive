# frozen_string_literal: true

require "test_helper"

class RepositoryAdvisoriesImporterTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "knows its source" do
    assert_equal "repository_advisories", RepositoryAdvisoriesImporter.source
  end

  test "Makes a feed entry if one does not already exist" do
    curation_data = create(:repository_advisory_curation_data)
    assert_difference -> { FeedEntry.count }, 1 do
      RepositoryAdvisoriesImporter.new(repo_advisory_curation_data: curation_data).import
    end
    new_feed_entry = FeedEntry.last
    assert_equal "repository_advisories", new_feed_entry.source
    assert_equal "repository_advisory/#{curation_data.ghsa_id}", new_feed_entry.identifier
  end

  test "publishes feed entry to hydro successfully, with non supported ecosystem set" do
    # use a non-supported ecosystem
    # since the hydro object requires a supported ecosystem,
    # the ecosystem should not be sent over hydro in this case
    curation_data = create(:repository_advisory_curation_data)
    curation_data.affected_products[0][:package_ecosystem] = "cargo"

    perform_enqueued_jobs(only: [ImportJob, ResolveFeedEntryJob, PublishImportFeedEntryToHydroJob]) do
      RepositoryAdvisoriesImporter.new(repo_advisory_curation_data: curation_data).import
    end
    message = hydro_messages.last
    assert message, "Feed entry message not found, should have been published"
    # vulnerabilities object should be empty, since cargo is not support ecosystem
    assert_equal [], message.dig(:feed_entry, :advisory_payload, :vulnerabilities)
  end
end

class RepositoryAdvisoryCurationDataTest < ActiveSupport::TestCase
  test "#importer_object" do
    ghsa_id = "GHSA-95qh-cr8q-7j8v"
    curation_data = create :repository_advisory_curation_data,
      ghsa_id: ghsa_id

    expected_importer_obj = {
      identifier: "repository_advisory/GHSA-95qh-cr8q-7j8v",
      ghsa_id: ghsa_id,
      cve_id: nil,
      raw_payload: {
        "ghsa_id" => "GHSA-95qh-cr8q-7j8v",
        "permalink" => "https://github.com/testorg/testrepo/security/advisories/GHSA-95qh-cr8q-7j8v",
        "title" => "This is a test advisory title",
        "description" => "This is a test advisory description",
        "severity" => "low",
        "cvss_v3" => "",
        "cvss_v4" => "",
        "cve_id" => "",
        "cwe_ids" => [],
        "affected_products" => [
          { "package_ecosystem" => "cargo",
            "package_name" => "popular_package",
            "vulnerable_version_range" => "< 1.2.3",
            "first_patched_version" => "1.2.3" },
        ],
      },
      advisory_payload: {
        summary: "This is a test advisory title",
        description: "This is a test advisory description",
        source_code_location: "https://github.com/testorg/testrepo",
        severity: "low",
        cvss_v3: nil,
        cvss_v4: nil,
        references: ["https://github.com/testorg/testrepo/security/advisories/GHSA-95qh-cr8q-7j8v"],
        cwe_ids: [],
        vulnerabilities: {
          0 => {
            ecosystem: "cargo",
            package_name: "popular_package",
            vulnerable_version_range: "< 1.2.3",
            first_patched_version: "1.2.3",
          },
        },
        withdrawn: false,
      },
    }
    assert_equal(expected_importer_obj, curation_data.importer_object)
  end

  test "when basic severity is specified, and cvss is not, then resulting importer object should have severity specified and not cvss" do
    # initialize cvss_v3 with blank string, just like hydro does (hydro does not allow nil/null)
    curation_data = create :repository_advisory_curation_data, severity: "critical", cvss_v3: ""

    expected_importer_obj = {
      identifier: "repository_advisory/#{curation_data.ghsa_id}",
      ghsa_id: curation_data.ghsa_id,
      cve_id: nil,
      raw_payload: {
        "ghsa_id" => curation_data.ghsa_id,
        "permalink" => "https://github.com/testorg/testrepo/security/advisories/#{curation_data.ghsa_id}",
        "title" => "This is a test advisory title",
        "description" => "This is a test advisory description",
        "severity" => "critical",
        "cvss_v3" => "",
        "cvss_v4" => "",
        "cve_id" => "",
        "cwe_ids" => [],
        "affected_products" => [
          { "package_ecosystem" => "cargo",
            "package_name" => "popular_package",
            "vulnerable_version_range" => "< 1.2.3",
            "first_patched_version" => "1.2.3" },
        ],
      },
      advisory_payload: {
        summary: "This is a test advisory title",
        description: "This is a test advisory description",
        source_code_location: "https://github.com/testorg/testrepo",
        severity: "critical",
        cvss_v3: nil,
        cvss_v4: nil,
        references: ["https://github.com/testorg/testrepo/security/advisories/#{curation_data.ghsa_id}"],
        cwe_ids: [],
        vulnerabilities: {
          0 => {
            ecosystem: "cargo",
            package_name: "popular_package",
            vulnerable_version_range: "< 1.2.3",
            first_patched_version: "1.2.3",
          },
        },
        withdrawn: false,
      },
    }
    assert_equal(expected_importer_obj, curation_data.importer_object)
  end

  # the form has two options for specifying a "severity".
  # - Option a) user can specify a basic severity (low/moderate/high/critical)
  # - Option b) user can specify a cvss vector string.  Generally we would expect the basic severity to be blank when this happens
  # When cvss is used, the severity should be set in accordance with the calculated severity
  # this test makes sure that is happening, by sending both severity and cvss_v3 (which is practice should never happen)
  test "when cvss_v3 is specified, then severity is set based on the cvss_v3, even if severity is specified and disagrees with cvss" do
    # The given cvss string evaluates to "moderate" severity.  The given severity of critical should be ignored
    cvss_vector = "CVSS:3.0/AV:N/AC:L/PR:L/UI:N/S:U/C:L/I:N/A:N"
    curation_data = create :repository_advisory_curation_data, severity: "critical", cvss_v3: cvss_vector

    expected_importer_obj = {
      identifier: "repository_advisory/#{curation_data.ghsa_id}",
      ghsa_id: curation_data.ghsa_id,
      cve_id: nil,
      raw_payload: {
        "ghsa_id" => curation_data.ghsa_id,
        "permalink" => "https://github.com/testorg/testrepo/security/advisories/#{curation_data.ghsa_id}",
        "title" => "This is a test advisory title",
        "description" => "This is a test advisory description",
        "severity" => "critical", # raw payload preserves exactly what was sent in
        "cvss_v3" => cvss_vector,
        "cvss_v4" => "",
        "cve_id" => "",
        "cwe_ids" => [],
        "affected_products" => [
          { "package_ecosystem" => "cargo",
            "package_name" => "popular_package",
            "vulnerable_version_range" => "< 1.2.3",
            "first_patched_version" => "1.2.3" },
        ],
      },
      advisory_payload: {
        summary: "This is a test advisory title",
        description: "This is a test advisory description",
        source_code_location: "https://github.com/testorg/testrepo",
        severity: "moderate", # advisory payload calculates the severity based on cvss
        cvss_v3: cvss_vector,
        cvss_v4: nil,
        references: ["https://github.com/testorg/testrepo/security/advisories/#{curation_data.ghsa_id}"],
        cwe_ids: [],
        vulnerabilities: {
          0 => {
            ecosystem: "cargo",
            package_name: "popular_package",
            vulnerable_version_range: "< 1.2.3",
            first_patched_version: "1.2.3",
          },
        },
        withdrawn: false,
      },
    }
    assert_equal(expected_importer_obj, curation_data.importer_object)
  end

  # the form has two options for specifying a "severity".
  # - Option a) user can specify a basic severity (low/moderate/high/critical)
  # - Option b) user can specify a cvss vector string.  Generally we would expect the basic severity to be blank when this happens
  # When cvss is used, the severity should be set in accordance with the calculated severity
  # this test makes sure that is happening, by sending both severity and cvss_v4 (which is practice should never happen)
  test "when cvss_v4 is specified, then severity is set based on the cvss_v4, even if severity is specified and disagrees with cvss and cvss_v3" do
    # The given cvss string evaluates to "moderate" severity.  The given severity of critical should be ignored
    cvss_vector = "CVSS:4.0/AV:N/AC:H/AT:P/PR:L/UI:P/VC:L/VI:L/VA:L/SC:L/SI:H/SA:L"
    cvss_v3_vector = "CVSS:3.1/AV:N/AC:H/PR:L/UI:R/S:U/C:L/I:N/A:N"
    curation_data = create :repository_advisory_curation_data, severity: "critical", cvss_v4: cvss_vector, cvss_v3: cvss_v3_vector

    expected_importer_obj = {
      identifier: "repository_advisory/#{curation_data.ghsa_id}",
      ghsa_id: curation_data.ghsa_id,
      cve_id: nil,
      raw_payload: {
        "ghsa_id" => curation_data.ghsa_id,
        "permalink" => "https://github.com/testorg/testrepo/security/advisories/#{curation_data.ghsa_id}",
        "title" => "This is a test advisory title",
        "description" => "This is a test advisory description",
        "severity" => "critical", # raw payload preserves exactly what was sent in
        "cvss_v4" => cvss_vector,
        "cvss_v3" => cvss_v3_vector,
        "cve_id" => "",
        "cwe_ids" => [],
        "affected_products" => [
          { "package_ecosystem" => "cargo",
            "package_name" => "popular_package",
            "vulnerable_version_range" => "< 1.2.3",
            "first_patched_version" => "1.2.3" },
        ],
      },
      advisory_payload: {
        summary: "This is a test advisory title",
        description: "This is a test advisory description",
        source_code_location: "https://github.com/testorg/testrepo",
        severity: "moderate", # advisory payload calculates the severity based on cvss V4
        cvss_v3: cvss_v3_vector,
        cvss_v4: cvss_vector,
        references: ["https://github.com/testorg/testrepo/security/advisories/#{curation_data.ghsa_id}"],
        cwe_ids: [],
        vulnerabilities: {
          0 => {
            ecosystem: "cargo",
            package_name: "popular_package",
            vulnerable_version_range: "< 1.2.3",
            first_patched_version: "1.2.3",
          },
        },
        withdrawn: false,
      },
    }
    assert_equal(expected_importer_obj, curation_data.importer_object)
  end

  test "when CWE IDs are set" do
    ghsa_id = "GHSA-95qh-cr8q-7j8v"
    curation_data = create :repository_advisory_curation_data,
      ghsa_id: ghsa_id,
      cwe_ids: ["CWE-79", "CWE-200"]

    expected_importer_obj = {
      identifier: "repository_advisory/GHSA-95qh-cr8q-7j8v",
      ghsa_id: ghsa_id,
      cve_id: nil,
      raw_payload: {
        "ghsa_id" => "GHSA-95qh-cr8q-7j8v",
        "permalink" => "https://github.com/testorg/testrepo/security/advisories/GHSA-95qh-cr8q-7j8v",
        "title" => "This is a test advisory title",
        "description" => "This is a test advisory description",
        "severity" => "low",
        "cvss_v3" => "",
        "cvss_v4" => "",
        "cve_id" => "",
        "cwe_ids" => ["CWE-79", "CWE-200"],
        "affected_products" => [
          { "package_ecosystem" => "cargo",
            "package_name" => "popular_package",
            "vulnerable_version_range" => "< 1.2.3",
            "first_patched_version" => "1.2.3" },
        ],
      },
      advisory_payload: {
        summary: "This is a test advisory title",
        description: "This is a test advisory description",
        source_code_location: "https://github.com/testorg/testrepo",
        severity: "low",
        cvss_v3: nil,
        cvss_v4: nil,
        references: ["https://github.com/testorg/testrepo/security/advisories/GHSA-95qh-cr8q-7j8v"],
        cwe_ids: ["CWE-79", "CWE-200"],
        vulnerabilities: {
          0 => {
            ecosystem: "cargo",
            package_name: "popular_package",
            vulnerable_version_range: "< 1.2.3",
            first_patched_version: "1.2.3",
          },
        },
        withdrawn: false,
      },
    }
    assert_equal(expected_importer_obj, curation_data.importer_object)
  end

  test "retrieves vulnerabilities from the affected products if it is passed in with a non-zero length" do
    affected_products = [
      {
        package_ecosystem: "npm",
        package_name: "nodemon",
        vulnerable_version_range: "< 1.0.0",
        first_patched_version: "1.0.0",
      }.stringify_keys,
      {
        package_ecosystem: "go",
        package_name: "gomon",
        vulnerable_version_range: "< 1.2.3",
        first_patched_version: "1.2.3",
      }.stringify_keys,
      {
        package_ecosystem: "nuget",
        package_name: "nugetmon",
        vulnerable_version_range: "< 2.3.4",
        first_patched_version: "2.3.4",
      }.stringify_keys,
    ]
    repository_advisory_curation_data = create(:repository_advisory_curation_data, affected_products: affected_products)

    affected_products.each_with_index do |affected_product, index|
      actual_affected_product = repository_advisory_curation_data.vulnerabilities[index]

      assert_equal affected_product["package_ecosystem"], actual_affected_product[:ecosystem]
      assert_equal affected_product["package_name"], actual_affected_product[:package_name]
      assert_equal affected_product["vulnerable_version_range"], actual_affected_product[:vulnerable_version_range]
      assert_equal affected_product["first_patched_version"], actual_affected_product[:first_patched_version]
    end
  end

  test "does not retrieve vulnerabilities from the affected products if it is passed in with a zero length, using the ecosystem, package, affected_versions, and patches fields instead" do
    repository_advisory_curation_data = create(
      :repository_advisory_curation_data,
      affected_products: [
        { "package_ecosystem" => "rust",
          "package_name" => "rustmon",
          "vulnerable_version_range" => "< 9.3.2",
          "first_patched_version" => "9.3.2" },
      ],
    )

    assert_equal 1, repository_advisory_curation_data.vulnerabilities.length
    vulnerability = repository_advisory_curation_data.vulnerabilities[0]
    assert_equal "rust", vulnerability[:ecosystem]
    assert_equal "rustmon", vulnerability[:package_name]
    assert_equal "< 9.3.2", vulnerability[:vulnerable_version_range]
    assert_equal "9.3.2", vulnerability[:first_patched_version]
  end

  test "normalizes RubyGems to rubygems" do
    repository_advisory_curation_data = create(
      :repository_advisory_curation_data,
      affected_products: [
        { "package_ecosystem" => "RubyGems",
          "package_name" => "rubypackage",
          "vulnerable_version_range" => "< 9.3.2",
          "first_patched_version" => "9.3.2" },
      ],
    )
    assert_equal 1, repository_advisory_curation_data.vulnerabilities.length
    vulnerability = repository_advisory_curation_data.vulnerabilities[0]
    assert_equal "rubygems", vulnerability[:ecosystem]
  end
end
