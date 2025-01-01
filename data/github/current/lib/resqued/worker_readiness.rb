# typed: true
# frozen_string_literal: true

module Resqued
  class WorkerReadiness
    READY_ENV_VAR = "RESQUED_WORKER_POOL_READY_FILE"

    # Public. Create a file to show that this worker is ready to accept
    # jobs. This is used in Kubernetes to set a container to the Running
    # state.
    def self.report_ready
      if path = ENV[READY_ENV_VAR]
        File.open(path, "a") do |_f|
          # the file is created, success!
        end
      end
    rescue Errno::ENOENT => e
      Failbot.report(e)
    end
  end
end
