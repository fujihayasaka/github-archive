# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class BackfillU2fLastUsedAtColumn < Base
      class U2fRegistration < ApplicationRecord::Domain::Users
        self.table_name = :u2f_registrations
      end

      iterate_over :database_table, params: {
        model_class: U2fRegistration,
        conditions: "last_used_at IS NULL",
        columns: %i[updated_at last_used_at],
      }

      sig { override.void }
      def after_initialize
        @total_u2f_registrations_updated = T.let(0, T.nilable(Integer))
      end

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        # Regrabbing records to ensure we have the latest data
        # From docs: Do not use the values of items for writes, as they might be outdated by the time the write happens.
        scope = U2fRegistration.where(id: items.keys).where(last_used_at: nil)
        if dry_run?
          log "Would have updated #{scope.size} u2f registrations"
        else
          write_to(model_class: U2fRegistration) do
            scope.update_all(Arel.sql("last_used_at = updated_at"))
          end
          log "Updated #{scope.size} u2f registrations"
        end
        @total_u2f_registrations_updated = T.must(@total_u2f_registrations_updated) + scope.size
        log "Total u2f registrations#{dry_run? ? " that we would have" : ""} updated: #{@total_u2f_registrations_updated}"
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  args = GitHub::Transitions::Arguments.parse(ARGV)

  GitHub::Transitions::BackfillU2fLastUsedAtColumn.new(args).run
end
