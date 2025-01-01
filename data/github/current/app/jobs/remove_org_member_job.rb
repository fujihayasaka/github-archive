# typed: true
# frozen_string_literal: true

class RemoveOrgMemberJob < ApplicationJob
  queue_as :remove_org_member

  # Only a single unique instance of the job can be concurrently running
  # per org and user being removed
  locked_by timeout: 5.minutes, key: -> (job) { "remove_org_member_job:#{job.arguments[0]}_#{job.arguments[1]}" }

  discard_on Organization::UnableToRemoveEnterpriseTeamMemberError, Organization::UnableToRemoveEmuError

  resolve_tenant_context do |org_id, user_id|
    org = Organization.find_by(id: org_id)
    next org.business if org&.business

    user = User.find_by(id: user_id)
    user&.enterprise_managed_business
  end

  def perform(org_id, user_id, options = {})
    return unless org = Organization.find_by(id: org_id)
    return unless user = User.find_by(id: user_id)

    org.remove_member!(user, **options)
  end
end
