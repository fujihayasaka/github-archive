# typed: true
# frozen_string_literal: true

class AssignStafftoolsAccessJob < ApplicationJob
  queue_as :assign_stafftools_access
  retry_on_dirty_exit

  SECURITY_USER = "thechickeneater"

  def self.attempt_to_enqueue(desired_state)
    current_users = User.where(gh_role: "staff").pluck(:login)
    users_to_add, users_to_remove = user_changes(desired_state, current_users)
    unpermitted_users = invalid_users_in_job_check(users_to_add)

    return { errors: unpermitted_users } if unpermitted_users.any?

    {
      job: perform_later(users_to_add, users_to_remove),
      users_added_count: users_to_add.length,
      users_removed_count: users_to_remove.length,
    }
  end

  def self.grant_stafftools_access(user)
    ActiveRecord::Base.connected_to(role: :writing) do
      user.grant_site_admin_access("Added via api")
    end
    GitHub.dogstats.increment("entitlements.api.grant_stafftools_access")
  end

  def self.revoke_stafftools_access(user)
    ActiveRecord::Base.connected_to(role: :writing) do
      user.revoke_privileged_access("Removed via api")
    end
    GitHub.dogstats.increment("entitlements.api.revoke_stafftools_access")
  end

  def perform(users_to_add, users_to_remove)
    User.with_logins(users_to_add).find_each(batch_size: 50) do |user|
      self.class.grant_stafftools_access(user)
    end

    User.with_logins(users_to_remove).find_each(batch_size: 50) do |user|
      self.class.revoke_stafftools_access(user)
    end
  end

  def self.invalid_users_in_job_check(users_to_add)
    # We currently validate for this, however the validation is never reached because the
    # grant_site_admin_access function short circuits the staff assignment so we do
    # not get the error on the model. This means we have validation messages sprinkled
    # here and in the stafftools user controller, it would be better IMO to just use the
    # built in activerecord validation so this is all in one place.

    invalid_users = []
    User.with_logins(users_to_add).find_each(batch_size: 50) do |user|
      invalid_users << user unless user.can_become_staff?
    end
    invalid_users
  end

  def self.user_changes(new_users, current_users)
    # LDAP is case insensitive, so we may encounter casing issues, shove everything to downcase.
    new_users = new_users.map(&:downcase)
    users_to_add = new_users - current_users.map(&:downcase)
    users_to_remove = current_users.reject { |u| new_users.include?(u.downcase) }
    users_to_add, user_to_remove = adjust_for_hardcoded_users(users_to_remove, users_to_add)
    [users_to_add, users_to_remove]
  end

  def self.adjust_for_hardcoded_users(users_to_remove, users_to_add)
    users_to_remove.delete(SECURITY_USER)
    users_to_add.delete(SECURITY_USER)
    [users_to_add, users_to_remove]
  end
end
