# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class UpdateGrcForDelegatedBypass < Base

      class SecurityConfigurationTable < ApplicationRecord::Notify
        self.table_name = "security_configurations"
      end

      sig { override.void }
      def perform
        grc = SecurityConfigurationTable.where(target_type: "global", target_id: 0).first
        if grc.nil?
          log "No recommended security configuration found"
          return
        end
        if dry_run?
          log "Would have updated security configuration with ID #{grc.id} to secret_scanning_delegated_bypass = 'not_set'"
        else
          write_to model_class: SecurityConfiguration do
            # Set the default value to 2 (not_set)
            SecurityConfigurationTable.where(id: grc.id).update(secret_scanning_delegated_bypass: 2)
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

  GitHub::Transitions::UpdateGrcForDelegatedBypass.new(args).run
end
