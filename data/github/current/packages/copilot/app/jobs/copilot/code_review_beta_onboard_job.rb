# typed: strict
# frozen_string_literal: true

module Copilot
  class CodeReviewBetaOnboardJob < ApplicationJob

    MAX_THROTTLE_RETRIES = 4
    locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC

    MAX_BATCH_QUERIES = 3

    queue_as :mailers
    retry_on_dirty_exit

    # When onboarding a business, onboard_entity will be a EarlyAccessMembership. Otherwise, it will be an array of logins
    sig { params(onboard_entity: T.any(EarlyAccessMembership, T::Array[String]), batch_size: T.nilable(Integer), actor: T.nilable(::User)).void }
    def perform(onboard_entity, batch_size: nil, actor: nil)
      # Business case: Copilot Code Review waitlist does not support business onboarding
      return if onboard_entity.is_a?(EarlyAccessMembership)
      # Organization/User case
      copilot_code_review_waitlist = EarlyAccessMembership.copilot_code_review_waitlist

      users_and_orgs = if batch_size.nil?
        get_selected_users(onboard_entity)
      else
        get_batched_users(copilot_code_review_waitlist, batch_size)
      end

      return if users_and_orgs.empty?

      orgs = users_and_orgs.select { |u| u.organization? }
      users = users_and_orgs - orgs

      ## Retrieving users that are on the waitlist
      user_memberships = copilot_code_review_waitlist
                      .where(member: users)
                      .where(feature_enabled: false)
                      .includes(:member)
      user_membership_array = user_memberships.to_a
      waitlisted_user_ids = user_memberships.pluck(:member_id)

      # Retrieving users that are already enrolled
      enrolled_user_ids = copilot_code_review_waitlist
        .where(member: users)
        .where(feature_enabled: true)
        .pluck(:member_id)


      ## Retrieving users that are not on the waitlist
      non_waitlisted_users = users.reject do |u|
        waitlisted_user_ids.include?(u.id) || enrolled_user_ids.include?(u.id)
      end

      ## Retrieving orgs that are on the waitlist
      org_memberships = copilot_code_review_waitlist
                      .where(member: orgs)
                      .where(feature_enabled: false)
                      .includes(:member)

      org_membership_array = org_memberships.to_a
      waitlisted_org_ids = org_memberships.pluck(:member_id)

      # Retrieving orgs that are already enrolled
      enrolled_org_ids = copilot_code_review_waitlist
        .where(member: orgs)
        .where(feature_enabled: true)
        .pluck(:member_id)

      ## Retrieving orgs that are not on the waitlist
      non_waitlisted_orgs = orgs.reject do |o|
        waitlisted_org_ids.include?(o.id) || enrolled_org_ids.include?(o.id)
      end

      return if user_membership_array.empty? &&
        org_membership_array.empty? &&
        non_waitlisted_users.empty? &&
        non_waitlisted_orgs.empty?

      created = T.let([], T::Array[EarlyAccessMembership])
      updated = T.let([], T::Array[EarlyAccessMembership])

      with_write do
        # Note that the early_access_enabled flipper group is added to copilot_code_review_public_preview feature flag.
        # As such, we don't need to explicitly flip the flag on each user.
        # Setting feature_enabled: true will get them into the early_access_enabled group for this ff.
        EarlyAccessMembership.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
          user_memberships.update_all(feature_enabled: true)
        end

        updated = user_membership_array
        # If a user is not on the waitlist, we need to create a new membership for them
        beta = Copilot::CodeReviewBeta.new
        non_waitlisted_users.each do |user|
          membership = EarlyAccessMembership.new(
            member_id: user.id,
            actor_id: actor&.id,
            feature_slug: beta.feature_slug,
            survey: beta.survey,
            feature_enabled: true,
            can_onboard: true,
          )
          success = membership.save
          if success
            created << membership
          end
          log_outcome(membership, success)
        end

        # Onboarding waitlisted orgs
        org_memberships.to_a.each do |membership|
          success = membership.update(feature_enabled: true)
          if success
            updated << membership
          end
          log_outcome(membership, success)
        end

        # Onboarding non-waitlisted orgs
        non_waitlisted_orgs.each do |org|
          membership = EarlyAccessMembership.new(
            member_id: org.id,
            actor_id: actor&.id,
            feature_slug: beta.feature_slug,
            survey: beta.survey,
            feature_enabled: true,
            can_onboard: true,
          )
          success = membership.save
          if success
            created << membership
          end
          log_outcome(membership, success)
        end


        notify_members = created + updated
        notify_members.each do |membership|
          send_emails(membership)
          log_outcome(membership, true)

          GitHub.dogstats.increment("copilot.code_review_beta.onboard")
          GlobalInstrumenter.instrument("user.beta_feature.enroll",
            actor: membership.actor,
            member: membership.member,
            action: "enroll",
            feature: "copilot_code_review_public_preview",
          )
        end
      end
    end

    private

    sig { params(copilot_code_review_waitlist: ActiveRecord::Relation, batch_size: Integer).returns(T::Array[::User]) }
    def get_batched_users(copilot_code_review_waitlist, batch_size)
      batched_users = []

      # If we don't fill up the batch size in MAX_BATCH_QUERIES random samples, just return what we have
      MAX_BATCH_QUERIES.times do
        user_ids = copilot_code_review_waitlist
          .where(feature_enabled: false)
          .where.not(member_id: batched_users.map(&:id))
          .order("RAND()")
          .limit(batch_size)
          .pluck(:member_id)

        ::User.where(id: user_ids).each do |user|
          next unless user_is_eligible?(user)

          batched_users << user unless batched_users.include?(user)
          return batched_users if batched_users.length >= batch_size
        end
      end

      batched_users
    end

    sig { params(selected_logins: T::Array[String]).returns(T::Array[::User]) }
    def get_selected_users(selected_logins)
      ::User.where(login: selected_logins).select { user_is_eligible?(_1) }.to_a
    end

    sig { params(user: ::User).returns(T::Boolean) }
    def user_is_eligible?(user)
      if user.organization?
        org = T.cast(user, ::Organization)
        copilot_org = Copilot::Organization.new(org)
        return copilot_org.copilot_enabled? || copilot_org.has_trial?
      end

      return false if user.spammy? || user.has_any_trade_restrictions?

      copilot_user = Copilot::Public::User.new(user)
      return false unless copilot_user.has_ci_access?

      true
    end

    sig { params(membership: EarlyAccessMembership).void }
    def send_emails(membership)
      onboarded_entity = T.cast(membership.member, T.any(::User, ::Organization))

      case onboarded_entity
      when ::Organization
        return if GitHub.flipper[:copilot_code_review_public_preview_skip_organization_onboarding_email].enabled?(onboarded_entity)
        onboarded_entity.admins.each do |admin|
          CopilotCodeReviewBetaMailer.organization_waitlist_acceptance(membership, admin).deliver_later
        end
      when ::User
        CopilotCodeReviewBetaMailer.individual_waitlist_acceptance(membership).deliver_later
      else
        T.absurd(onboarded_entity)
      end
    end

    sig { params(membership: EarlyAccessMembership, success: T::Boolean).void }
    def log_outcome(membership, success)
      member_data = {
        "gh.#{membership.member.class.name&.downcase}.id" => membership.member.id,
        "gh.#{membership.member.class.name&.downcase}.name" => membership.member.display_login,
      }

      if success
        GitHub.logger.info("#{membership.member.class} onboarded to Copilot Code Review Beta", member_data)
      else
        GitHub.logger.info("Failed to onboard #{membership.member.class} to Copilot Code Review Beta", member_data)
      end
    end
  end
end
