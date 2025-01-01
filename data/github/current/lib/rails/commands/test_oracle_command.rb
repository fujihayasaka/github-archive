# typed: true
# frozen_string_literal: true
require "open3"
require "shellwords"

require "rails/command"
require "rails/test_unit/runner"
require "rails/test_unit/reporter"
require "github/test_finder"
require "github/test_finder/git_change_finder"
require "github/test_finder/test_oracle"
require "zip"

module Rails
  module Command
    class GitHubAPIException < StandardError; end

    class TestOracleCommand < Base

      COVMAP_FILE = Rails.root.join("tmp", "test_oracle.db")
      MAX_TEST_FILES_TO_RUN = 75
      COVMAP_BRANCH = ENV["COVMAP_BRANCH"] || "master"
      COVMAP_WORKFLOW = ENV["COVMAP_WORKFLOW"] || "test-oracle-covmap.yml"

      # 128 MiB is currently ~ 10x the size of each shard.  Codespaces reliably
      # have > 40GiB available.
      MAX_SIZE_PER_SHARD = 1024**2 * 128

      long_desc <<~MESSAGE
        Predict tests related to your changes.

        If there are uncommitted changes, find related tests to those only.
        Otherwise, find tests related to changes made since origin/master.

        By default the command will only print the test command to run.
        Use --run to actually run the tests.

        Questions or comments? -> #test-frameworks-team
      MESSAGE

      class_option :force, aliases: "-f", type: :boolean, desc: "Force running more than #{MAX_TEST_FILES_TO_RUN} test files"
      class_option :fail_fast, aliases: "-F", type: :boolean, desc: "Stop running tests after the first failure"
      class_option :reset_db, aliases: "-R", type: :boolean, desc: "Reset the local Test Oracle database and pull the latest from CI"
      class_option :run, aliases: "-r", type: :boolean, desc: "Actually run tests"
      class_option :since, aliases: "-s", type: :string, desc: "Find tests related to changes since branch or sha (default: origin/master)", banner: "BRANCH_OR_REF"
      class_option :from_pr, aliases: "-p", type: :string, required: false, desc: "Detect changed files via the GitHub API (primarily for CI fallback - a PR for the SHA must exist for this to work!)"
      class_option :engines, aliases: "-e", type: :array, desc: "Run tests for the specified engines only", banner: "ENGINE1,ENGINE2", default: %w[covmap regexp]
      class_option :rubocop, aliases: "--cop", type: :boolean, desc: "Run rubocop on relevant files"
      class_option :sorbet, aliases: "--srb", type: :boolean, desc: "Run sorbet on relevant files"
      class_option :dbpath, type: :string, desc: "Path to the Test Oracle database directory", default: Rails::root.join("tmp", "test-oracle").to_s
      class_option :verbose, aliases: "-v", type: :boolean

      def perform(...)
        ENV["DEBUG"] = "1" if options["verbose"]

        dbpath = Pathname.new(options[:dbpath])
        say "Finding related tests to the change on your branch...", :blue

        if options[:reset_db]
          say "Resetting Test Oracle database as requested...", :yellow
          File.delete(COVMAP_FILE) if File.exist?(COVMAP_FILE)
          FileUtils.rm_rf(dbpath) if Dir.exist?(dbpath)
        end

        dbs = Dir.glob "#{dbpath}/**/test-oracle-covmap.db"
        if dbs.empty?
          report_fetch_dbs(dbpath)
          dbs = Dir.glob "#{dbpath}/**/test-oracle-covmap.db"
        end
        file_size = dbs.map { |db| File.size(db) }.sum / 1024 / 1024 # In MBs
        records = record_count(COVMAP_FILE, dbpath)
        say "Using local code coverage maps (#{dbs.count} DBs, #{file_size} MBs, #{records} records).", :blue

        now = Time.now
        GitHub::TestFinder::TestOracle.metrics_count("perform", 1, ["copy:#{options[:copy]}", "since:#{options[:since]}"] + metric_tags)
        $LOAD_PATH << Rails::Command.root.join("test").to_s

        related_tests = []
        test_collection = find_related_tests_covmap(dbpath)
        low_impact_tests = test_collection.low_impact_tests
        high_impact_tests = test_collection.high_impact_tests
        high_impact_scores = test_collection.changed_files_with_high_impact

        related_tests.concat(low_impact_tests) if options[:engines].include?("covmap")
        related_tests.concat(find_related_tests_regexp) if options[:engines].include?("regexp")

        related_tests = related_tests.uniq

        if high_impact_scores.any? && !options[:force]
          say "Detected high impact changes, that affect many tests, consider pushing to CI for full run:", :yellow
          high_impact_scores.each do |changed_file, impact|
            say "  #{changed_file} (#{impact})", :yellow
          end
          say "Cowardly refusing to run tests for high impact changes. If you want to run these anyway, use --force (-f).", :yellow unless options[:force]
        end
        high_impact_suffix = high_impact_scores.any? && !options[:force] ? " Some tests were skipped due to the high impact of your changes." : ""
        related_tests.concat(high_impact_tests) if options[:force] # Add high impact tests if forced
        if related_tests.empty?
          GitHub::TestFinder::TestOracle.metrics_count("no_related_tests", 1, metric_tags)
          say "No related test files found.#{high_impact_suffix}", :yellow
          return
        end

        GitHub::TestFinder::TestOracle.metrics_count("found_total", related_tests.size, metric_tags)
        say "Detected #{related_tests.size} test files related to your changes.#{high_impact_suffix}", :blue
        # TODO: fine tune this number, maybe factoring in the test runtime we can calculated from the covmap generation
        if related_tests.size > MAX_TEST_FILES_TO_RUN && !options[:force]
          say "Too many (>#{MAX_TEST_FILES_TO_RUN}) relevant test files detected. It may take too long to run all those tests, consider pushing to CI instead. To ignore maximum test files limitation pass --force (-f) to the command.", :yellow
          return
        end

        test_arguments = build_test_arguments(related_tests)
        test_command = "bin/rails test #{test_arguments.join(" ")}"

        if options[:run]
          say "Running: `#{test_command}`", :blue
          Rails::TestUnit::Runner.parse_options(test_arguments)
          begin
            Open3.popen2e(test_command) do |_stdin, stdout_and_stderr, wait_thr|
              # say every char to the console
              stdout_and_stderr.each_char do |char|
                print char
              end
              exit_status = T.cast wait_thr.value, Process::Status
              exit(exit_status.exitstatus || 1) unless exit_status.success?
            end
          ensure
            require "webmock/minitest"
            WebMock.allow_net_connect!
          end
        else
          say "Dry run only detects relevant tests, add --run (-r) parameter to actually execute those, or copy the command:", :blue
          say "#{test_command}", :green
        end # if options[:run]
        do_rubocop if options[:rubocop]
        do_sorbet if options[:sorbet]
      rescue StandardError => e
        suggest_verbose = "Try rerunning the command with -v flag to see more details. " unless options[:verbose]
        say "Unexpected error: #{e.message}. #{suggest_verbose}For support reach out to #test-frameworks-team.", :red
        GitHub::TestFinder::TestOracle.metrics_count("error", 1, ["copy:#{options[:copy]}", "error:#{e.class}"] + metric_tags)
        raise e
      ensure
        GitHub::TestFinder::TestOracle.duration_since("perform_duration", now, ["copy:#{options[:copy]}", "since:#{options[:since]}"] + metric_tags) unless now.nil?
      end # perform

      sig { returns(T::Array[String]) }
      def metric_tags
        stdout, stderr, status = Open3.capture3("git rev-parse --abbrev-ref HEAD")
        branch = "unknown"
        if status.success?
          branch = stdout
        else
          say "Unable to check local git branch, reporting metric value for branch as '#{branch}'", :yellow
        end

        github_user = ENV["GITHUB_USER"] || "unknown"

        mode = if ENV["MULTI_TENANT_ENTERPRISE"].present?
          "MULTI_TENANT_ENTERPRISE"
        elsif File.exist?("tmp/runtime/current")
          File.read("tmp/runtime/current").chomp.upcase
        elsif ENV["ENTERPRISE"]
          "ENTERPRISE"
        else
          "DOTCOM"
        end
        [
          "ci:#{ENV["GITHUB_CI"] == "1"}",
          "run:#{options[:run] == true}",
          "engines:#{options[:engines].join}",
          "branch:#{branch}",
          "user:#{github_user}",
          "mode:#{mode}",
        ]
      end

      def self.class_options_help(*)
        super
        Minitest.run(%w(--help))
      end

      # Include the description in the banner because later, in class_options_help,
      # printing Minitest options using Minitest.run causes the process to exit.
      def self.banner(command)
        super + indented_description(command)
      end

      def self.indented_description(command)
        indented_description = command.long_description.split("\n").map do |line|
          "  #{line}"
        end

        [
          "\n\nDescription:",
          indented_description
        ].join("\n")
      end

      private

      def find_changed_rb_files
        changed_files = GitHub::TestFinder.changed_files_for(
          merge_base_ref: options["since"],
          pr_sha: options["from_pr"],
        )
        changed_files.select { |file| file.end_with?(".rb") }
      end

      def do_rubocop
        changed_files = find_changed_rb_files
        if !changed_files.empty?
          say "Running rubocop...", :blue
          test_command = "bin/rubocop --parallel --config .rubocop_ci.yml --format GitHub::JankyFormatter --except 'Primer/DeprecatedComponents' #{changed_files.join(" ")}"
          say test_command if options[:verbose]
          run_test_command(test_command)
        end
      end

      def do_sorbet
        changed_files = find_changed_rb_files
        if !changed_files.empty?
          say "Running sorbet...", :blue
          test_command = "bin/srb tc"
          say test_command if options[:verbose]
          run_test_command(test_command)
        end
      end

      def run_test_command(test_command)
        Open3.popen2e(test_command) do |_stdin, stdout_and_stderr, wait_thr|
          # say every char to the console
          stdout_and_stderr.each_char do |char|
            print char
          end
          exit_status = T.cast wait_thr.value, Process::Status
          exit(exit_status.exitstatus || 1) unless exit_status.success?
        end
      end

      def build_test_arguments(test_file_paths)
        line_number_index = args.find_index { |arg| arg.match(/:\d+$/) }
        if line_number_index
          line_number = args.delete_at(line_number_index)

          test_file_paths = test_file_paths.map do |test_file_path|
            [test_file_path, line_number].join
          end
        end

        # If fail-fast is enabled, we want to stop running tests after the first failure
        args.concat(["--fail-fast"]) if options[:fail_fast]

        args + test_file_paths
      end

      def find_related_tests_regexp
        GitHub::TestFinder.related_tests_regexp(
          merge_base_ref: options["since"],
          pr_sha: options["from_pr"],
        )
      end

      # low_impact_tests, high_impact_test, high_impact_scores
      sig { params(dbpath: Pathname, sharded_dbs_path: Pathname).returns(Integer) }
      def record_count(dbpath, sharded_dbs_path)
        GitHub::TestFinder::TestOracleMapper.new(dbpath, sharded_dbs_path).record_count
      end

      # low_impact_tests, high_impact_test, high_impact_scores
      sig { params(dbpath: Pathname).returns(GitHub::TestFinder::TestCollection) }
      def find_related_tests_covmap(dbpath)
        GitHub::TestFinder.related_tests_covmap(
          covmap_file: COVMAP_FILE,
          merge_base_ref: options["since"],
          metric_tags: metric_tags,
          pr_sha: options["from_pr"],
          sharded_covmap_path: dbpath,
        )
      end

      sig { params(target_path: Pathname).void }
      def fetch_dbs(target_path)
        now = Time.now
        db_size = 0
        FileUtils.mkdir_p(target_path.to_s)

        say "Fetching code coverage map. This is a one-time operation.", :yellow

        GitHub::TestFinder::TestOracle.log "No code coverage map detected, fetching artifacts from #{COVMAP_WORKFLOW} last run on #{COVMAP_BRANCH}"

        run_id = get_run_id(COVMAP_BRANCH, COVMAP_WORKFLOW)
        GitHub::TestFinder::TestOracle.log "Fetching artifacts from the last successful run: #{run_id}.."
        download_artifacts(run_id, target_path.to_s)
        GitHub::TestFinder::TestOracle.log "Artifacts downloaded to #{target_path}."
      ensure
        GitHub::TestFinder::TestOracle.duration_since("fetch_and_merge_duration", now, []) unless now.nil?
        GitHub::TestFinder::TestOracle.metrics_count("fetch_and_merge_db_size", db_size, []) unless db_size.nil?
      end


      sig { params(run_id: String, path: String).void }
      def download_artifacts(run_id, path)
        url = URI("https://api.github.com/repos/github/github/actions/runs/#{run_id}/artifacts")
        content_type_header = { "Accept": "application/vnd.github.v3+json" }
        auth_header = { "Authorization": "token #{token}" }

        result = Net::HTTP.get_response(url, content_type_header.merge(auth_header))

        if !result.is_a?(Net::HTTPSuccess)
          error_message = "Failed to fetch artifacts from run #{run_id}"
          GitHub::TestFinder::TestOracle.log "#{error_message}"
          GitHub::TestFinder::TestOracle.metrics_count("artifacts_fetch_failure", 1, [])
          raise GitHubAPIException, error_message
        end

        artifacts = JSON.parse(result.body)["artifacts"]
        threads = []
        artifacts.each do |artifact|
          # rubocop:disable GitHub/ThreadUse
          threads << Thread.new do
            download_url = URI(artifact["archive_download_url"])
            filename = File.join(path, artifact["name"])
            GitHub::TestFinder::TestOracle.log "Downloading artifact #{artifact["name"]} from run #{run_id} to #{filename}.."
            fetch_artifact(download_url, auth_header, filename)

            # unzip the artifact
            unzip_file("#{filename}.zip", filename)
            FileUtils.rm("#{filename}.zip")
          end
          rescue StandardError => e
            GitHub::TestFinder::TestOracle.log "Failed to download artifact #{artifact["name"]} from run #{run_id}: #{e.message}"
        end
        threads.each(&:join)
      end # download_artifacts

      def fetch_artifact(download_url, auth_header, filename, max_redirects = 3)
        request = Net::HTTP::Get.new(download_url, auth_header)
        Net::HTTP.start(download_url.host, download_url.port, use_ssl: true) do |http|
          http.request(request) do |response|
            case response
            when Net::HTTPSuccess then
              File.open "#{filename}.zip", "wb" do |io|
                response.read_body do |chunk|
                  io.write chunk.force_encoding("BINARY")
                end
              end
            when Net::HTTPRedirection then
              location = response["location"]
              # For some reason, we should _not_ provide the auth header for the redirected URL, as that makes
              # it fail. Maybe because all of the required tokens etc. are now part of the URL. :shrug:
              fetch_artifact(URI(location), {}, filename, max_redirects - 1) if max_redirects.positive?
            else
              raise "Failed to download artifact #{download_url}. HTTP status: #{response.code}"
            end
          end
        end
      end

      sig { params(branch: String, workflow_file: String).returns(String) }
      def get_run_id(branch, workflow_file)
        # https://docs.github.com/rest/actions/workflow-runs?apiVersion=2022-11-28#list-workflow-runs-for-a-workflow
        url = URI("https://api.github.com/repos/github/github/actions/workflows/#{workflow_file}/runs")

        # TODO: how we can ensure that is the LAST succesful run?
        query_params = {
          branch: branch,
          status: "success",
          per_page: 1
        }
        headers = {
          "Accept": "application/vnd.github.v3+json",
          "Authorization": "token #{token}"
        }

        url.query = URI.encode_www_form(query_params)
        response = Net::HTTP.get_response(url, headers)

        run_id = JSON.parse(response.body).dig("workflow_runs", 0, "id")
        return run_id.to_s unless run_id.nil?

        error_message = "Failed to fetch run id for workflow #{workflow_file} on branch #{branch}"
        GitHub::TestFinder::TestOracle.log "#{error_message}, response: #{response}"
        raise GitHubAPIException, error_message
      end # get_run_id

      def report_fetch_dbs(target_path)
        say "No code coverage map detected, fetching last from #{COVMAP_WORKFLOW} workflow runs..", :yellow
        fetch_dbs(target_path)
        say "Code coverage map downloaded successfully.", :yellow
      end

      sig { returns(String) }
      def token
        # Use GAUNTLET_TESTS_API_TOKEN in CI where it's available, but use GITHUB_TOKEN when run from a Codespace
        ENV.fetch("GAUNTLET_TESTS_API_TOKEN", ENV["GITHUB_TOKEN"]) || raise("No token found")
      end

      def unzip_file(file, destination)
        Zip::File.open(file) do |zip_file|
          zip_file.each do |entry|
            f_path = File.join(destination, "test-oracle-covmap.db")
            if entry.size <= MAX_SIZE_PER_SHARD && entry.name == "test-oracle-covmap.db" && !File.exist?(f_path)
              FileUtils.mkdir_p(File.dirname(f_path))
              entry.extract(destination_directory: File.dirname(f_path))
            end
          end
        end
      end
    end
  end
end
