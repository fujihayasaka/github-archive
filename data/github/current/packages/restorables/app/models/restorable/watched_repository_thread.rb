# typed: true
# frozen_string_literal: true

# Internal: Belongs to a Restorable and stores the watched repository thread settings
# for a user. The user association is stored on a Restorable scenario class
# like Restorable::OrganizationUser.
#
# Usage:
#
#  > user = User.find_by_login("smashwilson")
#  > thread_sub = Restorables::WatchedRepositoryThreadSubscription.new(
#  >   user_id: user.id,
#  >   ignored: false,
#  >   reason: "team_mention",
#  >   thread_key: "Release;456"
#  > )
#  > restorable = Restorable.create
#  >
#  > Restorable::WatchedRepositoryThread.backup(restorable: restorable, threads: [thread_sub])
#
# This class and all of its methods should only ever be used by other Restorable classes and specifically Restorable
# scenario classes/models like Restorable::VisibilityChangedRepository.
class Restorable
  class WatchedRepositoryThread < ApplicationRecord::Domain::Restorables

    # A set of common restorable type model helper methods.
    extend TypeHelpers

    belongs_to :restorable
    belongs_to :user

    validates_presence_of :restorable_id, :user_id

    # Internal: Create a set of watched_repository_thread records.
    #
    # restorable - Restorable parent instance.
    # threads - An array of Restorables::WatchedRepositoryThreadSubscription instances.
    def self.backup(restorable:, threads:)
      save_models(restorable, threads)
    end

    # Internal: Bulk insert sql.
    #
    # Returns a String.
    def self.insert_ignore_sql
      <<-SQL
        INSERT IGNORE INTO
          restorable_watched_repository_threads
          (restorable_id,user_id,ignored,reason,thread_key)
        :values
      SQL
    end

    # Internal: Create an array with needed values from models.
    #
    # restorable_id - Integer id of Restorable.
    # threads - Array of Restorables::WatchedRepositoryThreadSubscription instances.
    #
    # Returns an Array of Arrays, each [Integer, Integer, Boolean, String, String]
    def self.values(restorable_id, threads)
      threads.map do |thread|
        [
          restorable_id, # restorable_id
          thread.user_id, # user_id
          thread.ignored, # ignored
          thread.reason, # reason
          thread.thread_key, # thread_key
        ]
      end
    end

    # Internal: The metric name for statsd.
    #
    # Returns a Symbol.
    def self.metric_name
      :watched_repository_thread
    end

    RESTORE_PREREQ_TYPES = %i[restorable_watched_repositories restorable_custom_watched_repositories]

    # Begin WatchedRepositoryThread recovery only once WatchedRepository and CustomWatchedRepository recovery
    # are all complete. This is necessary because WatchedRepositoryThread subscriptions can depend on the state
    # of other kinds of subscriptions.
    def self.ready_to_restore(restorable:)
      restorable&.restored?(RESTORE_PREREQ_TYPES) && restorable.saved?([:restorable_watched_repository_threads])
    end

    # Internal: Enqueue a job to restore watched repository thread subscriptions.
    #
    # restorable - Restorable parent instance.
    #
    # Returns nothing.
    def self.restore(restorable:)
      restorable.restoring(:restorable_watched_repository_threads)
      RecoverRestorableWatchedRepositoryThreadsJob.perform_later(restorable_id: restorable.id)
    end
  end
end
