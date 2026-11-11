# typed: true
# frozen_string_literal: true

require "minitest"
require "drb"
require "drb/unix" unless Gem.win_platform?

class FailedToCompleteAllTestsError < Minitest::UnexpectedError; end

module ActiveSupport
  module Testing
    class Parallelization # :nodoc:
      class ServerInterface
        include DRb::DRbUndumped

        MAX_FAILING_TESTS = 100

        def initialize
          @queue = Queue.new
          @in_flight = Concurrent::Map.new
          @first_run_failures = []
          @flake_first_run_map = Concurrent::Map.new
        end

        def record(worker_id, results)
          results.each do |reporter, result|
            raise DRb::DRbConnError if result.is_a?(DRb::DRbUnknown)
            @in_flight.delete([result.klass, result.name])

            if !result.passed? && !result.skipped?
              add_test_failure(result)
            end

            reporter.synchronize do
              reporter.record(result)
            end
          end
        end

        def <<(os)
          os.each do |o|
            o[2] = DRb::DRbObject.new(o[2])
          end if os
          @queue << os
        end

        def pop(worker_id)
          if !max_failures_reached? && tests = @queue.pop
            to_be_reenqueued, to_be_run = tests.partition do |test|
              worker_id_that_ran_test_first(test) == worker_id
            end
            @queue << to_be_reenqueued if to_be_reenqueued.any?
            to_be_run.each do |test|
              add_to_in_flight(test)
            end
            Jobs.new(to_be_run, @flake_first_run_map)
          end
        end

        def shutdown
          while still_testing?
            sleep 0.1
          end

          if max_failures_reached?
            STDERR.puts "=== WE'VE HIT THE MAXIMUM ALLOWED NUMBER OF TEST FAILURES! Shutting down early, some tests will not be run. ==="
          end

          @queue.close

          report_tests_left_inflight

          ParallelCollector.descendants.each do |klass|
            klass.instance.process
          end
        end

        def report_tests_left_inflight
          left_in_flight_count = @in_flight.size + @queue.length
          return if left_in_flight_count == 0

          STDERR.puts "=== #{left_in_flight_count} total suites were not completed. (#{@queue.length} left in queue and #{@in_flight.size} left in flight) ==="

          # Mark only one unreported test as a failure.
          # When tests are left in flight or in queue, it is likely there are a LOT
          # of them. If we marked all of them as failures,
          # we would have very messy output and sifting through to find the
          # failures we actually need would be difficult. Conversely, if we don't
          # flag ANY of these as failing, then we could end up with a false
          # positive green build.

          (klass, name, reporter, start_time) = if @in_flight.size > 0
            @in_flight.values.first
          else
            @queue.pop.first
          end

          if @in_flight.size > 0
            STDERR.puts "=== Outputting all tests left in flight ==="
            @in_flight.values.each do |k, n, _, _|
              STDERR.puts "Test Class: #{k}, Test Case Name: #{n}"
            end
          end

          message = left_in_flight_error_message(start_time, left_in_flight_count)

          report_left_in_flight_due_to_timeout(start_time)

          error = RuntimeError.new(message)
          error.set_backtrace([""])

          result = Minitest::Result.from(klass.new(name))
          result.time = 0
          result.failures << FailedToCompleteAllTestsError.new(error)

          reporter.synchronize do
            reporter.record(result)
          end
        end

        def left_in_flight_error_message(start_time, left_in_flight_count)
          message = if start_time
            "Test worker did not return results for this test after #{Time.now - start_time} seconds."
          else
            "This test was not run."
          end

          if left_in_flight_count > 1
            message += " An additional #{left_in_flight_count - 1} other tests were also left unreported."
          end

          message
        end

        def report_left_in_flight_due_to_timeout(start_time)
          # If there is no start time, it likely means the test was not
          # executed because we reached the max number of failures.
          # So we don't need to report it as a "timeout".
          return unless start_time
          GitHubTest.dogstats.increment("test.left_in_flight.timeout")
        end

        def max_failures_reached?
          @first_run_failures.count >= MAX_FAILING_TESTS
        end

        def still_testing?
          return false if max_failures_reached?

          return true if @queue.length != 0

          wait_for_in_flight?
        end

        MAX_SECONDS_WAITING_IN_FLIGHT = (ENV["CI_MAX_SECONDS_WAITING_IN_FLIGHT"] || 500).to_i

        def wait_for_in_flight?
          @in_flight_timer ||= Time.now
          if Time.now - @in_flight_timer > MAX_SECONDS_WAITING_IN_FLIGHT
            false
          else
            !@in_flight.empty?
          end
        end

        def run_flake_detection?
          TestEnv.run_flake_detection?
        end

        def record_exception(worker_number, worker_host, exception)
          STDERR.puts "Exception from worker: #{worker_number} #{worker_host}"
          STDERR.puts exception
          STDERR.puts exception.backtrace
        end

        def worker_id_that_ran_test_first(test)
          suite = test[0].to_s
          name = test[1]

          @flake_first_run_map[[suite, name]]
        end

        def set_job_first_run(suite, name, worker_id)
          @flake_first_run_map[[suite.to_s, name]] = worker_id
        end

        def add_to_in_flight(test)
          suite = test[0].to_s
          name = test[1]

          @in_flight[[suite, name]] = test + [Time.now]
        end

        def record_collector_data(data_by_class_name)
          data_by_class_name.each do |class_name, data|
            class_name.constantize.instance.append_data(data)
          end
        end

        def add_test_failure(result)
          @first_run_failures << result if first_run_result?(result)
        end

        def first_run_result?(result)
          result.extras[:run_type] == "first_run"
        end
      end

      class Jobs
        include Enumerable

        attr_reader :jobs

        delegate :each, :"empty?", :first, :length, to: :jobs

        def initialize(jobs, first_run_map)
          @jobs = jobs
          @first_run_map = first_run_map
        end

        def first_run_worker_id(job)
          @first_run_map[[job[0].to_s, job[1]]]
        end
      end
    end
  end
end
