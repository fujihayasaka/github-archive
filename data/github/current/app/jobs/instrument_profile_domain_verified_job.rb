# typed: true
# frozen_string_literal: true

class InstrumentProfileDomainVerifiedJob < ApplicationJob
  queue_as :instrument_profile_domain

  # Public: triggers a hydro event for the domain being verified. Will also optionally trigger
  # additional hydro events if the domain that was just verified corresponds to a profile domain
  # for any affiliated organizations.
  #
  # verifiable_domain - VerifiableDomain that was just verified
  # actor             - current_user who verified the domain
  #
  # Returns: nothing
  def perform(verifiable_domain, actor)
    organizations = verifiable_domain.organizations_for_profile_domain

    GlobalInstrumenter.instrument("verifiable_domains.domain_verified", {
      domain: verifiable_domain,
      actor: actor,
      profile_domain_verified: organizations.any?
    })

    organizations.each do |organization|
      GlobalInstrumenter.instrument("verifiable_domains.organization_profile_domain_verified", {
        org: organization,
        verified: organization.is_verified?,
        domain_types: profile_domain_types(organization, verifiable_domain),
        domain: verifiable_domain,
        actor: actor
      })
    end
  end

  # Public: for a given domain, check if it matches any of the profile domains for the org
  # specified and return the type(s) of domains that had matched, if any.
  #
  # organization       - organization whose profile domains we're looking at
  # verifiable_domain  - VerifiableDomain for the domain url to compare against
  #
  # Returns: Array[Symbol]
  #   :web if matched profile_blog
  #   :email if matched profile_email
  def profile_domain_types(organization, verifiable_domain)
    return nil if verifiable_domain.blank?

    types = []
    if VerifiableDomain.normalize_domain(organization.profile_blog) == verifiable_domain.domain
      types << :website
    end

    if VerifiableDomain.normalize_domain(organization.profile_email) == verifiable_domain.domain
      types << :email
    end

    types
  end
end
