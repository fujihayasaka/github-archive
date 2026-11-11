#!/usr/bin/env safe-ruby
# typed: true
# frozen_string_literal: true

require_relative "../config/environment"
require "faker"

unless Rails.env.development?
  abort "This can only be run in development"
end

class CreateExampleVulnerabilities
  SEEDS = [
    {
      ecosystem: "RubyGems",
      severity: "critical",
      versions: [
        {
          package_name: "octokit",
          vulnerable_versions: ">= 4.10.0, < 4.14.0",
          fixed_in: "4.14.0",
        },
        {
          package_name: "octokit",
          vulnerable_versions: ">= 3.0.0, < 3.2.0",
          fixed_in: nil,
        },
      ],
    },
    {
      ecosystem: "RubyGems",
      severity: "moderate",
      versions: [
        {
          package_name: "multipart-post",
          vulnerable_versions: ">= 2.0.0",
          fixed_in: nil,
        },
      ],
    },
    {
      ecosystem: "RubyGems",
      severity: "high",
      versions: [
        {
          package_name: "faraday",
          vulnerable_versions: "> 0.1.0, < 0.15.4",
          fixed_in: "0.15.3",
        },
      ],
    },
    {
      ecosystem: "RubyGems",
      severity: "critical",
      visibility: "innersource",
      owner: Business.find_by(slug: "github-inc"),
      versions: [
        {
          package_name: "faraday",
          vulnerable_versions: "> 0.1.0, < 0.15.4",
          fixed_in: "0.15.3",
        },
      ],
    },
    {
      ecosystem: "RubyGems",
      severity: "low",
      versions: [
        {
          package_name: "octokit",
          vulnerable_versions: "> 4.10.0",
          fixed_in: nil,
        },
      ],
    },
    {
      ecosystem: "RubyGems",
      severity: "critical",
      visibility: "innersource",
      owner: User.find_by_login("github"),
      external_id: "internal-octokit-1234",
      versions: [
        {
          package_name: "octokit",
          vulnerable_versions: ">= 5.0.0, < 6.0.0",
          fixed_in: "6.0.0",
        },
      ],
    },
    {
      ecosystem: "pip",
      severity: "critical",
      versions: [
        {
          package_name: "pyyaml",
          vulnerable_versions: "< 4.1",
          fixed_in: "4.1"
        }
      ]
    },
    {
      ecosystem: "npm",
      severity: "critical",
      versions: [
        {
          package_name: "sawyer",
          vulnerable_versions: ">= 0.8.1",
          fixed_in: nil,
        }
      ],
      cwe: "CWE-178"
    },
    {
      ecosystem: "maven",
      severity: "critical",
      versions: [
        {
          package_name: "org.apache.commons:commons-text",
          vulnerable_versions: "<= 2.0.0",
          fixed_in: "2.0.1",
        },
      ]
    },
    {
      ecosystem: "maven",
      severity: "critical",
      versions: [
        {
          package_name: "org.apache.commons:commons-lang3",
          vulnerable_versions: "< 4.0.0",
          fixed_in: "4.0.0",
        },
      ]
    },
  ]

  def create_vulnerabilities
    SEEDS.each do |params|
      vulnerability = vulnerability_class.create!(
        ghsa_id: params[:visibility] == "innersource" ? new_ghsi_id : new_ghsa_id,
        severity: params[:severity],
        description: new_description,
        classification: "general",
        status: "published",
        published_at: Time.now.utc,
        summary: new_summary,
        visibility: params[:visibility] || "open_source",
        owner: params[:owner],
        external_id: params[:external_id],
        cve_id: new_cve_id,
      )

      params[:versions].each do |version|
        vulnerability.vulnerable_version_ranges.create!(
          affects: version[:package_name],
          ecosystem: params[:ecosystem],
          requirements: version[:vulnerable_versions],
          fixed_in: version[:fixed_in],
        )
      end

      CWEReference.create!(source: vulnerability, cwe: CWE.find_by(cwe_id: params[:cwe])) if params[:cwe]
    end
  end

  def call
    create_vulnerabilities
  end

  private

  def vulnerability_class
    ::Vulnerability
  end

  def new_ghsa_id
    ::AdvisoryDB::GhsaIdGenerator.generate_unique_ghsa_id
  end

  def new_ghsi_id
    ::AdvisoryDB::GhsaIdGenerator.generate_unique_ghis_id
  end

  def new_cve_id
    "CVE-#{Time.now.year}-#{Vulnerability.maximum(:id).to_i + 1}" # rubocop:disable GitHub/PreventUnscopedVulnerabilityQueries
  end

  def new_description
    Faker::Lorem.paragraphs(number: 4).join("\n\n")
  end

  def new_summary
    Faker::Lorem.sentence(word_count: 5)
  end
end

if __FILE__ == $0
  CreateExampleVulnerabilities.new.call
end
