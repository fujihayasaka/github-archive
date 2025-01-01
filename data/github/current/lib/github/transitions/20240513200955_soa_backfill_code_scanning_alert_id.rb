# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class SoaBackfillCodeScanningAlertId < Base
      class CodeScanningRevisions < ApplicationRecord::SecurityOverviewAnalytics
        self.table_name = :soa_code_scanning_alert_revisions
      end

      iterate_over :database_table, params: {
        model_class: CodeScanningRevisions,
        conditions: "alert_id = 0",
        columns: %i[repository_id alert_number],
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        log "#{dry_run? ? "Would be updating" : "Updating"} revisions from #{items.keys.first} to #{items.keys.last}"
        items.values.uniq.group_by { |r| r[:repository_id] }.each do |repository_id, alerts|
          count = 0
          log "#{dry_run? ? "Would be updating" : "Updating"} revisions with repo id #{repository_id}"

          alerts.each do |alert|
            log "#{dry_run? ? "Would be updating" : "Updating"} revisions with repo id #{repository_id} and alert number #{alert[:alert_number]}"

            revisions = CodeScanningRevisions.where(repository_id:, alert_number: alert[:alert_number], alert_id: 0)
            unless dry_run?
              write_to(model_class: CodeScanningRevisions) do
                revisions.update_all(alert_id: alert[:alert_number])
              end
            end

            count += revisions.count
            log "#{dry_run? ? "Would have updated" : "Updated"} #{count} revisions for repo id #{repository_id} and alert number #{alert[:alert_number]}"
          end

          log "#{dry_run? ? "Would have updated" : "Updated"} a total of #{count} revisions for repo id #{repository_id}"
        end

        log "end of batch"
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

  GitHub::Transitions::SoaBackfillCodeScanningAlertId.new(args).run
end
