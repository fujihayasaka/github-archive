# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class AqueductTestJob < ApplicationJob
  self.queue_adapter = :aqueduct

  queue_as :aqueduct_test

  retry_on_dirty_exit

  redeliver_after 2.minutes

  ::AqueductTestJob::MONITOR_JOB_INTERVAL = 5.seconds

  # Optional arguments are:
  #
  #   "message" - print a message to the log
  #   "allocate" - allocate this many bytes to take up memory
  #   "sleep" - sleep this long before exiting
  #   "query" - execute a query against mySQL to check that the DB is working
  #   "raise" - set to truthy to raise an exception from the job
  def perform(args = {})
    args.stringify_keys! # allow symbols, but strip them internally

    if args["message"]
      Rails.logger.info "Got message: #{args["message"]}"
    end

    if args["allocate"].to_i > 0
      Rails.logger.info "Allocating #{args["allocate"]} bytes"
      string = "x" * args["allocate"].to_i
      string.upcase!
    end

    if args["sleep"].to_i > 0
      Rails.logger.info "Sleeping for #{args["sleep"]} seconds"
      sleep args["sleep"].to_i
    end

    if args["query"]
      User.connection.select_value(<<-SQL)
        SELECT 1 FROM users
      SQL
    end

    if args["raise"]
      Rails.logger.info "Raising an exception"
      raise "aqueduct-test-job-kaboom"
    end
  end
end
