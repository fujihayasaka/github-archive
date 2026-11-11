# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    module Turboscan
      class CodeScanningSecurityAlerts < Platform::Loader
        include CodeScanningHelper

        # Return a promise for a CodeScanningSecurityAlert model.
        def self.load(issue_id, viewer)
          self.for(viewer).load(issue_id)
        end

        def initialize(viewer)
          @viewer = viewer
        end

        private

        attr_reader :viewer

        def fetch(issue_ids)
          GitHub::Turboscan.async_get_tracked_alerts(issue_ids: issue_ids).then do |resp|
            if resp&.error.present?
              GitHub.logger.error(
                "Failed to get tracked alerts from Turboscan: #{resp&.error}",
                "code.namespace" => self.class.name,
                "code.function" => __method__.to_s,
              )

              next {}
            end

            alerts_data = resp&.data || ::Turboscan::Proto::GetTrackedAlertsResponse.new # return empty response on error
            issue_alerts = {}
            viewable_checks = []

            alerts_data.issue_alerts.each do |issue_id, alert_repo_results|
              repo_alerts = []

              alert_repo_results.results.each do |repo_result|
                alert_result = repo_result.result
                next unless alert_result

                title = result_title(alert_result)
                status = if result_fixed?(alert_result)
                  "fixed"
                elsif result_resolved?(alert_result)
                  "dismissed"
                else
                  "open"
                end

                security_alert = Models::CodeScanningSecurityAlert.new(alert_result.number, title, status, repo_result.repository_id)

                viewable_checks << security_alert.async_viewable?(viewer).then do |allowed|
                  repo_alerts << security_alert if allowed
                end
              end

              issue_alerts[issue_id] = repo_alerts
            end

            Promise.all(viewable_checks).then { issue_alerts }
          end
        end
      end
    end
  end
end
