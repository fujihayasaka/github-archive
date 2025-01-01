# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

module GitHub
  module Transitions
    class BackfillIntegrationVisibility < Base
      # Most transitions iterate over a dataset. To do that, use and configure
      # an iterator using `iterate_over`. See the common database table
      # iterator example below, or check the iterators base class
      # (`GitHub::Transitions::Iterators::Base`) to learn how to implement
      # a custom iterator.

      class Integration < ApplicationRecord::Domain::Integrations
        self.table_name = :integrations
      end

      iterate_over :database_table, params: {
        model_class: Integration,
        columns: %i[public visibility],
      }

      # The size of `items` is determined by the `process_batch_size`
      # argument. The value can be passed via the `--process-batch-size`
      # and has defaults for online and GHES environments.
      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        log("Processing batch of #{items.size} items starting with #{items.keys.first}")

        # If you're using the database table iterator, `items` is a
        # a `Hash` with `id`s as keys and values as columns loaded from
        # table: `{ 42 => { my_column: "foo" } }`
        items_to_change = items.select do |_id, column_hash|
          # if both, the app has a non default :public (of value false)
          # and a default :visibility (of value 0)
          (column_hash[:public] == false) && (column_hash[:visibility] == 0)
        end

        if dry_run?
          log("Would write #{items_to_change.count} updates to the Integrations table")
          return
        end

        if items_to_change.empty?
          log("No updates to write to the Integrations table")
        else
          log("Writing #{items_to_change.count} updates to the Integrations table")
          # Consider writing with a single query per batch instead of one query
          # per item. This will ensure speedy transitions in the GHES environment
          # where the process batch size is larger.
          write_to(model_class: ApplicationRecord::Domain::Integrations) do
            # "1" is "private_visibility"
            Integration.where(id: items_to_change.keys).update_all(visibility: 1)
          end
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

  GitHub::Transitions::BackfillIntegrationVisibility.new(args).run
end
