# frozen_string_literal: true

require "normal_yaml"

FactoryBot.define do
  factory :advisory_payload, class: Hash do
    skip_create
    initialize_with { NormalYAML.normalize(attributes) }

    transient do
      reference_count { 1 }
      cwe_id_count { 1 }
      vulnerability_count { 1 }
    end

    summary { build(:summary) }
    description { build(:description) }
    severity { "low" }
    source_code_location { "https://github.com/github/catalyst" }

    references do
      if reference_count == 0
        []
      else
        Array.new(reference_count - 1) do
          generate(:url)
        end.unshift("https://nvd.nist.gov/vuln/detail/CVE-1234-1234")
      end
    end

    cwe_ids do
      cwe_ids = CWE.limit(cwe_id_count).ids
      cwe_ids << create(:cwe).cwe_id while cwe_ids.count < cwe_id_count
      cwe_ids
    end

    cvss_v3 { "CVSS:3.1/AV:L/AC:H/PR:H/UI:R/S:U/C:L/I:L/A:L" }
    cvss_v4 { "" }

    vulnerabilities do
      Array.new(vulnerability_count) do |index|
        [index, create(:vulnerability_payload)]
      end.to_h
    end

    withdrawn { false }

    factory :cve_advisory_payload do
      summary { nil }
      description { "This is the description of a CVE" }
      severity { nil }
      cwe_id_count { 0 }
      vulnerability_count { 0 }
      references do
        [
          "https://nvd.nist.gov/vuln/detail/CVE-1234-1234",
          "https://github.com/link_from_cve_advisory_1",
          "https://github.com/link_from_cve_advisory_2",
        ]
      end
    end

    factory :friends_of_php_advisory_payload do
      summary { "A couple words about an exploit" }
      description { nil }
      references do
        [
          "https://github.com/link_from_php_advisory",
          "https://github.com/FriendsOfPHP/security-advisories/blob/master/api-platform/core/CVE-2019-1000011.yaml",
        ]
      end
      vulnerabilities do
        {
          0 => {
            ecosystem: "composer",
            package_name: "api-platform/core",
            vulnerable_version_range: ">= 2.2.0, < 2.2.10",
            first_patched_version: "2.2.10",
            affected_functions: [],
          },
          1 => {
            ecosystem: "composer",
            package_name: "api-platform/core",
            vulnerable_version_range: ">= 2.3.0, < 2.3.6",
            first_patched_version: "2.3.6",
            affected_functions: [],
          },
        }
      end
    end

    factory :rubysec_advisory_payload do
      summary { "A couple words about an exploit" }
      description { nil }
      references do
        [
          "https://github.com/link_from_rubysec_advisory",
          "https://github.com/rubysec/ruby-advisory-db/blob/master/gems/yard/CVE-2019-1020001.yml",
        ]
      end
      vulnerabilities do
        {
          0 => {
            ecosystem: "rubygems",
            package_name: "yard",
            vulnerable_version_range: "< 0.9.20",
            first_patched_version: "0.9.20",
            affected_functions: [],
          },
        }
      end
    end

    factory :rustsec_advisory_payload do
      summary { "A couple words about an exploit" }
      description { nil }
      references do
        [
          "https://github.com/link_from_rustsec_advisory",
          "https://github.com/RustSec/advisory-db/blob/main/crates/nanorand/RUSTSEC-2020-0089.md",
        ]
      end
      vulnerabilities do
        {
          0 => {
            ecosystem: "rust",
            package_name: "nanorand",
            first_patched_version: "0.5.1",
            affected_functions: [],
          },
        }
      end
    end

    factory :malware_advisory_payload do
      summary { "Malware in ua-parser-js" }
      description { "Any computer that has this package installed or running should be considered fully compromised. All secrets and keys stored on that computer should be rotated immediately from a different computer. The package should be removed, but as full control of the computer may have been given to an outside entity, there is no guarantee that removing the package will remove all malicious software resulting from installing it." }
      severity { "critical" }
      references { [] }
      cwe_ids { ["CWE-506"] }
      cvss_v3 { nil }
      cvss_v4 { nil }
      vulnerabilities do
        {
          0 => {
            package_name: "ua-parser-js",
            ecosystem: "npm",
            vulnerable_version_range: "0.7.29",
            first_patched_version: "",
          },
        }
      end
    end

    factory :other_advisory_payload do
      vulnerabilities do
        {
          0 => {
            ecosystem: "other",
            package_name: "redis",
            vulnerable_version_range: "< 0.5.1",
            first_patched_version: "0.5.1",
            affected_functions: [],
            withdrawn: false,
          },
        }
      end
    end
  end

  factory :vulnerability_payload, class: Hash do
    skip_create
    initialize_with { NormalYAML.normalize(attributes) }

    ecosystem { generate(:ecosystem) }
    package_name { ecosystem == "maven" ? generate(:maven_package_name) : generate(:package_name) }
    vulnerable_version_range { generate(:version_range) }
    first_patched_version { generate(:version) }
    fix_commits { [] }
    withdrawn { false }
  end

  factory :cve_request_hydro_payload, class: Hash do
    skip_create
    initialize_with { NormalYAML.normalize(attributes) }

    transient do
      ghsa_id
    end

    actor do
      {
        id: 1234,
        login: "testuser",
      }
    end

    repository_advisory do
      {
        state: "draft",
        ghsa_id: ghsa_id,
        permalink: "https://github.com/testorg/testrepo/security/advisories/#{ghsa_id}",
        severity: "LOW",
      }
    end

    title { "This is a test advisory title" }
    description { "This is a test advisory description" }
    cve_id { "" }
    cvss_v3 { "CVSS:3.1/AV:A/AC:H/PR:L/UI:R/S:U/C:L/I:H/A:N" }
    cvss_v4 { "" }

    affected_products do
      [
        {
          package_ecosystem: "cargo",
          package_name: "popular_package",
          vulnerable_version_range: "< 1.2.3",
          first_patched_version: "1.2.3",
        },
      ]
    end
  end

  factory :repository_advisory_curation_request_hydro_payload, class: Hash do
    skip_create
    initialize_with { NormalYAML.normalize(attributes) }

    transient do
      ghsa_id
      cve_id
    end

    repository_advisory_content do
      {
        ghsa_id: ghsa_id,
        state: "published",
        permalink: "https://github.com/testorg/testrepo/security/advisories/#{ghsa_id}",
        severity: "LOW",
        title: "This is a test advisory title",
        description: "This is a test advisory description",
        cve_id: cve_id,
        cwe_ids: [],
        cvss_v3: "CVSS:3.1/AV:L/AC:H/PR:H/UI:R/S:U/C:L/I:L/A:L",
        cvss_v4: "",
        affected_products: [
          {
            package_ecosystem: "cargo",
            package_name: "popular_package",
            vulnerable_version_range: "< 1.2.3",
            first_patched_version: "1.2.3",
            affected_functions: ["foo()"],
            affected_functions_json: "",
          },
        ],
      }
    end

    actor do
      {}
    end
  end
end
