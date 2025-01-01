# typed: true
# frozen_string_literal: true


class BitbucketServerMigrationsOnboardWaitlistUserJob < ApplicationJob
  queue_as :mailers
  retry_on_dirty_exit

  MAX_THROTTLE_RETRIES = 4

  def perform(user_logins)
    users = User.where(login: user_logins)
    return if users.empty?

    email_eligible = Set.new
    users.each do |user|
      email_eligible << onboard_user(user)
    end

    memberships = EarlyAccessMembership.bitbucket_server_migrations_waitlist.where(member: email_eligible)

    ActiveRecord::Base.connected_to(role: :writing) do
      EarlyAccessMembership.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
        memberships.update_all(feature_enabled: true)
      end
    end

    memberships.each { |m| BitbucketServerMigrationsBetaMembershipMailer.waitlist_acceptance(m).deliver_later }
  end

  def onboard_user(user)
    should_email = !GitHub.flipper[:octoshift_bitbucket_server].enabled?(user)

    ActiveRecord::Base.connected_to(role: :writing) do
      FlipperGate.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
        GitHub.flipper[:octoshift_bitbucket_server].enable(user)
      end
    end
    user if should_email
  end
end
