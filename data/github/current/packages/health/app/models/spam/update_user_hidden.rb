# typed: false
# frozen_string_literal: true

module Spam
  module UpdateUserHidden
    UPDATE_BATCH_SIZE = 10

    SELECT_BATCH_SIZE = 10_000
    # smaller batch size of 1000
    SMALLER_SELECT_BATCH_SIZE = 1_000


    def self.update_table(table, user_hidden, user_id)
      return unless user_id
      return unless table

      table = table.to_sym
      klass = Spam::Spammable.tables_classes_including[table]
      return unless klass

      ids = if table == :followers
        if FeatureFlag.vexi.enabled?(:update_user_hidden_follow_joins, default: true)
          select_followers_ids(klass, user_id, user_hidden)
        else
          select_ids(klass, user_id, user_hidden, :following_id) +
            select_ids(klass, user_id, user_hidden, :user_id)
        end
      else
        select_ids(klass, user_id, user_hidden)
      end

      update_table_ids(klass, ids, user_hidden)
    end

    # Public: Get ids for the users that have content that does not match their user_hidden state.
    #
    # updated_since - Time that user was updated at to use as lower bound in search.
    #
    # Returns an Array of user ids.
    def self.user_ids_for_mismatches(updated_since:)
      user_ids_with_mismatch = Set.new

      User.transaction do
        ActiveRecord::Base.connected_to(role: :reading) do
          scope = User.where("updated_at >= ?", updated_since)
          spammy_user_ids = scope.spammy.pluck(:id)
          not_spammy_user_ids = scope.not_spammy.pluck(:id)

          Spam::Spammable.tables_classes_including.each do |table, klass|
            # For follow relationships, we should only include cases where the
            # other user is not spammy.
            [true, false].each do |user_hidden|
              batch_size =  if user_hidden &&
                            klass == Following &&
                            FeatureFlag.vexi.enabled?(:smaller_batch_size_for_hidden_mismatches, default: true)
                SMALLER_SELECT_BATCH_SIZE
              else
                SELECT_BATCH_SIZE
              end

              user_ids = user_hidden ? not_spammy_user_ids : spammy_user_ids

              user_ids.each_slice(batch_size) do |slice_user_ids|
                mismatches_scope = klass.annotate("cross-shard-query-exempted-permanent").
                  where(user_hidden: user_hidden).
                  where(klass.spammable_user_foreign_key => slice_user_ids)

                if user_hidden && klass == Following
                  mismatches_scope = mismatches_scope.
                    joins("JOIN users ON users.id = #{table}.following_id").
                    where(users: { spammy: false })
                end
                table_user_ids = mismatches_scope.pluck(klass.spammable_user_foreign_key) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

                user_ids_with_mismatch.merge(table_user_ids)
              end
            end
          end
        end
      end

      user_ids_with_mismatch.to_a
    end

    # Public: return a query to select ids associated with a given user from a spammable table's
    #
    # klass          - the spammable class
    # foreign_key    - optional column in the spammable class's table that references the user,
    #                  default is the class's defined spammable_user_foreign_key
    # users_join_key - optional column in the spammable class's table to join to the users table to
    #                  filter out related users that are still flagged as spammy, default is nil
    #
    # Returns a query string
    def self.id_batch_query(klass, foreign_key: nil, users_join_key: nil)
      user_key = foreign_key || klass.spammable_user_foreign_key

      if users_join_key.present?
        optional_join = "JOIN users ON users.id = #{klass.table_name}.#{users_join_key}"
        optional_spammy_filter = "AND users.spammy = 0"
      end

      if klass.spammable_user_foreign_type.present?
        # Business and other type of owners are not supported yet.
        polymorphic_type_filter = "AND #{klass.table_name}.#{klass.spammable_user_foreign_type} = 'User'"
      end

      query = <<-SQL
        /* cross-shard-query-exempted-permanent */
        SELECT #{klass.table_name}.id FROM #{klass.table_name}
        #{optional_join}
        WHERE #{klass.table_name}.#{user_key} = :user_id
        #{polymorphic_type_filter}
        AND #{klass.table_name}.user_hidden = :user_hidden
        #{optional_spammy_filter}
        AND #{klass.table_name}.id > :previous_max_id
        ORDER BY #{klass.table_name}.id
        LIMIT #{SELECT_BATCH_SIZE}
        SQL
    end

    def self.select_ids(klass, user_id, user_hidden, foreign_key = nil)
      user_key = foreign_key || klass.spammable_user_foreign_key

      ActiveRecord::Base.connected_to(role: :reading) do
        previous_max_id = 0
        ids = []

        loop do
          query = id_batch_query(klass, foreign_key: foreign_key)
          res = klass.connection.select_values(Arel.sql(query, user_id: user_id, user_hidden: !user_hidden, previous_max_id: previous_max_id)) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

          ids.concat res

          break if res.size < SELECT_BATCH_SIZE
          previous_max_id = res.last
        end

        ids
      end
    end
    private_class_method :select_ids

    def self.select_followers_ids(klass, user_id, user_hidden)
      if user_hidden
        # When setting the user_hidden column for a user, we don't need to check the spammy status of
        # the other user.
        follower_query = id_batch_query(klass, foreign_key: :following_id)
        following_query = id_batch_query(klass, foreign_key: :user_id)
      else
        # When clearing the user_hidden column for a user, we need to ensure that the related user on
        # the other side of the follow relationship is not flagged as spammy.
        follower_query = id_batch_query(klass, foreign_key: :following_id, users_join_key: :user_id)
        following_query = id_batch_query(klass, foreign_key: :user_id, users_join_key: :following_id)
      end

      ActiveRecord::Base.connected_to(role: :reading) do
        ids = []

        [follower_query, following_query].each do |query|
          previous_max_id = 0

          loop do
            res = klass.connection.select_values(Arel.sql(query, user_id: user_id, user_hidden: !user_hidden, previous_max_id: previous_max_id))

            ids.concat res

            break if res.size < SELECT_BATCH_SIZE
            previous_max_id = res.last
          end
        end

        ids
      end
    end
    private_class_method :select_followers_ids

    def self.update_table_ids(klass, ids, user_hidden)
      ids.each_slice(UPDATE_BATCH_SIZE) do |slice|
        klass.throttle do
          if klass.table_name == "repositories"
            klass.connection.update(Arel.sql(<<-SQL, ids: slice, user_hidden: user_hidden))
              UPDATE #{klass.table_name}
              SET user_hidden = :user_hidden
              WHERE id IN (:ids)
            SQL
          else
            klass.connection.update(Arel.sql(<<-SQL, ids: slice, user_hidden: user_hidden)) # domain-isolation-query-violation:ignore:packages/issues (UPDATE)
              /* cross-shard-query-exempted-permanent */
              UPDATE #{klass.table_name}
              SET user_hidden = :user_hidden
              WHERE id IN (:ids)
            SQL
          end
        end
      end
    end
    private_class_method :update_table_ids
  end
end
