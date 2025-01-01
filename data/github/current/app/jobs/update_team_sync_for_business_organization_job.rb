# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# Organizations that are part of an Enterprise Account (aka business) must have
# a team_sync_tenant that replicates the business' one.
#
# This job ensures that happens for a given org when Team Sync is flipped on the
# Enterprise, when an org joins an Enterprise with Team Sycn enabled, etc.

class UpdateTeamSyncForBusinessOrganizationJob < ApplicationJob
  queue_as :update_team_sync_for_business_organization

  class OrgMustBePartOfABusinessError < RuntimeError; end
  class RegistrationFailed < RuntimeError; end

  # Handle temporary non-availability of the group-syncer service
  retry_on RegistrationFailed, wait: :polynomially_longer, attempts: 7

  # Handle temporary issues when adding organizations to a business
  # (in existing and new orgs, respectively)
  retry_on OrgMustBePartOfABusinessError, wait: :polynomially_longer, attempts: 3
  retry_on ActiveRecord::RecordNotFound, wait: :polynomially_longer, attempts: 3

  def perform(org_id:)
    Failbot.push(org_id: org_id)
    org = Organization.find(org_id)
    business = org.business
    raise OrgMustBePartOfABusinessError unless business
    with_write do
      if business.team_sync_enabled?
        upsert_tenant_from_business(org)
        register_tenant_on_group_syncer(org)
        trigger_app_installation(org)
      else
        org.team_sync_tenant&.disable
      end
    end
  end

  private

  def upsert_tenant_from_business(org)
    tenant = org.team_sync_tenant || org.build_team_sync_tenant
    tenant.update!(
      org.business.team_sync_tenant.slice(
        %w(provider_type provider_id status encrypted_ssws_token url forbid_organization_invites),
      ),
    )
  end

  def register_tenant_on_group_syncer(org)
    err = org.team_sync_tenant.register
    registration_failed(org, err.to_s) if err
  rescue Faraday::Error => exception
    registration_failed(org, exception)
  end

  def registration_failed(org, nested_exception_or_message)
    org.team_sync_tenant.update!(status: "failed")
    raise RegistrationFailed, nested_exception_or_message
  end

  def trigger_app_installation(org)
    AutomaticAppInstallation.trigger(
      type: :team_sync_enabled,
      originator: org,
      actor: org.admins.first,
    )
  end
end
