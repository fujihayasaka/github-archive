# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# This job is for site admin testing of error processing for background jobs.
# See also BoomtownController#index
class BoomtownJob < ApplicationJob
  queue_as :boomtown

  def perform(options = {})
    if options[:cause]
      begin
        raise "the underlying cause (from a job)"
      rescue # rubocop:todo Lint/RescueException
        raise "the outer wrapper (from a job)"
      end
    else
      raise "BOOM! (from a job)"
    end
  end
end
