# typed: true
# frozen_string_literal: true

# This job runs on a schedule and adds or deletes early access memberships for org members
# that have been removed from the org or added to the org
class SyncInheritedOrgEarlyAccessMembershipsJob < BatchedJob
  queue_as :sync_inherited_org_early_access_memberships
  schedule interval: 1.hour, condition: -> { !GitHub.enterprise? }

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  sig { params(args: T.untyped, timestamp: Time, offset_item_id: Integer, progress: Integer, options: T.untyped).returns(ActiveRecord::Relation) }
  def next_batch(*args, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
    betas = InheritOrgEarlyAccessJob::INHERIT_EARLY_ACCESS_BETAS
    enrolled_orgs = EarlyAccessMembership
      .where("member_id > ?", offset_item_id)
      .where(feature_slug: betas.map(&:feature_slug), member_class_name: "Organization", feature_enabled: true)
      .order(member_id: :asc)
      .distinct
      .limit(BATCH_SIZE)

    EarlyAccessMembership
      .where(
        member_id: enrolled_orgs.pluck(:member_id),
        feature_slug: betas.map(&:feature_slug))
  end

  sig { params(batch: ActiveRecord::Relation, args: T.untyped, options: T.untyped).returns(T.untyped) }
  def process_batch(batch, *args, **options)
    return unless GitHub.flipper[:sync_inherited_org_early_access_memberships].enabled?
    betas = InheritOrgEarlyAccessJob::INHERIT_EARLY_ACCESS_BETAS
    batch_early_access_members = EarlyAccessMembership.where(
      parent_id: batch.pluck(:id),
      feature_slug: betas.map(&:feature_slug))

    parent_ids_to_org_memberships = batch.index_by(&:id)

    batch_early_access_org_to_member_ids = {}
    batch_early_access_members.each do |member|
      next unless parent_ids_to_org_memberships.key?(member.parent_id)
      org_id = parent_ids_to_org_memberships[member.parent_id].member_id
      batch_early_access_org_to_member_ids[org_id] ||= []
      batch_early_access_org_to_member_ids[org_id] << member.member_id
    end

    synced_orgs = Set.new

    batch.each do |org_membership|
      beta = betas.find { |beta| beta.feature_slug == org_membership.feature_slug }
      batch_early_access_org_to_member_ids[org_membership.member_id] ||= []

      org_member_ids = org_membership.member.member_ids
      early_access_member_ids = batch_early_access_org_to_member_ids[org_membership.member_id]
      new_org_member_ids = org_member_ids - early_access_member_ids
      new_eligible_org_member_ids = T.let([], T::Array[Integer])
      new_org_member_ids.in_groups_of(1000) do |batch|
        User.where(id: batch).each do |member|
          if beta.can_inherit_org_membership?(member)
            new_eligible_org_member_ids << member.id
          end
        end
      end

      removed_member_ids = early_access_member_ids - org_member_ids

      if !synced_orgs.include?(org_membership.member_id) && (new_eligible_org_member_ids.any? || removed_member_ids.any?)
        synced_orgs.add(org_membership.member_id)
        log("Memberships are out of sync, triggering InheritOrgEarlyAccessJob", org_membership.feature_slug, org_membership)
        InheritOrgEarlyAccessJob.perform_later(org_membership)
      end
    end
  end

  sig { params(message: String, feature_slug: T.untyped, org_membership: T.untyped, member: T.untyped).void }
  def log(message, feature_slug, org_membership, member: nil)
    GitHub.logger.info("sync_inherited_org_early_access_memberships: #{message}",
      "gh.member.id" => org_membership.member&.id,
      "gh.org.name" => org_membership.member&.name,
      "gh.feature.slug" => feature_slug,
      "feature_enabled" => org_membership.feature_enabled,
    )
  end
end
