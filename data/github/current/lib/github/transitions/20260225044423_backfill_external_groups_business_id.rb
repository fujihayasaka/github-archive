# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class BackfillExternalGroupsBusinessId < Base
      iterate_over :database_table, params: {
        model_class: ExternalGroup,
        conditions: "business_id IS NULL",
        columns: %i[id],
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        external_group_ids = items.keys

        if dry_run?
          log("Would have updated #{external_group_ids.size} external groups (sample: #{external_group_ids.first(10)}) with business_id #{GitHub.global_business.id}")
        else
          log("Updating #{external_group_ids.size} external groups (sample: #{external_group_ids.first(10)}) with business_id #{GitHub.global_business.id}")
          write_to(model_class: ExternalGroup) do
            ExternalGroup.where(id: external_group_ids).update_all(business_id: GitHub.global_business.id)
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

  return unless GitHub.single_business_environment?
  GitHub::Transitions::BackfillExternalGroupsBusinessId.new(args).run
end
