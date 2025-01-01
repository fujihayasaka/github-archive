# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class DeleteOrphanedChildTeamAbilities < Base
      iterate_over :database_table, params: {
        model_class: Ability,
        conditions: "actor_type = 'User' AND subject_type = 'Team' AND parent_id > 0 AND parent_id NOT IN (SELECT id FROM abilities)",
        columns: %i(id),
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        total = 0
        items.each do |id, _|
          log "Found ability to cleanup id: #{id}"
          unless dry_run?
            write_to(model_class: Ability) do

              # We have 27 entries as of 2023-10-12 to delete so no need for batching deletes
              # See https://github.com/github/security/issues/5984#issuecomment-1759153359
              Ability.delete(id)
            end
            log "Deleted ability id: #{id}"
          end
          total += 1
        end
        log "Found #{total} abilities to cleanup."
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

  GitHub::Transitions::DeleteOrphanedChildTeamAbilities.new(args).run
end
