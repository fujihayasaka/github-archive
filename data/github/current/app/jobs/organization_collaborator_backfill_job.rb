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

    # rubocop:disable GitHub/FeatureManagement/NoActorFeatureFlagManipulation
    if business.present?
      business.enable_feature_flag(:collaborator_cache_write) unless FeatureFlag.vexi.enabled?(:collaborator_cache_write, default: false)
    end

    if orgs&.any?
      orgs.each do |org|
        org.enable_feature_flag(:collaborator_cache_write) unless FeatureFlag.vexi.enabled?(:collaborator_cache_write, default: false)
        OrganizationCollaborator.backfill_for_org(org)
      end
    end
    # rubocop:enable GitHub/FeatureManagement/NoActorFeatureFlagManipulation
  end
end
