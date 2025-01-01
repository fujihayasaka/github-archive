# typed: strict
# frozen_string_literal: true

class ModelsBetaOnboardJob < ApplicationJob
  extend T::Sig
  # Don't run more than one of this job at a time with the same args
  locked_by timeout: 1.hour, key: DEFAULT_LOCK_PROC

  queue_as :mailers
  retry_on_dirty_exit

  MAX_THROTTLE_RETRIES = 4
  MAX_BATCH_QUERIES = 3

  sig { params(user_logins: T::Array[::User], batch_size: T.nilable(Integer)).void }
  def perform(user_logins, batch_size: nil)
    project_neutron_playground_waitlist = EarlyAccessMembership.project_neutron_playground_waitlist

    users = if batch_size.nil?
      ::User.where(login: user_logins)
    else
      get_batched_users(project_neutron_playground_waitlist, batch_size)
    end
    return if users.empty?

    memberships = project_neutron_playground_waitlist.where(member: users, feature_enabled: false)
    memberships_array = memberships.to_a # need this because update_all call later changes memberships
    return if memberships.empty?

    with_write do
      # Note that the early_access_enabled flipper group is added to project_neutron_playground feature flag.
      # As such, we don't need to explicitly flip the flag on each user.
      # Setting feature_enabled: true will get them into the early_access_enabled group for this ff. It's magic.
      EarlyAccessMembership.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
        memberships.update_all(feature_enabled: true)
      end
    end

    memberships_array.each do |membership|
      ProjectNeutronBetaMembershipMailer.waitlist_acceptance(membership).deliver_later

      GitHub.dogstats.increment("project_neutron_playground.onboard")

      GlobalInstrumenter.instrument("user.beta_feature.enroll",
        actor: membership.member,
        action: "enroll",
        feature: "project_neutron_playground",
      )
    end
  end

  private

  sig { params(project_neutron_playground_waitlist: ActiveRecord::Relation, batch_size: Integer).returns(T::Array[::User]) }
  def get_batched_users(project_neutron_playground_waitlist, batch_size)
    batched_users = []

    # If we don't fill up the batch size in MAX_BATCH_QUERIES random samples, just return what we have
    MAX_BATCH_QUERIES.times do
      user_ids = project_neutron_playground_waitlist
        .where(feature_enabled: false)
        .where.not(member_id: batched_users.map(&:id))
        .order("RAND()")
        .limit(batch_size)
        .pluck(:member_id)

      ::User.where(id: user_ids).each do |user|
        if GitHub.flipper[:project_neutron_waitlist_trusted_only].enabled?
          # For now, we only want to onboard the safest tier of accounts
          next unless TrustTiers::Tier.for_billable_owner(user).tier <= TrustTiers::Tier::TRUSTED
          # And even then we don't trust new accounts
          next unless user.created_at < 3.months.ago
        end

        # Exclude trade-restricted/spammy users
        if user.spammy? || user.has_any_trade_restrictions?
          GitHub.dogstats.increment(
            "project_neutron_playground.onboard_blocked",
            tags: ["in_batch:#{batch_size.present?}"]
          )
          next
        end

        batched_users << user unless batched_users.include?(user)
        return batched_users if batched_users.length >= batch_size
      end
    end

    batched_users
  end
end
