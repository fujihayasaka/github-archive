# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class OrganizationCollaboratorBackfillJob < ApplicationJob
  queue_as :organization_collaborator_backfill
  retry_on_dirty_exit

  sig { params(org: T.nilable(Organization), business: T.nilable(Business)).void }
  def perform(org: nil, business: nil)
    orgs = if business.present?
      business.organizations.all
    elsif org.present?
      [org]
    end

    if business.present?
      business.enable_feature(:collaborator_cache_write) unless GitHub.flipper[:collaborator_cache_write].enabled?
    end

    if orgs&.any?
      orgs.each do |org|
        org.enable_feature(:collaborator_cache_write) unless GitHub.flipper[:collaborator_cache_write].enabled?
        OrganizationCollaborator.backfill_for_org(org)
      end
    end
  end
end
