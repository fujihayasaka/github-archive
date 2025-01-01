# typed: true
# frozen_string_literal: true

# This job runs on a schedule and adds or deletes early access memberships for org members
# that have been removed from the org or added to the org
class SyncInheritedOrgEarlyAccessMembershipsJob < ApplicationJob
  queue_as :sync_inherited_org_early_access_memberships
  schedule interval: 1.hour, condition: -> { !GitHub.enterprise? }

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  sig { params(args: T.untyped, initial_start: Time, offset_item_id: Integer, progress: Integer, options: T.untyped).void }
  def perform(*args, initial_start: Time.now.utc, offset_item_id: 0, progress: 0, **options)
    return unless GitHub.flipper[:sync_inherited_org_early_access_memberships].enabled?
    betas = InheritOrgEarlyAccessJob::INHERIT_EARLY_ACCESS_BETAS
    org_membership_ids = EarlyAccessMembership
      .where(feature_slug: betas.map(&:feature_slug))
      .select(:parent_id)
      .distinct
      .pluck(:parent_id)
    org_memberships = EarlyAccessMembership.where(id: org_membership_ids, feature_enabled: true)
    org_memberships.each do |org_membership|
      beta = betas.find { |beta| beta.feature_slug == org_membership.feature_slug }
      early_access_member_ids = EarlyAccessMembership.where(
        parent_id: org_membership.id,
        feature_slug: org_membership.feature_slug)
        .pluck(:member_id)
        .sort

      org_member_ids = org_membership.member.member_ids
      eligible_org_member_ids = T.let([], T::Array[Integer])
      org_member_ids.in_groups_of(1000) do |batch|
        User.where(id: batch).each do |member|
          if beta.can_inherit_org_membership?(member)
            eligible_org_member_ids << member.id
          end
        end
      end

      if eligible_org_member_ids.sort != early_access_member_ids
        log("Memberships are out of sync, triggering InheritOrgEarlyAccessJob", org_membership.feature_slug, org_membership)
        InheritOrgEarlyAccessJob.perform_later(org_membership)
      end
    end
  end

  def log(message, feature_slug, org_membership, member: nil)
    GitHub.logger.info("sync_inherited_org_early_access_memberships: #{message}",
      "gh.member.id" => org_membership.member&.id,
      "gh.org.name" => org_membership.member&.name,
      "gh.feature.slug" => feature_slug,
      "feature_enabled" => org_membership.feature_enabled,
    )
  end
end
