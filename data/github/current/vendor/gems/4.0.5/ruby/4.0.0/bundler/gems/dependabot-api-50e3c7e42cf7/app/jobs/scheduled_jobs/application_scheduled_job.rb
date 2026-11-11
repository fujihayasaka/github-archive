# frozen_string_literal: true

module ScheduledJobs
  class ApplicationScheduledJob < ApplicationJob
    include ActiveJob::ScheduledJob::Base
  end
end
