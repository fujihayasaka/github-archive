# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

module GitHub
  module Transitions
    class BackfillDelegatedAlertDismissalCodeScanningAll < Base
      # Backfill existing code security configurations.
      # If the configuration includes GHAS, we set the feature to 'not set'.
      # If the configuration does not include GHAS, we set the feature to 'disabled'.

      class SecurityConfiguration < ApplicationRecord::Notify
        self.table_name = :security_configurations
      end

      iterate_over :database_table, params: {
        model_class: SecurityConfiguration,
        # The target 'global' is used for GH Recommended configuration, so we ignore it.
        conditions: "code_scanning_delegated_alert_dismissal is null and target_type != 'global' and type is NULL",
        columns: [:enable_ghas],
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        with_ghas = []
        without_ghas = []
        items.each do |id, values|
          if values[:enable_ghas]
            with_ghas << id
          else
            without_ghas << id
          end
        end

        if dry_run?
          log "Would have updated #{with_ghas.size} configs to have delegated alert dismissal 'not set'"
          log "Would have updated #{without_ghas.size} configs to have delegated alert dismissal 'disabled'"
        else
          write_to(model_class: SecurityConfiguration) do
            SecurityConfiguration.where(id: with_ghas).update_all(code_scanning_delegated_alert_dismissal: 2)
          end
          write_to(model_class: SecurityConfiguration) do
            SecurityConfiguration.where(id: without_ghas).update_all(code_scanning_delegated_alert_dismissal: 0)
          end
        end

        log "Processed through id #{items.keys.max}"
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

  GitHub::Transitions::BackfillDelegatedAlertDismissalCodeScanningAll.new(args).run
end
