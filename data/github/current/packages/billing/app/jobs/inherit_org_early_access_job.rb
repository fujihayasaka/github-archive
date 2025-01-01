# typed: true
# frozen_string_literal: true

# This job creates an early access membership for every organization member
# This job is triggered when an organization is granted early access to a feature that is listed in INHERIT_EARLY_ACCESS list
class InheritOrgEarlyAccessJob < ApplicationJob

  queue_as :inherit_org_early_access
  retry_on_dirty_exit

  locked_by timeout: 5.minutes, key: ->(job) {
    job.arguments[0].member_id
  }

  MAX_THROTTLE_RETRIES = 5

  INHERIT_EARLY_ACCESS_BETAS = T.let([
    Copilot::CodeReviewBeta.new
  ], T::Array[T.untyped])

  sig { params(org_membership: EarlyAccessMembership).void }
  def perform(org_membership)
    return if org_membership.member.nil?
    return unless org_membership.member&.organization?

    org = org_membership.member
    beta = INHERIT_EARLY_ACCESS_BETAS.find { |beta| beta.feature_slug == org_membership.feature_slug }

    # making sure we don't create duplicate memberships on multiple job runs
    existing_memberships_via_org_ids = EarlyAccessMembership
      .where(
        parent_id: org_membership.id,
        feature_slug: beta.feature_slug)
      .pluck(:member_id).to_set

    existing_individual_membership_ids = Set.new

    # if the user signed up themselves, we don't want to revoke access so we update existing memberships only if org was onboarded
    if org_membership.feature_enabled?
      existing_individual_membership_ids = EarlyAccessMembership
        .where(
          member: org.members,
          feature_slug: beta.feature_slug,
          parent_id: 0)
        .pluck(:member_id).to_set
    end

    # statistics for logging
    created = T.let([], T::Array[EarlyAccessMembership])
    updated = T.let([], T::Array[EarlyAccessMembership])
    skipped = 0
    failed = 0

    with_write do
      EarlyAccessMembership.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES, skip_reporting: true) do
        org_member_ids = org.member_ids.to_set
        removed_org_member_ids = T.let([], T::Array[Integer])
        # remove memberships for users that are no longer in the org
        existing_memberships_via_org_ids.each do |member_id|
          # member has been removed from the org, removing inherited membership
          if !org_member_ids.include?(member_id)
            removed_org_member_ids << member_id
          end
        end

        memberships_to_destroy = EarlyAccessMembership.where(
          member_id: removed_org_member_ids,
          feature_slug: org_membership.feature_slug,
          parent_id: org_membership.id)

        memberships_to_destroy.destroy_all
        log("Removed inherited early access memberships, count: #{removed_org_member_ids.length}, ids (only first 100 are logged): #{removed_org_member_ids.first(100)}", beta, org_membership)

        existing_nomination_ids = []
        # add missing memberships
        org_member_ids.to_a.in_groups_of(1000) do |batch|
          User.where(id: batch).each do |member|
            if !beta.respond_to?(:can_inherit_org_membership?) || !beta.can_inherit_org_membership?(member)
              log("Skippping creation of inherited early access membership", beta, org_membership, member: member)
              skipped += 1
              next
            end

            # user may have been nominated via org already
            if existing_memberships_via_org_ids.include?(member.id)
              existing_nomination_ids << member.id
            end

            # user may have been nominated by themselves
            if existing_individual_membership_ids.include?(member.id)
              existing_nomination_ids << member.id
            end

            # if the org was off-boarded from the beta, we don't want to create new memberships
            next unless org_membership.feature_enabled?

            membership = EarlyAccessMembership.new(
              member_id: member.id,
              actor_id: member.id,
              feature_slug: beta.feature_slug,
              survey: beta.survey,
              feature_enabled: true,
              parent_id: org_membership.id,
            )
            success = membership.save

            if success
              created += [membership]
              log("Created inherited early access membership", beta.feature_slug, org_membership, member: member)
            else
              log("Failed to create inherited early access membership", beta, org_membership, member: member)
              failed += 1
            end
          end
        end

        memberships_to_update = EarlyAccessMembership.where(
          member_id: existing_nomination_ids,
          feature_slug: org_membership.feature_slug,
          feature_enabled: !org_membership.feature_enabled)

        memberships_to_update = memberships_to_update.where(parent_id: org_membership.id).or(memberships_to_update.where(parent_id: 0))
        memberships_to_update_a = memberships_to_update.to_a
        memberships_to_update.update_all(feature_enabled: org_membership.feature_enabled)

        updated += memberships_to_update_a
      end

      # we don't want to send emails to members when:
      # - the org was off-boarded from the beta
      # - the org is added to the feature flag that enables skipping onboarding emails
      should_send_emails = org_membership.feature_enabled? && !GitHub.flipper[:copilot_code_review_public_preview_skip_organization_onboarding_email].enabled?(org)
      notify_members = created + updated
      notify_members.each do |membership|
        unless org.adminable_by?(membership.member)
          if should_send_emails && beta.respond_to?(:mailer) && beta.mailer.respond_to?(:individual_waitlist_acceptance)
            beta.mailer.individual_waitlist_acceptance(membership).deliver_later
          end
        end

        GitHub.dogstats.increment("copilot.code_review_beta.onboard")
        GlobalInstrumenter.instrument("user.beta_feature.enroll",
          actor: membership.actor,
          member: membership.member,
          action: "enroll",
          feature: "copilot_code_review_public_preview",
        )
      end
    end

    log("Created #{created.length}, updated #{updated.length}, skipped #{skipped}, failed to create/update #{failed} memberships", beta, org_membership)
  end

  def log(message, feature_slug, org_membership, member: nil)
    GitHub.logger.info("inherit_early_access: #{message}",
      "gh.member.id" => member&.id,
      "gh.org.name" => org_membership.member&.name,
      "gh.feature.slug" => feature_slug,
      "feature_enabled" => org_membership.feature_enabled,
    )
  end
end
