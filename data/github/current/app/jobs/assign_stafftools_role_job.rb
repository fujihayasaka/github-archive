# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class AssignStafftoolsRoleJob < ApplicationJob
  queue_as :assign_stafftools_access
  retry_on_dirty_exit

  def perform(users_to_add, users_to_remove, role_id)
    role = StafftoolsRole.find(role_id)
    ::User.with_logins(users_to_add).find_each(batch_size: 50) do |user|
      self.class.assign_stafftools_role(user, role)
    end

    ::User.with_logins(users_to_remove).find_each(batch_size: 50) do |user|
      self.class.revoke_stafftools_role(user, role)
    end
  end

  def self.assign_stafftools_role(user, role)
    return if user.stafftools_roles.exists?(role.id)

    ActiveRecord::Base.connected_to(role: :writing) { user.stafftools_roles << role }
    GitHub.dogstats.increment("entitlements.api.grant_stafftools_role")
  end

  def self.revoke_stafftools_role(user, role)
    ActiveRecord::Base.connected_to(role: :writing) { user.stafftools_roles.delete(role) }
    GitHub.dogstats.increment("entitlements.api.revoke_stafftools_role")
  end

  def self.attempt_to_queue(desired_state, role)
    current_users = role.users.pluck(:login)
    users_to_add, users_to_remove = user_changes(desired_state, current_users)
    unpermitted_users = invalid_users_in_job_check(users_to_add, role)

    return { errors: unpermitted_users } if unpermitted_users.any?

    {
      job: ::AssignStafftoolsRoleJob.perform_later(users_to_add, users_to_remove, role.id),
      users_added_count: users_to_add.length,
      users_removed_count: users_to_remove.length,
    }
  end

  def self.invalid_users_in_job_check(users_to_add, role)
    invalid_users = []
    ::User.with_logins(users_to_add).find_each(batch_size: 50) do |user|
      role_join = UserStafftoolsRole.new(user: user, stafftools_role: role)
      invalid_users << user unless role_join.valid?
      nil
    end
    invalid_users
  end
  private_class_method :invalid_users_in_job_check

  def self.user_changes(new_users, current_users)
    # LDAP is case insensitive, so we may encounter casing issues, shove everything to downcase.
    new_users = new_users.map(&:downcase)
    users_to_add = new_users - current_users.map(&:downcase)
    users_to_remove = current_users.reject { |u| new_users.include?(u.downcase) }
    [users_to_add, users_to_remove]
  end
  private_class_method :user_changes
end
