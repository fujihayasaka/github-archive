# typed: true
# frozen_string_literal: true

# Internal: Belongs to a Restorable and stores the watched repository settings
# for a user. The user association is stored on a Restorable scenario class
# like Restorable::OrganizationUser.
#
# Usage:
#
#  > user = User.find_by_login("lizzhale")
#  > repo = Repository.with_name_with_owner("github/linguist")
#  > restorable = Restorable.create
#
#  > Restorable::WatchedRepository.backup(:restorable => restorable, :repositories => [repo])
#  > Restorable::WatchedRepository.restore(:restorable => restorable, :user => user)
#
# This class and all of its methods should only ever be used by other
# Restorable classes and specifically Restorable scenario classes/models like
# Restorable::OrganizationUser.
class Restorable
  class WatchedRepository < ApplicationRecord::Domain::Restorables

    # A set of common restorable type model helper methods.
    extend TypeHelpers

    belongs_to :restorable

    scope :watched, -> { where(ignored: false) }
    scope :ignored, -> { where(ignored: true) }

    validates_presence_of :restorable_id, :repository_id
    validates_uniqueness_of :restorable_id, scope: :repository_id

    # Internal: Create a set of watched_repository records.
    #
    # restorable - Restorable parent instance.
    # repositories - An array of Repositories.
    def self.backup(restorable:, repositories:)
      save_models(restorable, repositories)
    end

    # Internal: Restore watched repositories for this user.
    #
    # restorable - Restorable parent instance.
    # user - User instance.
    def self.restore(restorable:, user:)
      restorable.restoring(:restorable_watched_repositories)

      measure_restore_time do
        watched_ids = restorable.watched_repositories.watched.pluck(:repository_id)
        ::Repository.where(id: watched_ids).find_each do |repository|
          subscribe_to_list(user, repository)
        end

        ignored_ids = restorable.watched_repositories.ignored.pluck(:repository_id)
        ::Repository.where(id: ignored_ids).find_each do |repository|
          ignore_list(user, repository)
        end
      end

      restorable.restored(:restorable_watched_repositories)
    end

    # Internal: Bulk insert sql.
    #
    # Returns a String.
    def self.insert_ignore_sql
      <<-SQL
        INSERT IGNORE INTO
          restorable_watched_repositories
          (restorable_id,repository_id,ignored)
        :values
      SQL
    end

    # Internal: Create an array with needed values from models.
    #
    # restorable_id - Integer id of Restorable.
    # repositories - Array of repositories.
    #
    # Returns an Array of Arrays, each [Integer, Integer, Boolean]
    def self.values(restorable_id, repositories)
      repositories.map do |repository|
        repository.extend(WatchedRepositories::SubscriptionDetails)
        [
          restorable_id, # restorable_id
          repository.id, # repository_id
          repository.ignored, # ignored
        ]
      end
    end

    def self.subscribe_to_list(user, repository)
      response = GitHub.newsies.subscribe_to_list(user, repository)

      if response.failed?
        # not sure this is ever called. See https://github.com/github/wall-e-idempotent-jobs/issues/33
        SubscribeToListNotificationsJob.perform_later(user.id, repository.id)
      end
    end

    def self.ignore_list(user, repository)
      response = GitHub.newsies.ignore_list(user, repository)

      if response.failed?
        # not sure this is ever called. See https://github.com/github/wall-e-idempotent-jobs/issues/48
        IgnoreListNotificationsJob.perform_later(user.id, repository.id)
      end
    end

    # Internal: The metric name for statsd.
    #
    # Returns a Symbol.
    def self.metric_name
      :watched_repository
    end
  end
end
