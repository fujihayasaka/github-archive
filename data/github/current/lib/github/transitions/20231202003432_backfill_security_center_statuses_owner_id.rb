# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class BackfillSecurityCenterStatusesOwnerId < Base
      class MyModel < ApplicationRecord::Notify
        self.table_name = :repository_security_center_statuses
      end

      iterate_over :database_table, params: {
        model_class: MyModel,
        conditions: "owner_id=0",
        columns: %i[organization_id],
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        log "#{dry_run? ? "Would be updating" : "Updating"} records from #{items.keys.first} to #{items.keys.last}"
        return if dry_run?

        query = <<-SQL
        UPDATE repository_security_center_statuses
        SET owner_id = organization_id
        WHERE id in (:ids)
        SQL

        update_sql = Arel.sql(query, ids: items.keys)
        write_to(model_class: MyModel) do
          MyModel.connection.update(update_sql)
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

  GitHub::Transitions::BackfillSecurityCenterStatusesOwnerId.new(args).run
end
