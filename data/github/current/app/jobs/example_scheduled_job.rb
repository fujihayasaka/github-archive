# typed: true
# frozen_string_literal: true

class ExampleScheduledJob < ApplicationJob
  schedule interval: 30.seconds, condition: -> { !GitHub.enterprise? }

  queue_as :sample_scheduled_job

  def perform
    GitHub.dogstats.increment("example_scheduled_job")
  end
end
