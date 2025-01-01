# typed: true
# frozen_string_literal: true

module GitHub
  class HighUpdateKV < GitHub::KV
    # Use this class when you expect frequent updates to existing keys.
    # The base GitHub::KV implementation uses an `INSERT ... ON DUPLICATE KEY UPDATE` strategy
    # which can cause lock contention in high frequency update scenarios.

    def mset(kvs, expires: nil)
      key_count = kvs.keys.count

      if key_count == 1 && FeatureFlag.vexi.enabled?(:kv_update_first, default: false)
        GitHub.dogstats.distribution_time("high_update_kv.mset.time", tags: ["table:#{@table_name}", "eager_update:true"]) do
          mset_eager_update(kvs, expires:)
        end
      elsif key_count == 1 && FeatureFlag.vexi.enabled?(:observe_kv_mset_single_key_dist, default: false)
        GitHub.dogstats.distribution_time("high_update_kv.mset.time", tags: ["table:#{@table_name}", "eager_update:false"]) do
          super
        end
      else
        super
      end
    end

    private

    def mset_eager_update(kvs, expires:)
      validate_key_value_hash(kvs)
      validate_expires(expires) if expires

      encapsulate_error do
        insert = false
        success = nil
        begin
          key, value = kvs.first

          # Eagerly UPDATE
          update_columns = [
            "value = #{quoted_value(value)}",
            "updated_at = #{sanitized_now}",
            "expires_at = #{quoted_value(rounded_expiry(expires)) || "NULL"}"
          ].join(", ")
          where_clause = "`key` = #{quoted_value(key)}"
          if sharded?
            where_clause += " AND #{quoted_shard_key_column} = #{quoted_shard_key_value}"
          end

          update_result = connection.execute(<<-SQL
            UPDATE #{quoted_table_name}
            SET #{update_columns}
            WHERE #{where_clause}
            SQL
          )

          # If no rows were affected, INSERT a new record
          if update_result.affected_rows == 0
            insert = true
            columns = %w[
              `key`
              value
              created_at
              updated_at
              expires_at
            ]
            values = [
              quoted_value(key),
              quoted_value(value),
              sanitized_now,
              sanitized_now,
              quoted_value(rounded_expiry(expires)) || "NULL"
            ]

            if sharded?
              columns << quoted_shard_key_column
              values << quoted_shard_key_value
            end

            connection.execute(<<-SQL
              INSERT INTO #{quoted_table_name} (#{columns.join(",")})
              VALUES (#{values.join(",")})
              SQL
            )
          end
          success = true
        rescue ActiveRecord::RecordNotUnique
          success = false
        ensure
          GitHub.dogstats.increment("high_update_kv.mset", tags: [
            "table:#{@table_name}",
            "insert:#{insert}",
            "success:#{success}"
          ])
        end
      end
    end
  end
end
