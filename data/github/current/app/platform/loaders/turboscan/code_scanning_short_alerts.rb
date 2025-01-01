# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    module Turboscan
      class CodeScanningShortAlerts < Platform::Loader
        MAX_ALERTS_PER_CALL = 200

        # Return a promise for a ShortAlert hash.
        # The hash contains:
        #  :title         The title to be shown in lieu of the alert link
        def self.load(repository_id, alert_number)
          alert = [repository_id, alert_number]
          self.for.load(alert)
        end

        private

        def fetch(alerts)
          # Prepare the call to Turboscan, but limit the number of alerts
          alerts = alerts.first(MAX_ALERTS_PER_CALL)

          # Filter out alert numbers and repos that are less than 1
          filtered_alerts = alerts.select { |repo_id, alert_number| repo_id > 0 && alert_number > 0 }
          repos, numbers = filtered_alerts.transpose

          # Don't call turboscan if there are no alerts
          if repos.blank? || numbers.blank?
            return {}
          end

          response = GitHub::Turboscan.alert_titles(repository_ids: repos, alert_numbers: numbers)

          alerts_map = {}
          if response.present? && response.error.nil? && response.data.present?
            data = T.must(response.data)
            data.repository_ids.each_with_index do |repo_id, index|
              alert_number = data.alert_numbers[index]
              key = [repo_id, alert_number]
              alerts_map[key] = {
                title: data.titles[index].present? ? data.titles[index] : "Code scanning alert"
              }
            end
          end
          alerts_map
        end
      end
    end
  end
end
