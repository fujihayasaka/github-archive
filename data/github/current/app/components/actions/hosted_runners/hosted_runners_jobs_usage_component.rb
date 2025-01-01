# typed: true
# frozen_string_literal: true

module Actions
  class HostedRunners::HostedRunnersJobsUsageComponent < ApplicationComponent
    def initialize(concurrency_limit: 10, jobs: [])
      @concurrency_limit = concurrency_limit
      @jobs = jobs
    end

    # TODO: Update with actual concurrency limit or remove from view
    def mac_jobs_limit
      5
    end

    def mac_limit_reached?
      job_types_counts["macOS"] >= mac_jobs_limit
    end

    def job_types_counts
      {
        "macOS" => @jobs.count { |job| job[:os].match(/mac|dar/i) },
        "Linux" => @jobs.count { |job| job[:os].match(/lin|ubu/i) },
        "Windows" => @jobs.count { |job| job[:os].match(/wind/i) },
      }
    end

    def system_colors
      [
        {
          name: "Linux",
          color: :danger,
          bg: :danger_emphasis
        },
        {
          name: "Windows",
          color: :attention,
          bg: :attention_emphasis,
        },
        {
          name: "macOS",
          color: :accent,
          bg: :accent_emphasis,
        }
      ]
    end
  end
end
