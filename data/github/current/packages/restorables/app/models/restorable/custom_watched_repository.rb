# typed: strict
# frozen_string_literal: true

# Internal: Belongs to a Restorable and stores the custom watched repository settings
# for a user. The user association is stored on a Restorable scenario class
# like Restorable::VisibilityChangedRepository.
#
# Usage:
#
#  > user = User.find_by_login("smashwilson")
#  > repo = Repository.with_name_with_owner("github/stabilize")
#  > restorable = Restorable.create!
#  > subscription = Restorables::CustomWatchedRepositorySubscription.new(
#      user_id: user.id,
#      thread_type: "Discussion",
#      original_created_at: Time.current
#    )
#
#  > Restorable::CustomWatchedRepository.backup(restorable: restorable, subscriptions: [subscription])
#  > Restorable::CustomWatchedRepository.restore(restorable: restorable, user: user)
#
# This class and all of its methods should only ever be used by other
# Restorable classes and specifically Restorable scenario classes/models like
# Restorable::VisibilityChangedRepository.
class Restorable
  class CustomWatchedRepository < ApplicationRecord::Domain::Restorables

    # A set of common restorable type model helper methods.
    extend TypeHelpers

    belongs_to :restorable
    belongs_to :user

    # Internal: Create a set of custom_watched_repository records.
    #
    # restorable - Restorable parent instance.
    # subscriptions - An array of Restorables::CustomWatchedRepositorySubscription.
    sig do
      params(
        restorable: Restorable,
        subscriptions: T::Array[Restorables::CustomWatchedRepositorySubscription],
      ).void
    end
    def self.backup(restorable:, subscriptions:)
      save_models(restorable, subscriptions)
    end

    # Internal: Bulk insert sql.
    #
    # Returns a String.
    sig { returns(String) }
    def self.insert_ignore_sql
      <<-SQL
        INSERT IGNORE INTO
          restorable_custom_watched_repositories
          (restorable_id,user_id,thread_type,original_created_at)
        :values
      SQL
    end

    # Internal: Create an array with needed values from models.
    sig do
      params(restorable_id: Integer, subscriptions: T::Array[Restorables::CustomWatchedRepositorySubscription])
        .returns(T::Array[T.untyped])
    end
    def self.values(restorable_id, subscriptions)
      subscriptions.map do |sub|
        [
          restorable_id, # restorable_id
          sub.user_id, # user_id
          sub.thread_type, # thread_type
          sub.original_created_at, # original_created_at
        ]
      end
    end

    # Internal: Restore custom watched repositories for this user.
    #
    # restorable - Restorable parent instance.
    sig { params(restorable: Restorable).void }
    def self.restore(restorable:)
      restorable.restoring(:restorable_custom_watched_repositories)
      RecoverRestorableCustomWatchedRepositoriesJob.perform_later(restorable_id: restorable.id)
    end

    # Internal: The metric name for statsd.
    sig { returns(Symbol) }
    def self.metric_name
      :custom_watched_repository
    end
  end
end
