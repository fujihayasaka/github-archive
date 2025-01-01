# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class CleanUpFeatureManagementGithubKvKeys < Base
      sig { override.void }
      def perform
        last_synced_job_override_key = "FFSJ:overrided_at".freeze
        override_key_result = GitHub.kv.get(last_synced_job_override_key).value { nil }
        if !override_key_result.nil?
          if dry_run?
            log "Tried to delete #{last_synced_job_override_key}, but dry run is enabled. Skipping..."
          else
            ActiveRecord::Base.connected_to(role: :writing) do
              GitHub.kv.del(last_synced_job_override_key)
            end

            log"Removed #{last_synced_job_override_key}"
          end
        end

        last_synced_job_updated_at_key = "FFSJ:last_updated_at".freeze
        updated_at_key_result = GitHub.kv.get(last_synced_job_updated_at_key).value { nil }
        if !updated_at_key_result.nil?
          if dry_run?
            log "Tried to delete #{last_synced_job_updated_at_key}, but dry run is enabled. Skipping..."
          else
            ActiveRecord::Base.connected_to(role: :writing) do
              GitHub.kv.del(last_synced_job_updated_at_key)
            end

            log"Removed #{last_synced_job_updated_at_key}"
          end
        end

        mysql_feature_sync_enabled = "mysql_feature_sync_enabled".freeze
        sync_enabled_key_result = GitHub.kv.get(mysql_feature_sync_enabled).value { nil }
        if !sync_enabled_key_result.nil?
          if dry_run?
            log "Tried to delete #{mysql_feature_sync_enabled}, but dry run is enabled. Skipping..."
          else
            ActiveRecord::Base.connected_to(role: :writing) do
              GitHub.kv.del(mysql_feature_sync_enabled)
            end

            log "Removed #{mysql_feature_sync_enabled}"
          end
        end

        flipper_mysql_adapter_forwarder_testmode_enabled = "flipper_mysql_adapter_forwarder_testmode_enabled".freeze
        testmode_forwarder_enabled_key_result = GitHub.kv.get(flipper_mysql_adapter_forwarder_testmode_enabled).value { nil }
        if !testmode_forwarder_enabled_key_result.nil?
          if dry_run?
            log "Tried to delete #{flipper_mysql_adapter_forwarder_testmode_enabled}, but dry run is enabled. Skipping..."
          else
            ActiveRecord::Base.connected_to(role: :writing) do
              GitHub.kv.del(flipper_mysql_adapter_forwarder_testmode_enabled)
            end

            log "Removed #{flipper_mysql_adapter_forwarder_testmode_enabled}"
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

  GitHub::Transitions::CleanUpFeatureManagementGithubKvKeys.new(args).run
end
