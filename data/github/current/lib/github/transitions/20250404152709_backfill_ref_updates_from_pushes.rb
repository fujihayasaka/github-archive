# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class BackfillRefUpdatesFromPushes < Base
      NULL_OID = "0000000000000000000000000000000000000000"

      class TransitionPush < ApplicationRecord::Domain::RepositoriesPushes
        self.table_name = "pushes"
        default_scope { annotate("cross-shard-query-exempted") }
      end

      class TransitionRefUpdate < ApplicationRecord::Domain::RepositoriesPushes
        self.table_name = "ref_updates"
        serialize :after_oid, coder: GitHub::Hex
        serialize :before_oid, coder: GitHub::Hex
      end

      iterate_over :database_table, params: {
        model_class: TransitionPush,
        columns: %i[id repository_id before after ref push_type]
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        ref_updates = items.map do |push_id, push|
          push[:before] = NULL_OID if push[:before].nil?
          push[:after] = NULL_OID if push[:after].nil?

          # All the values selected above must be non-NULL.
          nil_columns = push.select { |_, v| v.nil? }.keys
          if nil_columns.empty?
            {
              push_id: push_id,
              repository_id: push[:repository_id],
              before_oid: push[:before],
              after_oid: push[:after],
              ref: push[:ref],
              ref_update_type: push[:push_type]
            }
          else
            log "Skipping push #{push_id} because it has null column(s): #{nil_columns}"
            next
          end
        end.compact

        candidate_insert_push_ids = ref_updates.pluck(:push_id)
        insert_push_ids = ActiveRecord::Base.connected_to(role: :reading) do
          found_push_ids = GitHub.dogstats.distribution_time("transition.backfill_ref_updates.select_dupe_push_ids") do
            TransitionRefUpdate.where(push_id: candidate_insert_push_ids).pluck(:push_id)
          end
          log "Skipping duplicate pushes: #{found_push_ids}" if found_push_ids.any?
          candidate_insert_push_ids - found_push_ids
        end

        ref_updates = ref_updates.select { |ref_update| insert_push_ids.include?(ref_update[:push_id]) }
        if verbose? && ref_updates.any?
          log "Ref updates to insert:"
          ref_updates.each do |ref_update|
            log ref_update.to_s
          end
        end

        if dry_run?
          log "[Dry run] would insert pushes: #{insert_push_ids}"
        elsif ref_updates.any?

          insert_proc = proc do
            GitHub.dogstats.distribution_time("transition.backfill_ref_updates.insert_all") do
              TransitionRefUpdate.insert_all(ref_updates)
            end
          end

          GitHub.dogstats.distribution_time("transition.backfill_ref_updates.write_to") do
            write_to(model_class: TransitionRefUpdate) do
              if GitHub.multi_tenant_enterprise?
                insert_ref_updates(ref_updates)
              else
                # This performance optimization causes TRILOGY_TRUNCATED_PACKET errors on Proxima.
                TransitionRefUpdate.transaction(isolation: :read_committed) do
                  insert_ref_updates(ref_updates)
                end
              end
            end
          end
          log "Inserted pushes: #{insert_push_ids}" if verbose?
        end
      end

      sig { params(ref_updates: T::Array[T.untyped]).void }
      private def insert_ref_updates(ref_updates)
        GitHub.dogstats.distribution_time("transition.backfill_ref_updates.insert_all") do
          TransitionRefUpdate.insert_all(ref_updates)
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
  args = GitHub::Transitions::Arguments.parse(ARGV)

  GitHub::Transitions::BackfillRefUpdatesFromPushes.new(args).run
end
