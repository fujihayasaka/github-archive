# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

module GitHub
  module Transitions
    # This class defines a high-performance version of this transition, but it requires MySQL 8+.
    #
    # We intend for this class to be used on Dotcom and on Proxima where MySQL 8+ is supported. For GHES (or, in
    # general, for MySQL <8), there is a second class defined below that should be used instead. If this class is
    # used on a MySQL <8, it will raise an exception.
    #
    # This class assumes that the `memex_dual_write_priorities` has been fully enabled in the environment in which
    # this transition is running.
    class BackfillVirtualPriorityOnMemexProjectItemsOnMySQL8 < Base
      include GitHub::Memoizer

      class MemexProjectItem < ApplicationRecord::Domain::Memexes
        self.table_name = :memex_project_items
      end

      class MemexProject < ApplicationRecord::Domain::Memexes
        self.table_name = :memex_projects
      end

      class InvalidMySQLVersionError < StandardError; end

      iterate_over :database_table, params: {
        model_class: MemexProject,
      }

      sig { override.void }
      def after_initialize
        unless mysql_version.to_i >= 8
          raise(
            InvalidMySQLVersionError,
            "This transition requires MySQL 8+, but the current database is running MySQL #{mysql_version}. " +
            "Please use `GitHub::Transitions::BackfillVirtualPriorityOnMemexProjectItemsOnMySQL5` instead."
          )
        end
      end

      sig { returns(String) }
      memoize private def mysql_version
        MemexProjectItem.connection.execute("SELECT VERSION()").rows.first.first
      end

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        items.keys.each do |memex_project_id|
          if MemexProjectItem.where(memex_project_id:).where.not(virtual_priority: nil).exists?
            log("Skipping project #{memex_project_id} because it already has a virtual_priority value")
            next
          end

          if dry_run?
            log(
              "Would have updated #{MemexProjectItem.where(memex_project_id:).count} items from project " +
              memex_project_id.to_s
            )
            next
          end

          # This assigns new priorities according to the sequence 1/2, 3/2, 5/2, etc.
          # That approach is adapted from https://wiki.postgresql.org/wiki/User-specified_ordering_with_fractions.
          #
          # The row count LIMIT applied below is the maximum number of items that are allowed in a single project
          # under the `memex_paginated_archive` feature flag. That feature flag will apply to less than 50 projects,
          # when this transition is executed, for which the current maximum number of items is ~23k
          # (https://data.githubapp.com/sql/share/6cfaf199). Otherwise, p99 project size is ~300 items
          # (https://data.githubapp.com/sql/share/9f78bbbc).
          #
          # In order to prevent interleaving writes that could cause us to assign incorrect priorities, we update
          # all items for the project in a single statement (and therefore a single transaction). We perform
          # throttling prior to updating items for each project, but not any more granularly so as to avoid
          # maintaining a long-running transaction in the event of replication lag.
          update_statement = Arel.sql(<<~SQL, memex_project_id:)
            UPDATE
              memex_project_items
            INNER JOIN
              (
                SELECT
                  id,
                  ROW_NUMBER() OVER (PARTITION BY memex_project_id ORDER BY priority ASC) AS rownum
                FROM
                  memex_project_items
                WHERE
                  memex_project_items.memex_project_id = :memex_project_id
              )
            AS
              numbered_memex_project_items
            ON
              memex_project_items.id = numbered_memex_project_items.id
            SET
              memex_project_items.priority_numerator = 2 * numbered_memex_project_items.rownum - 1,
              memex_project_items.priority_denominator = 2
          SQL

          write_to(model_class: MemexProjectItem) do
            rows_affected = MemexProjectItem.connection.update(update_statement)
            log("Updated #{rows_affected} rows from project #{memex_project_id}")
          end
        end
      end
    end

    # This class defines a slower version of this transition, but it is compatible with MySQL 5.7.
    #
    # We intend for this class to be used on GHES, where we need to maintain backwards compatibility with MySQL 5.7.
    # In environments that run MySQL 8+, we should prefer the class defined above.
    #
    # This class assumes that the `memex_dual_write_priorities` has been fully enabled in the environment in which
    # this transition is running.
    class BackfillVirtualPriorityOnMemexProjectItemsOnMySQL5 < Base
      class MemexProjectItem < ApplicationRecord::Domain::Memexes
        self.table_name = :memex_project_items
      end

      class MemexProject < ApplicationRecord::Domain::Memexes
        self.table_name = :memex_projects
      end

      iterate_over :database_table, params: {
        model_class: MemexProject,
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        items.keys.each do |memex_project_id|
          if MemexProjectItem.where(memex_project_id:).where.not(virtual_priority: nil).exists?
            log("Skipping project #{memex_project_id} because it already has a virtual_priority value")
            next
          end

          project_item_ids = MemexProjectItem.where(memex_project_id:).order(priority: :asc).pluck(:id)
          count_description = "#{project_item_ids.length} item#{project_item_ids.length == 1 ? '' : 's'}"

          if dry_run?
            log("Would have updated #{count_description} from project #{memex_project_id}")
            next
          end

          write_to(model_class: MemexProjectItem) do
            MemexProjectItem.transaction do
              project_item_ids.each_with_index do |id, index|
                numerator = 2 * index + 1
                update_statement = Arel.sql(<<~SQL, id:, numerator:)
                  UPDATE
                    memex_project_items
                  SET
                    priority_numerator = :numerator,
                    priority_denominator = 2
                  WHERE
                    id = :id
                SQL
                MemexProjectItem.connection.update(update_statement)
              end
            end
          end

          log("Updated #{count_description} from project #{memex_project_id}")
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
  args = GitHub::Transitions::Arguments.parse(ARGV, additional_arguments: %w(mysql_version))

  if args[:mysql_version].to_i >= 8
    GitHub::Transitions::BackfillVirtualPriorityOnMemexProjectItemsOnMySQL8.new(args).run
  else
    GitHub::Transitions::BackfillVirtualPriorityOnMemexProjectItemsOnMySQL5.new(args).run
  end
end
