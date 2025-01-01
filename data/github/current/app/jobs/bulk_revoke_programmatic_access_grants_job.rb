# typed: true
# frozen_string_literal: true

# This job is for revoking programmatic access grants in bulk.
class BulkRevokeProgrammaticAccessGrantsJob < ApplicationJob
  queue_as :programmatic_access_grants

  retry_on_dirty_exit

  def perform(grant_ids:, actor:, target:)
    grants = fetch_grants(grant_ids, target)

    revoked_grants = []
    grants.each do |grant|
      result = with_write { ProgrammaticAccessGrant.revoke(grant, actor, skip_revoke_notification: true) }
      revoked_grants << result unless result.errors.any?
    end

    grouped_accesses = revoked_grants.map(&:user_programmatic_access).group_by { |access| access.owner }

    grouped_accesses.each do |owner, accesses|
      UserProgrammaticAccess.notify_owner(about: :revoked, accesses: accesses, owner: owner, target: target)
    end
  end

  private

  def fetch_grants(grant_ids, target)
    return [] if grant_ids.nil? || target.nil?

    ProgrammaticAccessGrant.
      with_target(target).
      where(id: grant_ids).
      preload(user_programmatic_access: [:owner])
  end
end
