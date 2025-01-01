# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class RemoveAppManagementPermissions < Base
      ORG_APP_MANAGER_SUBJECT_TYPE = T.let("Organization/manage_apps", String)

      MANAGEMENT_SUBJECT_TYPES = T.let(
        [ORG_APP_MANAGER_SUBJECT_TYPE, "Integration/manage"],
        T::Array[String]
      )

      class Permission < ApplicationRecord::Domain::Permissions
        self.table_name = :permissions
      end

      class CustomIterator < GitHub::Transitions::Iterators::Base
        DEFAULT_PROCESS_BATCH_SIZE = T.let(
          GitHub.enterprise? ? 10000 : 100, Integer
        )

        sig do
          override.params(
            block: T.proc.params(items: GitHub::Transitions::Iterators::Identifiers).void
          ).void
        end
        def each_identifiers_batch(&block)
          last_processed_id = arguments[:last_processed_id].to_i

          while ids = load_ids(last_processed_id)
            yield ids
            last_processed_id = ids.last

            return unless last_processed_id
          end
        end

        sig do
          override.params(
            identifiers: GitHub::Transitions::Iterators::Identifiers
          ).returns(GitHub::Transitions::Iterators::Items)
        end
        def build_items_for_batch(identifiers)
          identifiers.each_with_object({}) do |id, hash|
            hash[id] = id
          end
        end

        sig { params(last_processed_id: Integer).returns(GitHub::Transitions::Iterators::Identifiers) }
        def load_ids(last_processed_id)
          Permission
            .where(subject_type: MANAGEMENT_SUBJECT_TYPES)
            .where(actor_type: "User")
            .where("id > ?", last_processed_id)
            .order(:id)
            .limit(process_batch_size)
            .pluck(:id)
        end

        sig { returns(Integer) }
        def process_batch_size
          arg = arguments[:process_batch_size].to_i
          return DEFAULT_PROCESS_BATCH_SIZE if arg.zero?

          arg
        end
      end

      iterate_over CustomIterator

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        item_ids = items.keys
        log("Processing batch", size: items.size, start_id: item_ids.first, end_id: item_ids.last)

        if dry_run?
          log("Would remove permissions", size: items.size)
        else
          write_to(model_class: Permission) do
            removed = Permission.where(id: item_ids).delete_all
            log("Successfully removed permissions in batch", size: removed)
          end
        end

        log("Finished batch", size: items.size)
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

  GitHub::Transitions::RemoveAppManagementPermissions.new(args).run
end
