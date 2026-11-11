# typed: true
# frozen_string_literal: true

# This file is a backport from Rails 6.1 (it first appeared in 6.0)
# Any changes made to this file must be upstreamed to Rails.

require "drb"
require "drb/unix" unless Gem.win_platform?
require "active_support/core_ext/module/attribute_accessors"
require "active_support/testing/parallelization/server"
require "active_support/testing/parallelization/worker"

module ActiveSupport
  module Testing
    class Parallelization # :nodoc:
      @@before_fork_hooks = []

      def self.before_fork_hook(&blk)
        @@before_fork_hooks << blk
      end

      cattr_reader :before_fork_hooks

      @@after_fork_hooks = []

      def self.after_fork_hook(&blk)
        @@after_fork_hooks << blk
      end

      cattr_reader :after_fork_hooks

      @@run_cleanup_hooks = []

      def self.run_cleanup_hook(&blk)
        @@run_cleanup_hooks << blk
      end

      cattr_reader :run_cleanup_hooks

      def initialize(worker_count, server: true, url: "drbunix:", drb: DRb)
        @worker_count = worker_count
        @worker_pool = []
        @server = server
        @all_tests  = []

        @url = url
        if server
          @queue_server = ServerInterface.new
          @url = drb.start_service(url, @queue_server).uri
        end
      end

      def before_fork
        Parallelization.before_fork_hooks.each(&:call)
      end

      def start
        before_fork
        wait_for_server unless @worker_count.zero?

        STDERR.puts "Starting #{@worker_count} workers on #{Socket.gethostname} using #{@url}"
        @worker_pool = @worker_count.times.map do |worker|
          Worker.new(number: worker, url: @url).start
        end
      end

      def <<(work)
        return unless @server
        @all_tests << work
      end

      def size
        @worker_count
      end

      def shutdown
        if @server
          fill_queue
          @queue_server.shutdown
        end

        STDERR.puts "Waiting for child processes to finish..."
        @worker_pool.each do |pid|
          STDERR.puts "Waiting for child process #{pid} to finish..."
          Process.waitpid pid
          STDERR.puts "Child process #{pid} has finished."
        end
        STDERR.puts "All child processes have finished."
      end

      def stats_file
        ENV["PARALLEL_TEST_STATS"] || ".parallel_test_stats"
      end

      def wait_for_server(timeout = 600)
        return if server_up?

        timeout.times do
          STDERR.puts "waiting for queue server..."
          sleep 1
          if server_up?
            puts
            return
          end
        end

        puts
        raise "Server not running after #{timeout} seconds"
      end

      def server_up?
        uri = URI.parse(@url)
        return true if uri.scheme == "drbunix"

        socket = TCPSocket.open(T.must(uri.host), T.must(uri.port))
        socket.close
        true
      rescue Errno::ECONNREFUSED
        false
      end

      def fill_queue
        suite_collection = suites_ordered_by_provided_manifest || suites_ordered_by_duration
        tests_sorted_by_collection(suite_collection).each do |suite|
          @queue_server << suite
        end
      end

      # There's a lot of connascence being assumed here. To help reason about this method,
      # I've left comments of how some of these data structures look
      #
      def tests_sorted_by_collection(collection)
        # @all_tests looks like:
        # [[SuiteClass, "test_method_name", <# Reporter>], [SuiteClass, "test_method_name2", <# Reporter>]]
        all_tests_by_suite = @all_tests.group_by { |t| t.first.to_s }

        # We transform it to group by the Suite
        # { SuiteClass: [[SuiteClass, "test_method_name", <# Reporter>], [SuiteClass, "test_method_name2", <# Reporter>]] }

        sorted_suites = []

        Array.wrap(collection).each do |suite_name|
          if tests = all_tests_by_suite[suite_name]
            sorted_suites << tests
            all_tests_by_suite.delete(suite_name)
          end
        end

        if ENV["SUITE_ORDER"].present?
          return sorted_suites
        end

        if all_tests_by_suite.present?
          GitHubTest.dogstats.count("missing_test_suite_durations", all_tests_by_suite.size)
          STDERR.puts "Missing duration stats for #{all_tests_by_suite.size} suites"
        end

        sorted_suites + all_tests_by_suite.values.shuffle
      end

      def suites_ordered_by_duration
        if stats = load_stats
          stats.sort_by { |stats_suite| -stats_suite[:duration] }.map { |h| h[:name] }
        end
      end

      def suites_ordered_by_provided_manifest
        ENV["SUITE_ORDER"]&.split(",").presence
      end

      def load_stats
        begin
          if TestEnv.github_ci?
            downloaded = download_stats || download_stats(branch: "master")
            STDERR.puts "No stats file downloaded" unless downloaded
          end
          File.open(stats_file, "rb") { |f| Marshal.load(f) }
        rescue Errno::ENOENT, EOFError, TypeError, ArgumentError => e
          STDERR.puts "No stats file found."
          STDERR.puts "#{e}: #{e.message}"
          STDERR.puts e.backtrace
          STDERR.puts
        end
      end

      def download_stats(branch: ENV["BUILD_BRANCH"])
        system({ "SKIP_SAFE_MODE" => "1" }, "script/ci/cache", "read", "--name", "parallel-test-stats", "--key-string", branch, stats_file)
      end
    end
  end
end
