# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class BackfillCliDirectOrgBillingValueFromCli < Base
      class CopilotConfiguration < ApplicationRecord::Copilot
        self.table_name = "copilot_configurations"
      end

      iterate_over :database_table, params: {
        model_class: CopilotConfiguration,
        columns: %i[configurable_type cli cli_direct_org_billing],
        conditions: "configurable_type in ('Organization', 'Business') AND cli = 2 AND cli_direct_org_billing <> 2",
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        if dry_run?
          log("Dry run: would have updated #{items.size} records")
        else
          log("Updating cli_direct_org_billing to enabled for #{items.size} records")
          write_to(model_class: CopilotConfiguration) do
            CopilotConfiguration.where(id: items.keys)
            .where(configurable_type: %w[Organization Business], cli: 2)
            .where.not(cli_direct_org_billing: 2)
            .update_all(cli_direct_org_billing: 2)
          end
          log("Updated cli_direct_org_billing to enabled for #{items.size} records")
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

  GitHub::Transitions::BackfillCliDirectOrgBillingValueFromCli.new(args).run
end
