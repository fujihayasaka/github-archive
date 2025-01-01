# typed: true
# frozen_string_literal: true

module Api::Serializer::SecurityAdvisoriesDependency
  extend T::Helpers
  requires_ancestor { Api::Serializer::RepositoriesDependency }
  requires_ancestor { Api::Serializer::UserDependency }

  # The `options` hash param can be used to set additional options for the serializer. Example:
  #     - { use_medium_severity: true } # use "medium" severity instead of "moderate"
  def security_advisory_hash(advisory, options = {})
    return nil unless advisory

    # Coerce to the correct subclass.
    if advisory.class == Vulnerability
      advisory = advisory.becomes(SecurityAdvisory)
    end

    # Just in case!
    return nil unless advisory.disclosed?

    # Do not show unreviewed advisories until the API can support them!
    return nil if advisory.unreviewed?

    payload = {
      ghsa_id: advisory.ghsa_id,
      cve_id: advisory.cve_id,
      summary: advisory.summary,
      description: advisory.description,
      severity: security_product_severity(advisory, options),
      identifiers: advisory.identifiers,
      references: advisory.references,
      published_at: time(advisory.published_at),
      updated_at: time(advisory.updated_at),
      withdrawn_at: time(advisory.withdrawn_at),
      vulnerabilities: advisory.vulnerabilities.map do |vulnerability|
        security_vulnerability_hash(vulnerability, options)
      end,
      cvss_severities: {
        cvss_v3: { vector_string: advisory.cvss_v3, score: advisory.cvss_v3_score },
        cvss_v4: { vector_string: advisory.cvss_v4, score: advisory.cvss_v4_score },
      },
    }

    # If the API changeset `deprecate_cvss` is active, don't add the `cvss` property to the payload.
    unless Api::SerializerOptions.from(options).changeset_active?(:deprecate_cvss)
      payload[:cvss] = {
        vector_string: advisory.cvss_v3,
        score: advisory.cvss_v3_score
      }
    end

    payload[:cwes] = advisory.cwes.map do |cwe|
      {
        cwe_id: cwe.cwe_id,
        name: cwe.name
      }
    end

    payload
  end

  # The `options` hash param can be used to set additional options for the serializer. Example:
  #     - { use_medium_severity: true } # use "medium" severity instead of "moderate"
  def security_vulnerability_hash(vulnerability, options = {})
    return nil unless vulnerability

    # Coerce to the correct subclass.
    if vulnerability.class == VulnerableVersionRange
      vulnerability = vulnerability.becomes(SecurityVulnerability)
    end

    {
      package: vulnerability.package,
      severity: security_product_severity(vulnerability, options),
      vulnerable_version_range: vulnerability.vulnerable_version_range,
      first_patched_version: vulnerability.first_patched_version,
    }
  end

  def security_product_severity(object, options = {})
    return "unknown" if object.severity.nil? && options[:use_unknown_severity]
    object.severity == "moderate" && options[:use_medium_severity] ? "medium" : object.severity
  end

  def global_advisories_hash(data, options = {})
    advisories = data.fetch(:advisories, [])

    associations = T.let(
      [
        :repository_advisory,
        :cwes,
        :vulnerable_version_ranges,
        :vulnerability_references,
        :cve_epss,
      ],
      T::Array[T.any(Symbol, T::Hash[Symbol, Symbol])]
    )
    associations << { credits: :recipient } unless GitHub.enterprise?

    GitHub::PrefillAssociations.prefill_associations(advisories, associations)

    advisories.map do |advisory|
      global_advisory_hash(advisory, options)
    end
  end

  # hash payload for global advisory REST API
  def global_advisory_hash(advisory, options = {})
    return nil unless advisory

    # Just in case!
    return nil unless advisory.disclosed?

    payload = {
      ghsa_id: advisory.ghsa_id,
      cve_id: advisory.cve_id,
      url: advisory.api_url,
      html_url: advisory.permalink,
      summary: AdvisoryDB::advisory_title(advisory, length: 100),
      description: advisory.description,
      type: advisory.type,
      severity: security_product_severity(advisory, use_medium_severity: true, use_unknown_severity: true),
      repository_advisory_url: advisory.repository_advisory&.api_url,
      source_code_location: advisory.source_code_location,
      identifiers: advisory.identifiers,
      references: advisory.reference_urls,
      published_at: time(advisory.published_at),
      updated_at: time(advisory.updated_at),
      github_reviewed_at: time(advisory.reviewed_at),
      nvd_published_at: time(advisory.nvd_published_at),
      withdrawn_at: time(advisory.withdrawn_at),
      vulnerabilities: advisory.vulnerable_version_ranges.map { |vulnerability| global_advisory_vulnerability_api_hash(vulnerability, options) },
      cvss_severities: {
        cvss_v3: { vector_string: advisory.cvss_v3, score: advisory.cvss_v3_score },
        cvss_v4: { vector_string: advisory.cvss_v4, score: advisory.cvss_v4_score },
      },
      cwes: advisory.cwes.map do |cwe|
        {
          cwe_id: cwe.cwe_id,
          name: cwe.name,
        }
      end,
      credits: global_advisory_credits(advisory, options),
    }

    # If the API changeset `deprecate_cvss` is active, don't add the `cvss` property to the payload.
    unless Api::SerializerOptions.from(options).changeset_active?(:deprecate_cvss)
      payload[:cvss] = {
        vector_string: advisory.cvss_v3,
        score: advisory.cvss_v3_score.zero? ? nil : advisory.cvss_v3_score,
      }
    end

    if advisory.cve_epss.present?
      payload[:epss] = {
        percentage: advisory.cve_epss&.percentage.to_f,
        percentile: advisory.cve_epss&.percentile.to_f,
      }
    end

    payload
  end

  def global_advisory_vulnerability_api_hash(vulnerability, options = {})
    return nil unless vulnerability

    {
      package: {
        ecosystem: vulnerability.ecosystem.downcase,
        name: vulnerability.affects,
      },
      vulnerable_version_range: vulnerability.requirements,
      first_patched_version: vulnerability.fixed_in,
      vulnerable_functions: vulnerability.affected_functions,
    }
  end

  def global_advisory_credits(advisory, options = {})
    # Credits aren't applicable in GHES/Proxima since they're only for public advisories
    return [] if GitHub.single_or_multi_tenant_enterprise?

    # Don't use .accepted here because it's a scope and takes us back to the db
    GitHub::PrefillAssociations.prefill_associations(advisory.credits, :recipient)
    credits = advisory.credits.filter { |credit| credit.accepted? }
    credits.map do |credit|
      {
        user: simple_user_hash(credit.recipient, options),
        type: credit.credit_type,
      }
    end
  end
end
