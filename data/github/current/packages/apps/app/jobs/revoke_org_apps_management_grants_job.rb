# typed: true
# frozen_string_literal: true

class RevokeOrgAppsManagementGrantsJob < ApplicationJob
  queue_as :revoke_org_apps_management_grants

  discard_on ActiveJob::DeserializationError

  RevocationError = Class.new(StandardError)
  retry_on RevocationError
  retry_on_dirty_exit

  resolve_tenant_context do |org|
    org&.business
  end

  attr_reader :org, :user

  def perform(org, user)
    @org = org
    @user = user

    revoke_all_apps_grant
    revoke_single_apps_grants
  end

  private

  def revoke_all_apps_grant
    result = with_write do
      Permissions::Granter.revoke(
        actor_id: user.id,
        action: :manage_all_apps,
        subject_id: org.id,
      )
    end

    unless result.success?
      raise RevocationError.new(result.reason)
    end
  end

  def revoke_single_apps_grants
    failed = []
    org.integrations.find_each do |integration|
      # consider creating a separate job for revoking individual apps grants
      # to not retry revocations for grants that were already revoked
      result = with_write { revoke_single_app_grant(integration) }
      failed << result unless result.success?
    end

    if failed.any?
      exception_message = failed.first(5).map(&:reason).to_sentence
      raise RevocationError.new(exception_message)
    end
  end

  def revoke_single_app_grant(integration)
    with_write do
      Permissions::Granter.revoke(
        actor_id: user.id,
        action: :manage_app,
        subject_id: integration.id,
      )
    end
  end
end
