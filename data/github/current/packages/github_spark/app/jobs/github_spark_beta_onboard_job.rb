# typed: strict
# frozen_string_literal: true

class GitHubSparkBetaOnboardJob < ApplicationJob
  # Don't run more than one of this job at a time with the same args
  locked_by timeout: 1.hour, key: DEFAULT_LOCK_PROC

  queue_as :mailers
  retry_on_dirty_exit

  MAX_THROTTLE_RETRIES = 4
  MAX_BATCH_QUERIES = 3

  sig { params(user_logins: T::Array[::User], batch_size: T.nilable(Integer)).void }
  def perform(user_logins, batch_size: nil)
    spark_waitlist = EarlyAccessMembership.github_spark_waitlist

    users = if batch_size.nil?
      ::User.where(login: user_logins)
    else
      get_batched_users(spark_waitlist, batch_size)
    end
    return if users.empty?

    memberships = spark_waitlist.where(member: users, feature_enabled: false)
    memberships_array = memberships.to_a # need this because update_all call later changes memberships
    return if memberships.empty?

    with_write do
      # Note that the early_access_enabled flipper group is added to copilot_next_edit_suggestions feature flag.
      # As such, we don't need to explicitly flip the flag on each user.
      # Setting feature_enabled: true will get them into the early_access_enabled group for this ff.
      EarlyAccessMembership.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
        memberships.update_all(feature_enabled: true)
      end
    end

    memberships_array.each do |membership|
      GitHubSparkBetaMembershipMailer.waitlist_acceptance(membership).deliver_later

      GitHub.dogstats.increment("copilot.spark.onboard")
      GlobalInstrumenter.instrument("user.beta_feature.enroll",
        actor: membership.member,
        action: "enroll",
        feature: "github_spark",
      )
    end
  end

  private

  sig { params(spark_waitlist: ActiveRecord::Relation, batch_size: Integer).returns(T::Array[::User]) }
  def get_batched_users(spark_waitlist, batch_size)
    batched_users = []

    # If we don't fill up the batch size in MAX_BATCH_QUERIES random samples, just return what we have
    MAX_BATCH_QUERIES.times do
      user_ids = spark_waitlist
        .where(feature_enabled: false)
        .where.not(member_id: batched_users.map(&:id))
        .order("RAND()")
        .limit(batch_size)
        .pluck(:member_id)

      ::User.where(id: user_ids).each do |user|
        # Exclude trade-restricted/spammy users
        if user.is_enterprise_managed? || user.spammy? || user.has_any_trade_restrictions?
          GitHub.dogstats.increment(
            "copilot.spark.onboard_blocked",
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
