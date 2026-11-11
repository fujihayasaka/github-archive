# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class PopulateCustomPropertyDefinitionSourceFields < Base
      class CustomPropertyDefinition < ApplicationRecord::Domain::Repositories
        self.table_name = :custom_property_definitions
      end

      iterate_over :database_table, params: {
        model_class: CustomPropertyDefinition,
        conditions: "source_id IS NULL",
        columns: %i[id organization_id source_id],
      }

      sig { override.void }
      def after_initialize
        @total = T.let(0, T.nilable(Integer))
      end

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        first_id = items.keys.first
        last_id = items.keys.last

        log "Dry run:" if dry_run?
        log "Processing items #{first_id} to #{last_id}"

        log "The following items are not up to date:"
        log "#{items.keys}"

        if dry_run?
          log "#{items.size} items would have been updated"
        else
          write_to(model_class: CustomPropertyDefinition) do
            CustomPropertyDefinition.where(id: items.keys).update_all(
              source_id: Arel.sql("organization_id")
            )

            log "Definition IDs: #{items.keys} are updated"
          end

          log "#{items.size} items have been updated"
        end

        @total = (@total || 0) + items.size
        log "#{@total} items processed"
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

  GitHub::Transitions::PopulateCustomPropertyDefinitionSourceFields.new(args).run
end
