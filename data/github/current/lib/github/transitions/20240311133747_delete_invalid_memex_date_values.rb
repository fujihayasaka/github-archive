# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class DeleteInvalidMemexDateValues < Base
      iterate_over :database_table, params: {
        model_class: MemexProjectColumn,
        conditions: "data_type = 63",
      }

      sig { override.void }
      def after_initialize
        @total_records_deleted = T.let(0, T.nilable(Integer))
      end

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        items.keys.each do |memex_column_id|
          values = MemexProjectColumnValue.where(memex_project_column_id: memex_column_id).pluck(:id, :value)
          next if values.empty?

          records_to_delete = []

          values.each do |date|
            begin
              MemexDateTimeFormat.parse(date[1])
            rescue MemexDateTimeFormat::FormatError
              records_to_delete.append(date[0])
            end
          end

          next unless records_to_delete.any?

          log("Number of records #{dry_run? ? "to delete" : "deleting" }: #{records_to_delete.size} ")
          log("#{dry_run? ? "Records to delete" : "Records deleting"}: #{records_to_delete}")
          @total_records_deleted += records_to_delete.size if @total_records_deleted

          next if dry_run?

          write_to(model_class: MemexProjectColumnValue) do
            MemexProjectColumnValue.where(id: records_to_delete).delete_all
          end
        end

        log("#{dry_run? ? "Would have deleted" : "Deleted"} #{@total_records_deleted} records")
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

  GitHub::Transitions::DeleteInvalidMemexDateValues.new(args).run
end
