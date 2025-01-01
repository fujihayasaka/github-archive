# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Mailers
    class AlertsListComponent < ApplicationComponent
      sig do
        params(
          alerts: T::Array[T.untyped],
          repository: Repository,
          limit: Integer,
          total_scan_count: T.nilable(Integer),
          skip_bottom_border: T::Boolean,
        ).void
      end
      def initialize(alerts, repository, limit, total_scan_count, skip_bottom_border = false)
        @alerts = T.let(alerts.take(limit), T::Array[T.untyped])
        @repository = repository
        @additional_alerts_count = T.let(total_scan_count.present? ? total_scan_count - limit : 0, Integer)
        @skip_bottom_border = skip_bottom_border
      end

      sig { params(alert: T.untyped).returns(String) }
      def alert_url(alert)
        repository_react_alerts_show_path(@repository.owner, @repository, alert.number)
      end
    end
  end
end
