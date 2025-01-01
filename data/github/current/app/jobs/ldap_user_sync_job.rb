# typed: true
# frozen_string_literal: true

class LdapUserSyncJob < ApplicationJob
  queue_as :ldap_user_sync

  # This timeout is the amount of time that the lock will be kept
  # whether the job completes or not. It is set to a very long
  # value (2 days) to assure that jobs don't stack up under normal
  # circumstances.
  locked_by timeout: 48.hours + 1.minute, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  schedule interval: GitHub.ldap_user_sync_interval.hours, condition: -> {
    LdapUserSyncJob.enabled?
  }

  def self.enabled?
    GitHub.enterprise? && GitHub.ldap_sync_enabled?
  end

  # Public: Sync user given by `user_id` or all users.
  #
  # Emits `ldap_user_sync.perform` event with:
  #  :count - number of users synced
  def perform(user_id = nil)
    return unless LdapUserSyncJob.enabled?

    iterator =
      if user_id
        User.find(user_id)
      else
        User.where("type = 'User' and id != ?", [User.ghost.id]).in_batches(of: 1000)
      end

    GitHub.instrument "ldap_user_sync.perform" do |payload|
      payload[:count] = 0
      sync = GitHub::LDAP::UserSync.new

      if iterator.instance_of? User
        with_write { sync.perform(iterator) }
        payload[:count] += 1
      else
        iterator.each_record do |user|
          with_write { sync.perform(user) }
          payload[:count] += 1
        end
      end
    end
  end
end
