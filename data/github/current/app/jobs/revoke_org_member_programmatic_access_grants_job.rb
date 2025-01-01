# typed: true
# frozen_string_literal: true

class RevokeOrgMemberProgrammaticAccessGrantsJob < ApplicationJob
  queue_as :programmatic_access_grants

  discard_on ActiveJob::DeserializationError

  retry_on_dirty_exit
  retry_on ActiveRecord::RecordNotDestroyed

  attr_reader :org, :user

  resolve_tenant_context do |_, user|
    Business.find_by(id: user.business_id)
  end

  def perform(org, user)
    @org = org
    @user = user

    return unless @org && @user

    ApplicationRecord::Permissions.throttle_writes_with_retry do
      revoke_programmatic_access_grants
    end
  end

  private

  def revoke_programmatic_access_grants
    # Keep track of the access records when grants are revoked
    # so that we can send a bulk notification to the owner.
    accesses = []

    # Since:
    # - User PATs are capped to 50 entries https://github.com/github/github/pull/208829
    # - This revocation is processed asynchronously, and
    # - Currently PATs can only have one grant
    # We can afford to keep it simple and retrieve/revoke each grant individually.
    ProgrammaticAccess.for(user).find_each do |access|
      access.organization_programmatic_access_grants.where(target: @org).find_each do |org_grant|
        accesses << access
        with_write { org_grant.destroy! }
      end
    end

    UserProgrammaticAccess.notify_owner(about: :revoked, accesses: accesses.uniq, owner: user, target: @org)
  end
end
