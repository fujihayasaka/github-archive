# typed: false
# frozen_string_literal: true

class EnterpriseOIDCIssuerUrlCustomisation < ApplicationRecord::Domain::Oidc

  # get enterprise issuesr policy
  def self.get_issuer_policy(enterprise_id)
    started_at = GitHub::Dogstats.monotonic_time
    self.where(enterprise_id: enterprise_id)&.first
  end

  # Update enterprise issuer policy
  def self.update_issuer_policy(enterprise_id, include_enterprise_slug)
    started_at = GitHub::Dogstats.monotonic_time
    self.transaction do
      existing_record = self.where(enterprise_id: enterprise_id)&.first
      if existing_record
        existing_record.update!(include_enterprise_name: include_enterprise_slug)
        :updated
      else
        self.create!(enterprise_id: enterprise_id, include_enterprise_name: include_enterprise_slug)
        :created
      end
    end
  ensure
    GitHub.dogstats.distribution("actions_oidc_issuer_customisation.update.time", GitHub::Dogstats.duration(started_at), tags: ["action:actions_oidc_issuer_customisation"])
  end
end
