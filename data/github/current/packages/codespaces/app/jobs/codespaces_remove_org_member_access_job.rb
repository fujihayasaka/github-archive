# typed: strict
# frozen_string_literal: true

class CodespacesRemoveOrgMemberAccessJob < CodespacesJob

  locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
  retry_on_dirty_exit

  sig { params(org: Organization, user: User).void }
  def perform(org, user)
    has_org_access = org.member?(user) || org.user_is_outside_collaborator?(user)

    unless has_org_access
      with_write { Codespaces::OrgPolicy.revoke_billing_permission!(user, org) }
    end
  end
end
