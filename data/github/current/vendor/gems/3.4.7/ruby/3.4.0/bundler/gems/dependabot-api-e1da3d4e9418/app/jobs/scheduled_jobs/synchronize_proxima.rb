# frozen_string_literal: true

module ScheduledJobs
  class SynchronizeProxima < ApplicationScheduledJob
    queue_as :default

    schedule interval: 5.minutes

    def perform
      return unless Dependabot.proxima?

      response = Excon.get(
        Dependabot::Application.dotcom_proxima_sync_endpoint,
        idempotent: true,
        accepts: "application/json",
        retry_limit: 6,
        retry_interval: 5,
      )

      if response.status == 200
        response_body = JSON.parse(response.body, symbolize_names: true)

        response_body[:ecosystem_versions].each do |setting|
          UpdaterVersion.upsert({
                                  env: UpdaterVersion.envs[:prod],
                                  ecosystem: setting[:ecosystem],
                                  version: setting[:version],
                                })
        end
      else
        Dependabot::Logger.error("Failed to sync proxima settings")
      end
    end
  end
end
