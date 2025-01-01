# typed: strict
# frozen_string_literal: true

module GitHub
  module Transitions
    class MoveKeyValuesBase < Base

      abstract!

      class KeyValues < ApplicationRecord::Domain::KeyValues
        self.table_name = :key_values
      end

      sig { params(key_patterns: T::Array[String]).void }
      def self.iterate_key_values(key_patterns = [])
        if key_patterns.length > 25
          raise ArgumentError, "too many patterns specified. (given #{key_patterns.length}, allowed 25)"
        end

        iterate_over :database_table, params: {
          model_class: KeyValues,
          columns: [:key, :value, :created_at, :updated_at, :expires_at],
          conditions: key_patterns.map! { |pattern| "`key_values`.`key` LIKE '#{pattern}'" }.join(" OR ")
        }
      end

      sig { abstract.returns(T.class_of(ApplicationRecord::Base)) }
      def model_class; end

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        # for ghes we migrate and cleanup in a single pass. we can do this
        # on ghes because the migration doesn't require dual-write and instead
        # occurs entirely offline.
        if GitHub.enterprise?
          copy_keys(items)
          cleanup_keys(items)
        else
          if arguments[:cleanup].blank?
            copy_keys(items)
          else
            cleanup_keys(items)
          end
        end
      end

      # Subclasses may override this method, e.g. for sharded clusters we need
      # an additional field for the shard key.
      sig { returns(T::Array[String]) }
      def insert_fields = %w[key value created_at updated_at expires_at]

      # Subclasses may override this method, e.g. for sharded clusters we need
      # an additional field for the shard key, or we may wish to rewrite the
      # keys in the new table.
      sig { params(rows: T::Array[T::Hash[Symbol, T.anything]]).returns(T::Array[T.anything]) }
      def insert_values(rows)
        rows.map { _1.values_at(:key, :value, :created_at, :updated_at, :expires_at) }
      end

      sig { params(items: Iterators::Items).void }
      def copy_keys(items)
        # make sure we do nothing on a dry run
        if dry_run?
          log "Would have copied #{items.count} rows to #{model_class.table_name}" if verbose?
          return
        end

        # note this is ensuring we do not overwrite values during the
        # migration. since we expect dual write to be fully enabled during
        # this process, we don't want to migrate an old value and overwrite
        # the more recent value from the dual write.
        query = <<~SQL
          INSERT INTO #{model_class.table_name}
            (#{insert_fields.map { model_class.connection.quote_column_name(_1) }.join(", ")})
          :rows
          ON DUPLICATE KEY UPDATE
            value = IF(updated_at < VALUES(updated_at), VALUES(value), value),
            created_at = IF(updated_at < VALUES(updated_at), VALUES(created_at), created_at),
            expires_at = IF(updated_at < VALUES(updated_at), VALUES(expires_at), expires_at),
            updated_at = IF(updated_at < VALUES(updated_at), VALUES(updated_at), updated_at)
        SQL

        rows = insert_values(items.values)
        sql = Arel.sql(query, rows: Arel::Nodes::ValuesList.new(rows))

        log "Inserting #{items.count} rows to #{model_class.table_name}" if verbose?
        write_to(model_class: model_class) do
          model_class.connection.insert(sql)
        end
      end

      sig { params(items: Iterators::Items).void }
      def cleanup_keys(items)
        # expiration values are rounded down using floor in github-kv
        # https://github.com/github/github-kv/blob/416940da77e6a71e3f34b5b164557af71251425d/lib/github/kv.rb#L652-L658
        expires_at = (Time.now.utc + 7.days).floor
        if dry_run?
          log "Would have expired #{items.count} rows on #{expires_at}" if verbose?
          return
        end

        # the idea behind this expiration vs. immediate deletion is to provide
        # a grace period before the original source data is lost forever. while
        # this likely isn't necessary, this still ensures the data is eventually
        # cleaned up after the migration has completed.
        query = <<~SQL
          UPDATE `key_values`
          SET    `expires_at` = :expires_at
          WHERE   id IN (:ids)
                  AND (expires_at IS NULL OR expires_at > :expires_at)
        SQL

        sql = Arel.sql(query, ids: items.keys, expires_at: expires_at)

        log "Expiring #{items.count} rows in table #{KeyValues.table_name} on #{expires_at}" if verbose?
        write_to(model_class: KeyValues) do
          KeyValues.connection.update(sql)
        end
      end
    end
  end
end
