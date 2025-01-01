# typed: true
# frozen_string_literal: true
module Team::ParentChange
  class RecalculateSubscriptionsOperation

    BATCH_SIZE = 100 # how many records to insert or delete at a time

    attr_reader :payload

    def initialize(payload, options = nil)
      @payload = payload
    end

    # Public: recalculates subscriptions for indirect members of a team that's been
    # moved around in a hierarchy.
    #
    def execute
      total_deleted = 0
      total_created = 0
      start = Time.now
      ApplicationRecord::Domain::Notifications.transaction do
        team_and_decendant_ids = payload.old_descendants + [payload.team_id]
        removed_ancestor_ids = payload.old_ancestors - payload.new_ancestors
        added_ancestor_ids = payload.new_ancestors - payload.old_ancestors

        direct_member_ids(team_and_decendant_ids).each_slice(BATCH_SIZE) do |member_ids|
          total_deleted += delete_subscriptions(team_ids: removed_ancestor_ids, member_ids: member_ids)
          total_created += create_subscriptions(team_ids: added_ancestor_ids, member_ids: member_ids)
        end
      end
      ms = (Time.now - start) * 1000
      GitHub.dogstats.distribution("notifications.team.parent_change.recalculate_subscriptions_operation.dist.duration", ms)

      GitHub.dogstats.distribution("notifications.team.parent_change.recalculate_subscriptions_operation.dist.subscriptions_deleted", total_deleted)
      GitHub.dogstats.distribution("notifications.team.parent_change.recalculate_subscriptions_operation.dist.subscriptions_created", total_created)
    end

    private

    # Private
    #
    # Returns an Array of User ids for all direct members of the given team ids.
    def direct_member_ids(team_ids)
      return [] if team_ids.blank?
      ActiveRecord::Base.connected_to(role: :reading) do
        sql = Arel.sql(<<-SQL, subject_ids: team_ids, direct: Ability.priorities[:direct])
          SELECT actor_id
          FROM abilities
          WHERE priority = :direct
          AND actor_type = 'User'
          AND subject_type = 'Team'
          AND subject_id IN (:subject_ids)
        SQL

        Ability.connection.select_all(sql).rows.flatten
      end
    end

    # Private
    #
    # Returns an Array of User and Team id tuples [user.id, team.id] for the given
    # members that are direct members of the given teams.
    def direct_memberships(team_ids:, member_ids:)
      return [] if team_ids.blank?
      ActiveRecord::Base.connected_to(role: :reading) do
        sql = Arel.sql(<<-SQL, subject_ids: team_ids, user_ids: member_ids, direct: Ability.priorities[:direct])
          SELECT actor_id, subject_id
          FROM abilities
          WHERE priority = :direct
          AND actor_type = 'User'
          AND actor_id IN (:user_ids)
          AND subject_type = 'Team'
          AND subject_id IN (:subject_ids)
        SQL

        Ability.connection.select_all(sql).rows
      end
    end

    # Private
    #
    # Returns an Array of Subscription ids of all (and only) indirect memberships
    # for the given teams and members. Subscriptions for direct memberships are
    # excluded.
    def subscription_ids_for_indirect_memberships(team_ids:, member_ids:)
      return [] if team_ids.blank? || member_ids.blank?

      ActiveRecord::Base.connected_to(role: :reading) do
        sql = Arel.sql(<<-SQL, team_ids: team_ids, user_ids: member_ids)
          SELECT id
          FROM notification_subscriptions
          WHERE list_type = 'Team'
          AND list_id IN (:team_ids)
          AND user_id IN (:user_ids)
        SQL

        direct_memberships(team_ids: team_ids, member_ids: member_ids).each do |user_and_team_id|
          user_id = user_and_team_id[0]
          team_id = user_and_team_id[1]
          sql += Arel.sql <<-SQL, user_id: user_id, team_id: team_id
            AND NOT (user_id = :user_id AND list_id = :team_id)
          SQL
        end

        Newsies::ListSubscription.connection.select_all(sql).rows.flatten
      end
    end

    # Private
    #
    # Deletes subscriptions for (and only for) indirect memberships of the given
    # team and user ids. Subscriptions for direct memberships will remain.
    #
    # Returns an Integer representing the number of deleted subscriptions.
    def delete_subscriptions(team_ids:, member_ids:)
      subscription_ids = subscription_ids_for_indirect_memberships(
        team_ids: team_ids, member_ids: member_ids)
      return 0 if subscription_ids.blank?

      Newsies::ListSubscription.throttle { Newsies::ListSubscription.delete(subscription_ids) }
    end

    # Private
    #
    # Creates (or ignores when there already exist) subscriptions for the
    # provided user and team ids.
    #
    # Returns an Integer representing the number of created subscriptions.
    def create_subscriptions(team_ids:, member_ids:)
      user_and_team_ids = member_ids.product(team_ids)
      return 0 if user_and_team_ids.blank?

      now = GitHub::SQL::ArelLiterals::NOW
      rows = user_and_team_ids.map do |user_and_team_id|
        user_id = user_and_team_id[0]
        team_id = user_and_team_id[1]
        [
          user_id,
          team_id,
          "Team",
          0,
          1,
          now
        ]
      end

      sql = Arel.sql(<<-SQL, rows: Arel::Nodes::ValuesList.new(rows))
        INSERT IGNORE INTO
          notification_subscriptions
          (user_id, list_id, list_type, ignored, notified, created_at)
          :rows
      SQL

      connection = Newsies::ListSubscription.connection
      Newsies::ListSubscription.throttle { connection.update(sql) }
    end
  end
end
