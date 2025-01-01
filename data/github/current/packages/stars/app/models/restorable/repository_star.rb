# typed: true
# frozen_string_literal: true

# Internal: Belongs to a Restorable and stores the repository stars
# for a user. The user association is stored on a Restorable scenario class
#  like Restorable::OrganizationUser.
#
# Usage:
#
#  > user = User.find_by_login("lizzhale")
#  > repo = Repository.with_name_with_owner("github/linguist")
#  > restorable = Restorable.create
#
#  > Restorable::RepositoryStar.backup(:restorable => restorable, :repositories => [repo])
#  > Restorable::RepositoryStar.restore(:restorable => restorable, :user => user)
#
# This class and all of its methods should only ever be used by other
# Restorable classes and specifically Restorable scenario classes/models like
# Restorable::OrganizationUser.
class Restorable
  class RepositoryStar < ApplicationRecord::Mysql1
    # A set of common restorable type model helper methods.
    extend TypeHelpers

    belongs_to :restorable
    belongs_to :user, optional: true

    validates_presence_of :restorable_id, :repository_id
    validates_uniqueness_of :restorable_id, scope: :repository_id

    # Internal: Create a set of repository_star records.
    #
    # restorable - Restorable parent instance.
    # repositories - An array of repositories.
    def self.backup(restorable:, repositories:)
      star_entities = repositories.map do |repository|
        StarEntity.new(
          id: nil,
          user_id: nil,
          starrable_id: repository.id,
          starrable_type: Star::STARRABLE_TYPE_REPOSITORY,
          user_hidden: nil,
          created_at: nil,
        )
      end
      backup_from_stars(restorable: restorable, stars: star_entities)
    end

    # Internal: Create a set of repository_star records. To replace the self.backup method once the
    # :persist_user_with_restorable_stars feature flag is fully shipped.
    #
    # restorable - Restorable parent instance.
    # stars - An array of StarEntity instances.
    def self.backup_from_stars(restorable:, stars:)
      save_models(restorable, stars)
    end

    # Internal: Restore repository stars for this user.
    #
    # restorable - Restorable parent instance.
    # user - User instance.
    def self.restore(restorable:, user:)
      restorable.restoring(:restorable_repository_stars)

      measure_restore_time do
        repository_ids = restorable.repository_stars.pluck(:repository_id)

        throttle_batches(::Repository.where(id: repository_ids)) do |repository|
          Stars::Domain.new.star_repository(user:, repository:)
        end
      end

      restorable.restored(:restorable_repository_stars)
    end

    # Internal: Bulk insert sql.
    #
    # Returns a String.
    def self.insert_ignore_sql
      <<-SQL
        INSERT IGNORE INTO
          restorable_repository_stars
          (restorable_id,repository_id,user_id,original_created_at)
        :values
      SQL
    end

    # Internal: Create an array with needed values from models.
    #
    # restorable_id - Integer id of Restorable.
    # star_entities - Array of StarEntities.
    #
    # Returns an Array of arrays.
    def self.values(restorable_id, star_entities)
      star_entities.map do |star_entity|
        [
          restorable_id, # restorable_id
          star_entity.starrable_id, # repository_id
          star_entity.user_id, # user_id
          star_entity.created_at, # original_created_at
        ]
      end
    end

    # Internal: The metric name for statsd.
    #
    # Returns a Symbol.
    def self.metric_name
      :repository_star
    end
  end
end
