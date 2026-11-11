# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class SetNppEnterpriseSettings < Base
      include GitHub::Memoizer
      OLD_CONFIG_KEY_USER_ENABLED = "secret_scanning.lower_confidence_patterns.user_enabled"
      CONFIG_KEY_ENABLED_FOR_NEW_REPOS = "secret_scanning.lower_confidence_patterns.new_business_repos_enable"

      class ConfigurationEntry < ApplicationRecord::Domain::ConfigurationEntries
        self.table_name = "configuration_entries"
      end

      iterate_over :database_table, params: {
            model_class: ConfigurationEntry,
            conditions: "target_type = 'Business' and name = '#{OLD_CONFIG_KEY_USER_ENABLED}' and value = 'true'",
            columns: %i[target_id],
          }

      sig { override.void }
      def after_initialize
        return unless arguments[:business_ids].present?

        iterator = T.cast(self.iterator, Iterators::DatabaseTable)
        iterator.conditions += " and target_id IN (#{arguments[:business_ids]})"
      end

      sig { returns(Integer) }
      memoize def ghost_id
        User.ghost&.id || 0
      end

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        enterprise_level_configs = ConfigurationEntry.where(
          target_type: "Business",
          target_id: items.keys,
          name: CONFIG_KEY_ENABLED_FOR_NEW_REPOS,
          value: "true",
        ).pluck(:target_id).to_h


        # insert rows
        configuration_rows = (items.values.pluck(:target_id) - enterprise_level_configs.keys).map do |id|
          {
            target_type: "Business",
            target_id: id,
            name: CONFIG_KEY_ENABLED_FOR_NEW_REPOS,
            value: "true",
            updater_id: ghost_id,
          }
        end

        if dry_run?
          log "Would have created #{configuration_rows.size} configurations"
        else
          ActiveRecord::Base.connected_to(role: :writing) do
            ConfigurationEntry.insert_all(configuration_rows)
          end
        end

        log "Last business id processed: #{items.keys.last}"
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV, additional_arguments: %w(business_ids))

  GitHub::Transitions::SetNppEnterpriseSettings.new(args).run
end
