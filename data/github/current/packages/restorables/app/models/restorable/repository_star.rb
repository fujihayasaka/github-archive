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
#  > star_entity = Stars.domain.repository_latest_star(repo.id)
#  > restorable = Restorable.create
#
#  > Restorable::RepositoryStar.backup(:restorable => restorable, :stars => [star_entity])
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

    batch_method(:repository) do |repository_stars|
      repositories_by_id = Repositories.domain.by_ids(repository_stars.map(&:repository_id)).index_by(&:id)
      repository_stars.index_with { |repository_star| repositories_by_id[repository_star.repository_id] }
    end

    # Internal: Create a set of repository_star records.
    #
    # restorable - Restorable parent instance.
    # stars - An array of StarEntity instances.
    def self.backup(restorable:, stars:)
      save_models(restorable, stars)
    end

    # Internal: Restore repository stars for this user.
    #
    # restorable - Restorable parent instance.
    # user - User instance to use when no user_id is present. To be removed once user_id is no longer nullable.
    def self.restore(restorable:, user: nil)
      restorable.restoring(:restorable_repository_stars)

      RecoverRestorableRepositoryStarsJob.perform_later(restorable_id: restorable.id, user_id: user&.id)
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
