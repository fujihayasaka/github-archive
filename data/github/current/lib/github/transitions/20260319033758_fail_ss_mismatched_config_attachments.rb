# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class FailSsMismatchedConfigAttachments < Base
      # Rows we're writing back to when updating attachment state
      class RepoSecConfig < ApplicationRecord::Notify
        self.table_name = :repository_security_configurations
      end

      # Rows we're reading from to check if SS is actually running on the repo
      class ConfigEntry < ApplicationRecord::Domain::ConfigurationEntries
        self.table_name = :configuration_entries
      end

      iterate_over :database_table, params: {
        model_class: RepoSecConfig,
        columns: %i[repository_id],
        # state 1 = attached, state 5 = enforced
        conditions: "state IN (1, 5) AND EXISTS (" \
                    "SELECT 1 FROM security_configurations sc " \
                    "WHERE sc.id = repository_security_configurations.security_configuration_id AND sc.secret_scanning = 1" \
                    ")",
      }

      attr_reader :total_processed, :total_mismatched

      def after_initialize
        @total_processed = 0
        @total_mismatched = 0
      end

      def process_batch(items)
        repo_ids = items.values.map { |v| v[:repository_id] }.uniq

        repos_with_ss_running = ConfigEntry.where(
          target_type: "Repository",
          target_id: repo_ids,
          name: "token_scanning.user_enabled",
          value: "true",
        ).pluck(:target_id).to_set

        mismatched_rsc_ids = []
        items.each do |rsc_id, values|
          next if repos_with_ss_running.include?(values[:repository_id])
          mismatched_rsc_ids << rsc_id
        end

        @total_processed += items.size
        @total_mismatched += mismatched_rsc_ids.size

        if mismatched_rsc_ids.empty?
          log "No mismatched attachments in this batch | Running totals: #{@total_processed} processed, #{@total_mismatched} mismatched"
        end

        if dry_run?
          log "Would mark #{mismatched_rsc_ids.size} attachments as failed: #{mismatched_rsc_ids.inspect}"
        else
          log "Marking #{mismatched_rsc_ids.size} attachments as failed: #{mismatched_rsc_ids.inspect}"
          write_to(model_class: RepoSecConfig) do
            RepositorySecurityConfiguration.where(id: mismatched_rsc_ids, state: [1, 5]).find_each do |rsc|
              rsc.update!(
                state: :failed,
                failure_reason: "Secret scanning was not enabled on this repository despite the configuration requiring it. " \
                               "Re-apply this configuration to retry."
              )
            end
          end
        end

        log "Processed through id #{items.keys.max} | Running totals: #{@total_processed} processed, #{@total_mismatched} mismatched"
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

  GitHub::Transitions::FailSsMismatchedConfigAttachments.new(args).run
end
