# typed: true
# frozen_string_literal: true

module Actions
  class HostedRunners::HostedRunnersJobsListComponent < ApplicationComponent

    def initialize(jobs: [])
      @jobs = jobs
    end

    def get_os_icon_symbol(job)
      os = job[:os]

      if os.match(/mac|dar/i)
        :macos
      elsif os.match(/win/i)
        :windows
      elsif os.match(/lin|ubu/i)
        :linux
      else
        :unverified
      end
    end

  end
end
