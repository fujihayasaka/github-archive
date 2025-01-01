# typed: true
# frozen_string_literal: true

module Starrable
  extend ActiveSupport::Concern
  include GitHub::BatchMethod
  extend T::Helpers

  requires_ancestor { ActiveRecord::Base }

  class InvalidActorError < StandardError
  end

  included do
    # Has this entity been starred by this user?
    #
    # user - the User in question
    #
    # Examples
    #
    #   # To prevent N+1s when this method is called on a list of starrables,
    #   # prefill it this way:
    #
    #   # Execute 1 query to preload (usually in a controller action)
    #   GitHub::PrefillAssociations.prefill_batch_method(repos, :starred_by?, current_user)
    #
    #   repos.each do |repo|
    #     # Method is preloaded and memoized - no queries are executed here!
    #     repo.starred_by?(current_user)
    #   end
    #
    # Returns a Boolean.
    batch_method :starred_by? do |entities, user|
      starred_by_entity = Hash.new(false)
      next starred_by_entity unless user

      unless user.is_a?(User)
        raise InvalidActorError, "actor must be a User"
      end

      promises = entities.select(&:persisted?).map do |entity|
        Platform::Loaders::HasStarredCheck.load(user.id, entity).then do |is_starred|
          starred_by_entity[entity] = true if is_starred
        end
      end
      Promise.all(promises).sync

      starred_by_entity
    end
  end

  # Public: Name of the database field used to store the star count, if the table has one.
  #
  # Returns a String.
  def stargazer_count_column
    "stargazer_count"
  end

  # Public: Modify the current stargazer_count of this entity by one.
  #
  # increment - Boolean indicating whether the value should increase or decrease
  #
  # Returns a Boolean indicating success.
  def modify_stargazer_count(increment:)
    field_name = stargazer_count_column
    return unless field_name

    klass = T.cast(self.class, T.class_of(ActiveRecord::Base))

    query = <<~SQL
      UPDATE #{klass.table_name}
      SET updated_at = CASE WHEN #{field_name} <> GREATEST(COALESCE(#{field_name}, 0) + :difference, 0)
                       THEN :now
                       ELSE updated_at
                       END,
        #{field_name} = GREATEST(COALESCE(#{field_name}, 0) + :difference, 0)
      WHERE id = :id
    SQL

    difference = increment ? 1 : -1
    affected_rows = klass.connection.update(Arel.sql(query, id: id, difference: difference, now: Time.now.utc))
    success = affected_rows == 1

    # Update the local value for immediate use, so we don't have to reload the record to fetch it:
    self[field_name] = [self[field_name] + difference, 0].max if success

    success
  end
end
