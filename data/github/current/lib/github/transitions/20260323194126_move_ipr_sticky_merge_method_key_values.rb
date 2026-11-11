# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "github/transitions/move_key_values_base"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
#
# Migrates sticky merge method keys from GitHub.kv (mysql5 key_values) to
# PullRequests::KV (ipr_key_values on issues-pull-requests cluster).
#
# Old key format: repo.merge_method.{repo_id}.user.{user_id}
# New key format: pull_requests/merge_method.user{user_id}
# Shard key:      repository_id (extracted from old key)
#
# Uses a custom key-based iterator that scans using the secondary index on
# `key_values`.`key` instead of PK-range scanning. This is dramatically faster
# because only matching rows are visited (~119M) instead of the full PK space (~89B).
module GitHub
  module Transitions
    class MoveIprStickyMergeMethodKeyValues < MoveKeyValuesBase
      StickyMergeMethodKeyTransformer = PullRequests::KV::KeyTransformer.new(
        old_key_pattern: %r(
          \Arepo\.merge_method\.(?<repository_id>\d+)
          \.user\.(?<user_id>\d+)
          \z
        )x,
        new_key_template: "pull_requests/merge_method.user%{user_id}",
      )

      # Custom iterator that scans key_values using the secondary index on `key`
      # instead of iterating over the full PK range. This leverages the
      # UNIQUE KEY `index_key_values_on_key` for an index-ordered scan,
      # visiting only the ~119M matching rows instead of 89B PKs.
      class KeyIndexIterator < Iterators::Base
        KEY_PREFIX = T.let("repo.merge_method.", String)
        # Keys starting with "repo.merge_method/" would be just past our range
        # since '/' (0x2F) follows '.' (0x2E) in ASCII.
        KEY_UPPER_BOUND = T.let("repo.merge_method/", String)

        BATCH_SIZE = T.let(1000, Integer)
        MAX_BATCH_SIZE = T.let(10_000, Integer)
        COLUMNS = T.let([:id, :key, :value, :created_at, :updated_at, :expires_at], T::Array[Symbol])

        sig do
          override.params(
            block: T.proc.params(items: Iterators::Identifiers).void
          ).void
        end
        def each_identifiers_batch(&block)
          last_key = T.let(start_key || KEY_PREFIX, String)
          batch_size = read_batch_size
          iteration_count = 0
          rows_count = 0

          log "iterating by key index with key_prefix=#{KEY_PREFIX} batch_size=#{batch_size}"

          while true
            rows = load_batch_by_key(last_key, batch_size)
            break if rows.empty?

            ids = rows.map(&:first)
            ids.each_slice(process_batch_size) do |ids_slice|
              ActiveRecord::Base.connected_to(role: :reading) do
                yield ids_slice
              end
            end

            last_key = T.cast(T.cast(rows.last, T::Array[T.untyped])[1], String)
            iteration_count += 1
            rows_count += rows.size

            if iteration_count % 100 == 0
              log "progress iterations=#{iteration_count} rows=#{rows_count} last_key=#{last_key}"
            end
          end

          log "complete total_iterations=#{iteration_count} total_rows=#{rows_count} last_key=#{last_key}"
        end

        sig { override.params(identifiers: Iterators::Identifiers).returns(Iterators::Items) }
        def build_items_for_batch(identifiers)
          items = T.let({}, Iterators::Items)

          column_values = MoveKeyValuesBase::KeyValues
            .where(id: identifiers)
            .pluck(*COLUMNS)

          column_values.each do |row|
            id = T.cast(row[0], Integer)
            items[id] = {
              key: row[1],
              value: row[2],
              created_at: row[3],
              updated_at: row[4],
              expires_at: row[5],
            }
          end

          items.each(&:freeze)
          items.freeze
        end

        sig { override.returns(Integer) }
        def worker_count
          value = arguments[:workers] || 4
          [value, 16].min
        end

        sig { override.void }
        def prepare_iteration
          ActiveRecord::Base.connection_handler.clear_all_connections!(:all)
        end

        sig { override.void }
        def prepare_worker
          ActiveRecord::Base.connection_handler.clear_all_connections!(:all)
        end

        private

        sig { params(last_key: String, batch_size: Integer).returns(T::Array[T::Array[T.untyped]]) }
        def load_batch_by_key(last_key, batch_size)
          ActiveRecord::Base.connected_to(role: :reading) do
            MoveKeyValuesBase::KeyValues
              .where("`key_values`.`key` > ? AND `key_values`.`key` < ?", last_key, KEY_UPPER_BOUND)
              .order(key: :asc)
              .limit(batch_size)
              .pluck(:id, :key)
          end
        end

        sig { returns(T.nilable(String)) }
        def start_key
          value = arguments[:start_key]
          return nil if value.blank?

          value.to_s
        end

        sig { returns(Integer) }
        def read_batch_size
          value = arguments[:read_batch_size] || BATCH_SIZE
          [value, MAX_BATCH_SIZE].min
        end

        sig { returns(Integer) }
        def process_batch_size
          value = arguments[:process_batch_size] || 100
          [value, 1000].min
        end
      end

      class IprKeyValues < ApplicationRecord::Domain::IssuesPullRequests
        self.table_name = :ipr_key_values
      end

      @source_model = KeyValues

      iterate_over KeyIndexIterator

      sig { override.returns(T.class_of(ApplicationRecord::Base)) }
      def model_class
        IprKeyValues
      end

      sig { override.returns(T::Array[String]) }
      def insert_fields = %w[key repository_id value created_at updated_at expires_at]

      sig { override.params(rows: T::Array[T::Hash[Symbol, T.anything]]).returns(T::Array[T.anything]) }
      def insert_values(rows)
        transformer = StickyMergeMethodKeyTransformer
        rows.map do |row|
          transformer.new_key_and_repo_id(T.cast(row[:key], String)) +
            row.values_at(:value, :created_at, :updated_at, :expires_at)
        end
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV, additional_arguments: %w(cleanup start_key))

  GitHub::Transitions::MoveIprStickyMergeMethodKeyValues.new(args).run
end
