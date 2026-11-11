# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# Backfills subject_type and subject_id on agent_assignments rows where either
# is NULL. These columns were added in PR #427242 to support querying
# assignments by the entity being worked on (the "subject"), independent of
# what triggered the assignment (the "source"). Dual-writing was enabled in
# the preceding PR, so any new rows already have subject_* populated; this
# transition fills in historical rows.
#
# All historical rows have source_type = 0 (issue), so subject mirrors source:
# subject_type = source_type, subject_id = source_id. We scope by
# source_type = 0 defensively in case any other source_type rows ever exist
# without an established subject mapping.
#
# The iterator selects rows where either subject_type OR subject_id is NULL.
# Today no codepath produces a partially-populated row (every writer sets both
# columns atomically), but defending against that case is free and prevents a
# straggler row with one column set from quietly surviving the backfill and
# breaking the read migration's assumption that both fields are present.
#
# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class BackfillAgentAssignmentSubject < Base
      iterate_over :database_table, params: {
        model_class: AgentAssignment,
        conditions: "subject_type IS NULL OR subject_id IS NULL",
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        row_ids = items.keys

        scope = AgentAssignment
          .where(id: row_ids)
          .where("subject_type IS NULL OR subject_id IS NULL")
          .where(source_type: AgentAssignment.source_types[:issue])

        if dry_run?
          would_update = scope.count
          log "Would update #{would_update} of #{row_ids.size} agent_assignments row(s) (#{row_ids.min}-#{row_ids.max})"
        else
          updated_count = 0
          write_to(model_class: AgentAssignment) do
            updated_count = T.cast(
              scope.update_all("subject_type = source_type, subject_id = source_id"),
              Integer,
            )
          end
          log "Updated #{updated_count} out of #{row_ids.size} agent_assignments row(s) (#{row_ids.min}-#{row_ids.max})"
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

  GitHub::Transitions::BackfillAgentAssignmentSubject.new(args).run
end
