# typed: true
# frozen_string_literal: true

class CodeSearchCodeViewOnboardJob < ApplicationJob
  queue_as :blackbird
  retry_on_dirty_exit

  MAX_THROTTLE_RETRIES = 4

  def perform(user_logins)
    # NOTE: May be either a user or an organization.
    owners = User.where(login: user_logins)

    return if owners.empty?

    # We only email users that don't have feature access
    email_eligible = Set.new
    onboarded_repo_ids = Set.new

    # Onboard each owner and all their repos and all their users (for orgs)
    owners.each do |owner|
      users_to_email = onboard_owner(owner, onboarded_repo_ids)
      email_eligible.merge(users_to_email.reject(&:nil?))
    end

    # Sending emails for users who are on the waitlist
    memberships = EarlyAccessMembership.code_search_code_view_waitlist.where(member: email_eligible)

    ActiveRecord::Base.connected_to(role: :writing) do
      EarlyAccessMembership.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
        memberships.update_all(feature_enabled: true)
      end
    end

    memberships.each do |membership|
      CodeSearchCodeViewMailer.waitlist_acceptance(membership).deliver_later(wait: 1.hour)
    end
  end

  # Onboard a user or org.
  #
  # Returns a Set of users that may be emailed.
  def onboard_owner(owner, onboarded_repo_ids)
    email_eligible = Set.new
    if owner.organization?
      email_eligible.merge(onboard_org(owner, onboarded_repo_ids))
    else
      email_eligible << onboard_user(owner, onboarded_repo_ids)
    end
    email_eligible
  end

  # Onboard an organization into blackbird code search by enabling the
  # blackbird_fe feature flag on the org (so all members get access) and
  # onboarding all members (to index their repositories).
  #
  # Returns an Array of users that may be emailed.
  def onboard_org(org, onboarded_repo_ids)
    onboard_repos(actor: org, account: org, onboarded_repo_ids: onboarded_repo_ids)

    email_eligible = []
    org.members.each do |member|
      email_eligible << onboard_user(member, onboarded_repo_ids)
    end

    email_eligible
  end

  # Onboard a user into blackbird code search by enabling the feature flag on
  # their account and submitting all their repositories for indexing.
  #
  # Returns the user if they can be emailed, or nil otherwise.
  def onboard_user(user, onboarded_repo_ids)
    # Only email users that don't have feature access already
    email = !GitHub.flipper[:code_search_code_view].enabled?(user)

    ActiveRecord::Base.connected_to(role: :writing) do
      FlipperGate.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
        GitHub.flipper[:blackbird_fe].enable(user)
        user.enable_feature_preview(:code_search_code_view)
      end
    end

    if email
      user
    end
  end

  # Onboard all repositories not in onboarded_repo_ids owned by a user/org to be indexed for blackbird
  # code search. Adds all onboarded repositories to onboarded_repo_ids.
  def onboard_repos(actor:, account:, onboarded_repo_ids:)
    account.repositories.each do |repo|
      next if onboarded_repo_ids.include?(repo.id)

      GlobalInstrumenter.instrument("blackbird.repository.onboard",
        actor: actor,
        repository: repo,
      )

      onboarded_repo_ids << repo.id
    end
  end
end
