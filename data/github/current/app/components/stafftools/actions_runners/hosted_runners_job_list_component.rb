# typed: true
# frozen_string_literal: true

module Stafftools
  class ActionsRunners::HostedRunnersJobListComponent < ApplicationComponent
    include SvgHelper

    # component and UI largely copied over from HostedRunners::HostedRunnersJobsListComponent and Actions::Runners::CheckRunItemComponent so that stafftools and user facing UI is separate

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
