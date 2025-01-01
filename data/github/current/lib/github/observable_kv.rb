# typed: true
# frozen_string_literal: true

module GitHub
  class ObservableKV < GitHub::KV
    sig { params(kvs: T::Hash[String, String], expires: T.nilable(Time)).void }
    def mset(kvs, expires: nil)
      if FeatureFlag.vexi.enabled?(:observe_kv_mset, default: false)
        validate_key_value_hash(kvs)
        validate_expires(expires) if expires

        encapsulate_error do
          columns = %w[
            `key`
            value
            created_at
            updated_at
            expires_at
          ]
          values_list = kvs.map do |key, value|
            [
              quoted_value(key),
              quoted_value(value),
              sanitized_now,
              sanitized_now,
              quoted_value(rounded_expiry(expires)) || "NULL"
            ]
          end

          if sharded?
            columns << quoted_shard_key_column
            values_list.each { _1 << quoted_shard_key_value }
          end

          result = connection.execute(<<-SQL
            INSERT INTO #{quoted_table_name} (#{columns.join(",")})
            VALUES #{values_list.map { |values| "(#{values.join(",")})" }.join(", ")}
            ON DUPLICATE KEY UPDATE
              value = VALUES(value),
              updated_at = VALUES(updated_at),
              expires_at = VALUES(expires_at)
            SQL
          )

          GitHub.dogstats.increment("kv.mset.success", tags: ["table:#{@table_name}", "affected_rows:#{result.affected_rows}", "key_count:#{kvs.keys.count}"])
        end
      else
        super
      end
    end
  end
end
