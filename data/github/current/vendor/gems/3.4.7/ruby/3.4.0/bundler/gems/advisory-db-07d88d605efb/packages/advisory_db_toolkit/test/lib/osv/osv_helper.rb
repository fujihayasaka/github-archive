# frozen_string_literal: true

require "test_helper"
require "advisory_db_toolkit"

module OSVHelper
  def create_osv_data(vulnerability_count: 0)
    advisory = {
      "id" => "OSV-2020-111",
      "details" => "Sed laboriosam cupiditate. Nulla nisi perspiciatis. Voluptatum ipsum et.\n\nAutem quod rerum. Et est distinctio. Est iusto facilis.\n\nPlaceat et ratione. Aut eum quibusdam. Molestiae est voluptatem.\n\nDistinctio quasi rerum. Ea dolorum cupiditate. Rerum doloribus est.\n\nMaxime dolores rerum. Maxime aut repellendus. Est deleniti omnis.\n\nTemporibus nostrum minus. Sequi aut dolorum. Impedit voluptatem animi.\n\nDolor totam vitae. Et eum doloribus. Culpa autem in.\n\nVitae velit qui. Amet fugit saepe. Ut blanditiis quisquam.\n\nOdit adipisci repellat. Aliquam veniam voluptate. Non inventore deserunt.\n\nExercitationem libero nostrum. Aut sit ut. Itaque quia sunt.",
      "modified" => "2023-03-07T19:07:28Z",
      "published" => "2023-03-07T19:07:26Z",
      "aliases" => [
        "GHSA-vc4r-2cpc-mc65",
      ],
      "summary" => "Et ab autem sed eos fugit blanditiis facilis illum quis sit vitae velit fugiat temporibus",
      "references" => [],
      "database_specific" => { "cwe_ids" => [], "severity" => "MODERATE", "github_reviewed" => true, "github_reviewed_at" => "2023-03-07T19:07:26Z", "nvd_published_at" => nil },
      "affected" => [],
    }
    (0...vulnerability_count).each do
      append_osv_vulnerability(
        advisory:,
        ecosystem: "Maven",
        name: "com.google.protobuf:protobuf-kotlin",
        introduced_in: "3.19.0",
        fixed_in: "3.19.2",
      )
    end
    advisory
  end

  def create_osv_vulnerability(ecosystem:, name:, fixed_in:, introduced_in: "0")
    events = []
    events << { "introduced" => introduced_in }
    events << { "fixed" => fixed_in }

    {
      "package" => {
        "ecosystem" => ecosystem,
        "name" => name,
      },
      "ranges" => [{
        "type" => "ECOSYSTEM",
        "events" => events,
      }],
    }
  end

  def append_osv_vulnerability(advisory:, ecosystem:, name:, fixed_in:, introduced_in: "0")
    advisory["affected"] << create_osv_vulnerability(
      ecosystem:,
      name:,
      fixed_in:,
      introduced_in:,
    )
  end

  def append_osv_reference(advisory:, url:, type: "WEB")
    advisory["references"] << ref = { "type" => type, "url" => url }
    ref
  end

  def append_advisory_reference(advisory:, url:)
    advisory.references << url
    url
  end

  def create_advisory_interface(vulnerability_count: 0)
    advisory = AdvisoryDBToolkit::OSV::Interfaces::Advisory.new
    advisory.ghsa_id = "GHSA-5qhq-9w8w-49q6"
    advisory.published_at = Time.now
    advisory.reviewed_at = Time.now
    advisory.updated_at = Time.now
    advisory.cve_id = nil
    advisory.summary = "sample summary data"
    advisory.description = "sample advisory description"
    advisory.severity = nil
    advisory.reviewed = false
    advisory.source_code_location = nil
    advisory.references = []
    advisory.vulnerabilities = []

    (0...vulnerability_count).each do
      append_vulnerability_interface(
        advisory:,
        package_ecosystem: "Maven",
        package_name: "com.google.protobuf:protobuf-kotlin",
        first_patched_version: "3.19.2",
        vulnerable_version_range: ">= 3.19.0",
      )
    end

    advisory
  end

  def create_vulnerability_interface(package_ecosystem:, package_name: nil, first_patched_version: nil, vulnerable_version_range: ">= 1.2.3, <= 1.2.4")
    AdvisoryDBToolkit::OSV::Interfaces::Vulnerability.new.tap do |vuln|
      vuln.package_ecosystem = package_ecosystem
      vuln.package_name = package_name
      vuln.first_patched_version = first_patched_version
      vuln.vulnerable_version_range = vulnerable_version_range
    end
  end

  def append_vulnerability_interface(advisory:, package_ecosystem:, package_name: nil, first_patched_version: nil, vulnerable_version_range: ">= 1.2.3, <= 1.2.4")
    v = advisory.vulnerabilities
    if v.nil?
      v = []
      advisory.vulnerabilities = v
    end
    v << vuln = create_vulnerability_interface(
      package_ecosystem:,
      package_name:,
      first_patched_version:,
      vulnerable_version_range:,
    )
    vuln
  end
end
