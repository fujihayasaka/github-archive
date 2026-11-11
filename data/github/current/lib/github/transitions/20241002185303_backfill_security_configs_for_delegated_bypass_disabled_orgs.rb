# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class BackfillSecurityConfigsForDelegatedBypassDisabledOrgs < Base
      include GitHub::Memoizer

      CONFIG_KEY_USER_ENABLED = "secret_scanning.delegated_bypass.user_enabled"

      class ConfigurationEntry < ApplicationRecord::Domain::ConfigurationEntries
        self.table_name = "configuration_entries"
      end

      class SecurityConfiguration < ApplicationRecord::Notify
        self.table_name = "security_configurations"
      end

      iterate_over :database_table, params: {
        model_class: SecurityConfiguration,
        conditions: "target_type != 'global'",
        columns: %i[id target_id secret_scanning_push_protection],
      }

      # This transition iterates over all non-global security configurations, in order to update those that are part
      # of organizations with delegated bypass disabled. It updates their security configurations'
      # `secret_scanning_delegated_bypass` value based on the parent feature (`secret_scanning_push_protection`) value.
      #
      # Relies on the default `start_id`, `end_id`, and `process_batch_size` arguments for iterating over Organization.
      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        all_security_config_ids = items.keys
        all_org_ids = items.values.pluck(:target_id).uniq

        enabled_org_ids = ConfigurationEntry.where(name: CONFIG_KEY_USER_ENABLED, target_type: "User", value: "true", target_id: all_org_ids).pluck(:target_id)
        disabled_org_ids = (all_org_ids - enabled_org_ids).to_set

        security_config_ids_to_disable = []
        security_config_ids_to_not_set = []

        items.each_pair do |security_config_id, value|
          next unless disabled_org_ids.include?(value[:target_id])
          if value[:secret_scanning_push_protection] == 0
            # Push protection is disabled
            security_config_ids_to_disable << security_config_id
          elsif value[:secret_scanning_push_protection] == 1 || value[:secret_scanning_push_protection] == 2
            # Push protection is enabled or not_set
            security_config_ids_to_not_set << security_config_id
          end
        end

        if dry_run?
          log "Would have updated #{security_config_ids_to_disable.length} security configurations to secret_scanning_delegated_bypass = 'disabled'"
          log "Would have updated #{security_config_ids_to_not_set.length} security configurations to secret_scanning_delegated_bypass = 'not_set'"
        else
          write_to(model_class: SecurityConfiguration) do
            SecurityConfiguration.where(id: security_config_ids_to_disable).update_all(secret_scanning_delegated_bypass: 0)
            SecurityConfiguration.where(id: security_config_ids_to_not_set).update_all(secret_scanning_delegated_bypass: 2)
          end
        end

        log "Last security config id processed: #{all_security_config_ids.last}"
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

  GitHub::Transitions::BackfillSecurityConfigsForDelegatedBypassDisabledOrgs.new(args).run
end
