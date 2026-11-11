# typed: false
# frozen_string_literal: true

class OrganizationOIDCSubClaimTemplate < ApplicationRecord::Domain::Oidc
  # get the claim-keys to customize the Actions OIDC sub claim for the org
  def self.get_template_for_org(org_id)
    started_at = GitHub::Dogstats.monotonic_time
    self.where(organization_id: org_id)&.first
  end

  # create or update the claim-keys to customize the Actions OIDC sub claim for the org
  def self.create_or_update_template(org_id, requested_template, use_immutable_subject: nil)
    started_at = GitHub::Dogstats.monotonic_time
    self.transaction do
      existing_template = self.where(organization_id: org_id)&.first
      if existing_template
        attrs = { template: requested_template }
        attrs[:use_immutable_subject] = use_immutable_subject unless use_immutable_subject.nil?
        existing_template.update!(attrs)
        :updated
      else
        attrs = { organization_id: org_id, template: requested_template }
        attrs[:use_immutable_subject] = use_immutable_subject unless use_immutable_subject.nil?
        self.create!(attrs)
        :created
      end
    end
  ensure
    GitHub.dogstats.distribution("oidc_custom_template_usage.org_usage_create_or_update_for_org.time", GitHub::Dogstats.duration(started_at), tags: ["oidc:oidc_custom_template_usage.org_by_repo"])
  end
end
