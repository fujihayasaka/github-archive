# typed: true
# frozen_string_literal: true

# Given an organization or enterprise and one or more users, revokes any
# OauthAuthorization and OauthAccess records associated with both the user and
# the internal visibility GitHub Apps owned by either the given enterprise, or
# the owning enterprise of the given organization.
#
# Example 1: Revoking OAuth authorizations as part of removing an organization
# member:
#
# ```
# RevokeInternalAppAuthorizationsJob.perform_later(
#   organization_id: org.id,
#   user_ids: [user.id]
# )
# ```
#
# Example 2: Revoking OAuth authorizations as part of removing an enterprise
# membership:
#
# ```
# RevokeInternalAppAuthorizationsJob.perform_later(
#   enterprise_id: business.id,
#   user_ids: [user.id]
# )
# ```
class RevokeInternalAppAuthorizationsJob < ApplicationJob

  queue_as :revoke_internal_app_authorizations

  retry_on_dirty_exit

  def perform(enterprise_id: nil, organization_id: nil, user_ids: nil)
    user_ids = Array(user_ids).compact
    enterprise = find_enterprise(enterprise_id: enterprise_id, organization_id: organization_id)
    return if user_ids.empty? || enterprise.nil?

    internal_app_ids = enterprise.integrations.internal_visibility.pluck(:id)
    if internal_app_ids.any?
      authorizations = OauthAuthorization.where(
        user_id: user_ids,
        application_id: internal_app_ids,
        application_type: Integration
      )
      with_write { authorizations.destroy_all } if authorizations.any?
    end
  end

  private

  def find_enterprise(enterprise_id: nil, organization_id: nil)
    if enterprise_id.present?
      Business.find_by(id: enterprise_id)
    elsif organization_id.present?
      org = Organization.find_by(id: organization_id)
      org&.business
    end
  end
end
