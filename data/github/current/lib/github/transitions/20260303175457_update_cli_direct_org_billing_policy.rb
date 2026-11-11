# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class UpdateCliDirectOrgBillingPolicy < Base
      class Configuration < ApplicationRecord::Domain::Copilot
        self.table_name = :copilot_configurations
      end

      CLI_ENUMS = T.let({
        unconfigured: 0,
        disabled: 1,
        enabled: 2,
        no_policy: 3,
      }, T::Hash[T.untyped, T.untyped])

      CLI_DIRECT_ORG_BILLING_ENUMS = T.let({
        unconfigured: 0,
        disabled: 1,
        enabled: 2,
        no_policy: 3,
      }, T::Hash[T.untyped, T.untyped])

      iterate_over :database_table, params: {
        model_class: Configuration,
        conditions: "configurable_type = 'Business' AND cli = #{CLI_ENUMS[:no_policy]} AND cli_direct_org_billing = #{CLI_DIRECT_ORG_BILLING_ENUMS[:unconfigured]}",
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        if dry_run?
          log("Dry run: would update #{items.size} configurations")
        else
          write_to(model_class: Configuration) do
            Configuration.where(id: items.keys)
            .where("configurable_type = 'Business' AND cli = #{CLI_ENUMS[:no_policy]} AND cli_direct_org_billing = #{CLI_DIRECT_ORG_BILLING_ENUMS[:unconfigured]}")
            .update_all(cli_direct_org_billing: CLI_DIRECT_ORG_BILLING_ENUMS[:no_policy])
          end
          log("Updated #{items.size} configurations")
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

  GitHub::Transitions::UpdateCliDirectOrgBillingPolicy.new(args).run
end
