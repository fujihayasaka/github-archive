# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityAdvisoryTest < GitHub::TestCase
  fixtures do
    @vulnerability = create :vulnerability, cve_id: "CVE-1900-0001",
                                            references: [
                                              "https://example.com/oh-noes"
                                            ],
                                            severity: :high,
                                            published_at: DateTime.parse("2018-01-04 14:00:00 +00:00"),
                                            with_ranges: 0

    @incomplete_vulnerability = create :vulnerability

    @unreviewed_vulnerability = create :vulnerability, :unreviewed
  end

  context "disclosed scope and predicate" do
    test "collections are limited to non-simulation records" do
      simulation = create(:vulnerability_with_range, simulation: true)
      non_simulation = create(:vulnerability_with_range, simulation: false)

      refute_predicate simulation, :disclosed?
      assert_predicate non_simulation, :disclosed?

      disclosed_ids = SecurityAdvisory.disclosed.ids
      refute_includes disclosed_ids, simulation.id
      assert_includes disclosed_ids, non_simulation.id
    end

    test "collections limited to public ecosystems" do
      public_ecosystem = create :published_vulnerability, ecosystem: "npm"
      non_public_ecosystem = create :published_vulnerability, ecosystem: "test_preview_eco"

      assert_predicate public_ecosystem, :disclosed?
      refute_predicate non_public_ecosystem, :disclosed?

      disclosed_ids = SecurityAdvisory.disclosed.ids
      assert_includes disclosed_ids, public_ecosystem.id
      refute_includes disclosed_ids, non_public_ecosystem.id
    end
  end

  test "looking up a vulnerability by id" do
    @advisory = SecurityAdvisory.find(@vulnerability.id)

    assert_equal @vulnerability.id, @advisory.id
    assert_equal "CVE-1900-0001", @advisory.identifier
    assert_equal @vulnerability.ghsa_id, @advisory.ghsa_id
  end

  context "decorators" do
    test "it summarizes the issue with a standard message if the underlying vulnerability summary is not present" do
      create :vulnerable_version_range, vulnerability: @vulnerability,
                                        affects: "foo"

      create :vulnerable_version_range, vulnerability: @vulnerability,
                                        affects: "bar"

      create :vulnerable_version_range, vulnerability: @vulnerability,
                                        affects: "baz"

      @advisory = SecurityAdvisory.find(@vulnerability.id)

      assert_equal "High severity vulnerability that affects bar, baz, and foo",
                   @advisory.summary
    end

    test "it summarizes the issue using the underlying vulnerability summary if it is present" do
      create(:vulnerable_version_range, vulnerability: @vulnerability, affects: "foo")
      expected_summary = "This is the summary for this vulnerability"
      @vulnerability.update!(summary: expected_summary)
      @advisory = SecurityAdvisory.find(@vulnerability.id)

      assert_equal(expected_summary, @advisory.summary)
    end

    test "it summarizes the issue using the description if other information is not present" do
      long_description = Faker::Lorem.paragraph
      @unreviewed_vulnerability.update!(description: long_description)
      @advisory = SecurityAdvisory.find(@unreviewed_vulnerability.id)

      assert(@advisory.summary.present? && long_description.starts_with?(@advisory.summary))
    end

    test "it wraps identifiers correctly" do
      @advisory = SecurityAdvisory.find(@vulnerability.id)

      assert_same_elements(
        [
          {
            value: @advisory.ghsa_id,
            type: "GHSA",
          },
          {
            value: "CVE-1900-0001",
            type: "CVE",
          },
        ], @advisory.identifiers)
    end

    test "if cve_id and white_source_id are defined, only the cve_id is additionally listed" do
      vulnerability = create(:vulnerability, cve_id: "CVE-2020-1111", white_source_id: "WS-2019-3333")
      advisory = vulnerability.becomes(SecurityAdvisory)
      assert_same_elements(
        [
          {
            value: advisory.ghsa_id,
            type: "GHSA",
          },
          {
            value: "CVE-2020-1111",
            type: "CVE",
          },
        ], advisory.identifiers)
    end

    test "it wraps references correctly" do
      @advisory = SecurityAdvisory.find(@vulnerability.id)
      create :vulnerability_reference,
              vulnerability: @advisory,
              url: "https://nvd.nist.gov/vuln/detail/CVE-1900-0001"

      assert_same_elements(
        [
          {
            url: "https://example.com/oh-noes",
          },
          {
            url: "https://nvd.nist.gov/vuln/detail/CVE-1900-0001",
          },
          {
            url: "https://github.com/advisories/#{@vulnerability.ghsa_id}",
          },
        ], @advisory.references)
    end

    test "it backfills the permalink of the advisory if there are no other references" do
      @incomplete_advisory = SecurityAdvisory.find(@incomplete_vulnerability.id)

      assert_same_elements [
        {
          url: "https://github.com/advisories/#{@incomplete_advisory.ghsa_id}",
        },
      ], @incomplete_advisory.references
    end

    test "it wraps vulnerable version ranges as vulnerabilities" do
      @vvr1 = create :vulnerable_version_range, vulnerability: @vulnerability,
                                                 affects: "safe_eval",
                                                 requirements: "<= 1.0.0",
                                                 fixed_in: "1.0.1",
                                                 ecosystem: "RubyGems"

      @vvr2 = create :vulnerable_version_range, vulnerability: @vulnerability,
                                                 affects: "safe_eval",
                                                 requirements: ">= 2.0.0, < 2.4.1",
                                                 fixed_in: "2.4.1",
                                                 ecosystem: "RubyGems"

      @vvr3 = create :vulnerable_version_range, vulnerability: @vulnerability,
                                                affects: "super_safe_eval",
                                                requirements: ">= 0.0.1",
                                                fixed_in: nil,
                                                ecosystem: "RubyGems"

      @advisory = SecurityAdvisory.find(@vulnerability.id)

      assert_same_elements [@vvr1.id, @vvr2.id, @vvr3.id], @advisory.vulnerabilities.pluck(:id)
    end
  end

  context "#primary_reference" do
    test "returns the first vulnerability reference if available" do
      security_advisory = @vulnerability.becomes(SecurityAdvisory)
      assert_equal "https://example.com/oh-noes", security_advisory.primary_reference
    end

    test "returns the permalink if no vulnerability reference is available" do
      vulnerability = create(:vulnerability)
      security_advisory = vulnerability.becomes(SecurityAdvisory)

      assert_equal "https://github.com/advisories/#{vulnerability.ghsa_id}", security_advisory.primary_reference
    end
  end

  context "#public_vulnerabilities" do
    test "returns only vulnerabilities with public ecosystems" do
      @vvr1 = create :vulnerable_version_range, vulnerability: @vulnerability,
                                                 affects: "safe_eval",
                                                 requirements: "<= 1.0.0",
                                                 fixed_in: "1.0.1",
                                                 ecosystem: "RubyGems"

      @vvr2 = create :vulnerable_version_range, vulnerability: @vulnerability,
                                                 affects: "safe_eval",
                                                 requirements: ">= 2.0.0, < 2.4.1",
                                                 fixed_in: "2.4.1",
                                                 ecosystem: "RubyGems"

      @vvr3 = create :vulnerable_version_range, :preview,
                                                vulnerability: @vulnerability,
                                                affects: "super_safe_eval",
                                                requirements: ">= 0.0.1",
                                                fixed_in: nil

      @advisory = SecurityAdvisory.find(@vulnerability.id)

      assert_same_elements [@vvr1.id, @vvr2.id], @advisory.public_vulnerabilities.pluck(:id)
    end
  end

  context "#matches_ecosystem?" do
    test "returns true if at least one of the vulnerable version ranges associated with the security advisory has the ecosystem in question" do
      vulnerability = create(:vulnerability)
      create(:vulnerable_version_range, ecosystem: "npm", vulnerability: vulnerability)
      create(:vulnerable_version_range, ecosystem: "nuget", vulnerability: vulnerability)
      create(:vulnerable_version_range, ecosystem: "go", vulnerability: vulnerability)
      security_advisory = vulnerability.becomes(SecurityAdvisory)

      assert security_advisory.matches_ecosystem?("nuget")
    end

    test "returns false if none of the vulnerable version ranges associated with the security advisory has the ecosystem in question" do
      vulnerability = create(:vulnerability, with_ranges: 0)
      create(:vulnerable_version_range, ecosystem: "npm", vulnerability: vulnerability)
      create(:vulnerable_version_range, ecosystem: "nuget", vulnerability: vulnerability)
      create(:vulnerable_version_range, ecosystem: "go", vulnerability: vulnerability)
      security_advisory = vulnerability.becomes(SecurityAdvisory)

      refute security_advisory.matches_ecosystem?("RubyGems")
    end
  end
end
