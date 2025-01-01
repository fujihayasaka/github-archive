# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class BackfillGhesPatsExpConfiguration < Base
      class ConfigurationEntry < ApplicationRecord::Domain::ConfigurationEntries
        self.table_name = "configuration_entries"
      end

      sig { override.void }
      def perform
        unless GitHub.enterprise?
          raise RuntimeError, "This transition cannot be run outside of the enterprise runtime environment."
        end

        log "Starting transition #{self.class.to_s.underscore}"
        business = GitHub.global_business
        return log("Skipping migration. No global enterprise found") unless business
        return log("Skipping migration. Enterprise already has a limit") if business.fine_grained_personal_access_token_expiration_limit_enabled?

        unless dry_run?
          write_to(model_class: ConfigurationEntry) do
            business.set_fine_grained_personal_access_token_expiration_limit(actor: User.ghost, expiration: 366)
          end

          log "Inserted default value for FG PAT lifetime policy for #{business.name}"
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

  GitHub::Transitions::BackfillGhesPatsExpConfiguration.new(args).run
end
