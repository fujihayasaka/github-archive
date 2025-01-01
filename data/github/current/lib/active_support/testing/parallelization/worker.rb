# typed: true
# frozen_string_literal: true

require "drb"
require "drb/unix" unless Gem.win_platform?

module ActiveSupport
  module Testing
    class Parallelization # :nodoc:
      class UndumpableException < StandardError; end
      class FailedToRecordResultError < Minitest::UnexpectedError ; end

      class GauntletFailure < Minitest::Assertion
        def initialize(error)
          # The beginning newlines look weird, but it makes the formatting nicer since
          # the message is prefixed with the string "ActiveSupport::Testing::Parallelization::GauntletFailure:"
          super <<~EOF


          This is an error from the gauntlet build check. This build check takes tests from added and modified test
          files in a pull request and runs each of them many times. The idea is to surface potential flaky tests. You
          can read more about it here:
          https://thehub.github.com/epd/engineering/products-and-services/dotcom/testing/flakes/github-gauntlet/

          Due to the nature of the build check, it may happen that you get errors that are not directly related to the
          changes in your pull request. If that is the case, you have two options:
          * Spend some time to fix the failing test, thus improving the overall quality of the test suite.
          * Ignore the failure.

          If you choose to ignore the failure, you can apply the "Skip gauntlet suite" label to your pull request and
          re-run the build check. This will make the gauntlet suite skip all work. Please ping us in the
          #dx-testing-strategy Slack channel so we know about this.

          Also, reach out to us in #dx-testing-strategy with any other questions, comments, and feedback.

          #{error.message}
          EOF

          @error = error
        end

        def backtrace
          @error.backtrace
        end

        def result_label
          "Error"
        end
      end

      class Worker
        MAX_FAILING_TESTS = 3

        def initialize(number:, url:)
          @number = number
          @worker_id = SecureRandom.uuid
          @url = url
          @to_record = []
          @failures = 0
        end

        def log(message)
          STDERR.puts "[#{@number} / #{@worker_id}] #{message}"
        end

        def start
          log "Forking worker process..."
          pid = fork do
            log "Worker process is starting..."
            DRb.stop_service

            set_process_title("(starting)")

            @host = Socket.gethostname
            @queue_server = DRb::DRbObject.new_with_uri(@url)

            log "Running after fork hooks..."
            begin
              after_fork
            rescue => setup_exception; end # rubocop:todo Lint/GenericRescue

            if setup_exception
              log "Worker process caught a setup exception."
              record_exception(setup_exception)

              # try running jobs on a different worker, since this worker is most probably broken
              requeue_jobs if ENV["TEST_WORKER_REQUEUE_JOBS"] == "true"
            else
              log "Starting to work from the queue."
              work_from_queue
            end
          rescue Exception => e # rubocop:todo Lint/GenericRescue
            log "Worker process caught an exception."
            log e
            log e.backtrace
            record_exception(e)
            raise
          ensure
            log "Worker process is cleaning up..."
            set_process_title("(stopping)")
            run_cleanup
            Process.exit!
          end
          log "Worker process forked with pid #{pid}."
          pid
        end

        private

        def after_fork
          Parallelization.after_fork_hooks.each do |cb|
            cb.call(@number)
          end
        end

        def run_cleanup
          Parallelization.run_cleanup_hooks.each do |cb|
            cb.call(@number)
          end
        end

        # Run test at various times. If test passes, exit early.
        # We run the test in the past, as that is most likely to make it pass if the test for some reason stops
        # working at a certain time (due to unexpected date logic).
        #
        # Returns result of last time shift test execution.
        def run_one_method_time_shifted(klass, method)
          result = T.let(nil, T.nilable(Minitest::Result))
          [6.hours, 12.hours, 18.hours, 24.hours].each do |time_shift|
            Timecop.travel(time_shift.ago) do
              result = Minitest.run_one_method(klass, method)
              return result if result.passed?
            end
          end
          result
        end

        def run_one_method_many_times(klass, method)
          if gauntlet_timed_out?
            log "Skipping test #{klass}##{method} because of an internal timeout."

            # Only emit one timeout event per worker
            GitHubTest.dogstats.increment("github_gauntlet.test_run_timeout") unless @gauntlet_timeout_emitted
            @gauntlet_timeout_emitted = true

            return skipped_job(klass, method)
          end

          # Only emit one start event per worker
          GitHubTest.dogstats.increment("github_gauntlet.test_run_start") unless @gauntlet_start_emitted
          @gauntlet_start_emitted = true

          # Run the same test method over and over - 50 times or 1 minute, whatever comes first.
          # We need to limit the time taken per test, otherwise a single slow test can end up
          # timing out the whole CI build.
          max_time = Time.now + 60

          failure_result = T.let(nil, T.nilable(Minitest::Result))
          has_succeeded = T.let(false, T::Boolean)
          has_failed = T.let(false, T::Boolean)
          30.times do
            result = Minitest.run_one_method(klass, method)

            if job_failed?(result)
              if result.failures.any?
                # Replace the Minitest failure with a more descriptive one
                result.failures[0] = GauntletFailure.new(result.failures[0])
              end

              has_failed = true
              failure_result ||= result
            else
              has_succeeded = true
            end

            if has_succeeded && has_failed
              GitHubTest.dogstats.increment("github_gauntlet.flake_detected")
              return failure_result
            end
            if Time.now > max_time
              GitHubTest.dogstats.increment("github_gauntlet.timeout_iterations")
              break
            end
          end

          skipped_job(klass, method)
        end

        def execute_test(klass, method, reporter, metadata)
          run_type = metadata.fetch(:run_type)
          klass.with_info_handler reporter do
            if run_type == "time_shifted"
              run_one_method_time_shifted(klass, method)
            elsif run_type == "gauntlet_retry"
              run_one_method_many_times(klass, method)
            else
              Minitest.run_one_method(klass, method)
            end
          end
        end

        def run_job(klass, method, reporter, metadata: {})
          set_process_title("#{klass}##{method}")

          result = if klass.respond_to?(:stackprof_enabled?) && klass.stackprof_enabled?
            test_result = nil
            StackProf.start(mode: klass.stackprof_mode)
            test_result = execute_test(klass, method, reporter, metadata)
            StackProf.stop
            klass.capture_stackprof_content(StackProf.results, method)
            test_result
          else
            execute_test(klass, method, reporter, metadata)
          end

          @failures += 1 if job_failed?(result) && %w[first_run gauntlet_retry].include?(metadata.fetch(:run_type))

          safe_record(reporter, result, metadata: metadata)

          set_process_title("(idle)")

          result
        end

        def gauntlet!(job)
          GitHub::DatabaseShuffler.enable if defined?(GitHub::DatabaseShuffler)
          run_job(*job, metadata: { run_type: "gauntlet_retry" })
        ensure
          GitHub::DatabaseShuffler.disable if defined?(GitHub::DatabaseShuffler)
        end

        def run_jobs(jobs)
          jobs.each do |job|
            if max_failures_reached?
              skip_job(*job)
            else
              if TestEnv.gauntlet_enabled?
                gauntlet!(job)
                next
              end

              job_metadata = {}

              first_run_worker_id = jobs.first_run_worker_id(job)

              if first_run_worker_id.nil?
                job_metadata[:run_type] = "first_run"
              else
                job_metadata[:run_type] = "different_worker"
              end

              result = run_job(*job, metadata: job_metadata)

              if first_run_worker_id.nil? && job_failed?(result) && run_flake_detection?
                @queue_server.set_job_first_run(job[0], job[1], @worker_id)

                # Run on the same worker
                run_job(*job, metadata: { run_type: "same_worker" })

                # Run on the same worker but time-shifted
                run_job(*job, metadata: { run_type: "time_shifted" })

                # Run on different worker
                begin
                  @queue_server << [job]
                rescue ClosedQueueError => exception
                  @queue_closed = true
                  log "Failed to add failed job to the work queue because the queue was closed."
                end
              end
            end
          end

          begin
            GitHub::SetupAndTeardown.last_suite_run&.run_teardown_once
          rescue => teardown_exception # rubocop:todo Lint/GenericRescue
            log "failed teardown"
          end
        end

        def job_failed?(result)
          !result.passed? && !result.skipped?
        end

        def work_from_queue
          while jobs = @queue_server.pop(@worker_id)
            run_suite(jobs)
          end
        end

        def requeue_jobs
          GitHubTest.dogstats.increment("testing_worker.requeue_jobs")
          while jobs = @queue_server.pop(@worker_id)
            begin
              @queue_server << jobs
            rescue ClosedQueueError => exception
              @queue_closed = true
              log "Failed to add a job to the work queue because the queue was closed."
            end
          end
        end

        def run_suite(jobs)
          if jobs.empty?
            log "Received an empty test suite job."
            return
          end
          fork_for_suite do
            log "Running test suite #{jobs.first[0]} with #{jobs.length} test cases."
            run_jobs(jobs)
            log "Bulk recording results for test suite #{jobs.first[0]}."
            bulk_record unless @queue_closed
          end
        end

        def fork_for_suite
          log "Forking test suite process..."
          suite_pid = fork do
            begin
              yield
            rescue Exception => e # rubocop:todo Lint/GenericRescue
              log "Exception caught during test suite run."
              log e
              log e.backtrace
              raise
            ensure
              Process.exit!
            end
          end
          log "Test suite process forked with pid #{suite_pid}."

          log "Waiting for test suite process #{suite_pid} to finish..."
          Process.waitpid suite_pid
          log "Test suite process #{suite_pid} has finished."
        end

        def run_flake_detection?
          TestEnv.run_flake_detection?
        end

        def skip_job(klass, method, reporter)
          safe_record(reporter, skipped_job(klass, method))
        end

        def skipped_job(klass, method)
          result = Minitest::Result.from(klass.new(method))
          result.time = 0
          result
        end

        def safe_record(reporter, result, metadata: {})
          begin
            Marshal::dump(result)
          rescue Exception => e # rubocop:todo Lint/GenericRescue
            # swap out result for something dumpable
            klass = result.klass.constantize
            runnable = klass.new(result.name)
            original_result = result
            result = Minitest::Result.from(runnable)
            result.time = 0

            message = +"A failure occurred and then another error occurred serializing that failure!\nUnable to dump result: #{original_result.inspect}: #{e.message}"
            begin
              original_error = original_result.failures[0]
              message << "\noriginal error message: #{original_error.message}"
              original_backtrace = original_error.backtrace
            rescue Exception => e # rubocop:todo Lint/GenericRescue
              # ignore
            end
            err = UndumpableException.new(message)
            err.set_backtrace(original_backtrace || e.backtrace)
            result.failures << FailedToRecordResultError.new(err)
          end

          result.extras[:end_time] = Time.now
          result.extras[:hostname] = @host
          result.extras[:worker_id] = @worker_id
          result.extras[:remote_worker_number] = @number
          result.extras.merge!(metadata)

          @to_record << [reporter, result]
        end

        def bulk_record
          begin
            @queue_server.record(@worker_id, @to_record)

            @queue_server.record_collector_data(
              ParallelCollector.descendants.index_with do |klass|
                klass.instance.retrieve_data
              end.transform_keys(&:name)
            )
          rescue DRb::DRbConnError => e
            log "Exception caught during bulk record."
            log e
            log e.backtrace
            record_exception(e)
          end
        end

        def record_exception(e)
          @queue_server.record_exception(@number, @host, e)
        end

        def set_process_title(status)
          Process.setproctitle("Rails test worker #{@number} - #{status}")
        end

        def max_failures_reached?
          @failures >= MAX_FAILING_TESTS
        end

        # Respect an "internal timeout" of 7 minutes, so the whole build won't time out because of
        # really slow test suites.
        def gauntlet_timed_out?
          @gauntlet_internal_timeout ||= Time.now + (7 * 60)
          Time.now > @gauntlet_internal_timeout
        end
      end
    end
  end
end
