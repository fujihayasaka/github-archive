# typed: true
# frozen_string_literal: true
require "open3"

require "rails/command"
require "rails/test_unit/runner"
require "rails/test_unit/reporter"
require "github/test_finder"
require_relative "../../../script/dx/telemetry/datadog"

module Rails
  module Command
    class TestChangesCommand < Base
      long_desc <<~MESSAGE
        Run tests related to your changes.

        If there are uncommitted changes, find and run related tests.
        Otherwise, find and run tests related to changes made since master.
      MESSAGE

      class_option :copy, aliases: "-c", type: :boolean, desc: "Copy test command to clipboard"
      class_option :since, aliases: "-s", type: :string, desc: "Run tests related to changes since branch (default: master)", banner: "BRANCH_OR_REF"
      class_option :verbose, aliases: "-v", type: :boolean

      def perform(...)
        ENV["DEBUG"] = "1" if options["verbose"]
        metrics.submit_count("test_changes.perform", Time.now.to_i, 1, ["copy:#{options[:copy]}", "since:#{options[:since]}"])
        $LOAD_PATH << Rails::Command.root.join("test").to_s

        # Let users know about Test Oracle which includes test_changes functions
        say "test_changes (tc) functionality is included in the test_oracle command. Test Oracle will help you better find relevant tests to run. Read more here: https://gh.io/test_oracle", :magenta

        related_tests = find_related_tests
        if related_tests.empty?
          metrics.submit_count("test_changes.no_related_tests", Time.now.to_i, 1)
          say "No related test files found.", :yellow
          return
        else
          metrics.submit_count("test_changes.found_total", Time.now.to_i, related_tests.size)
        end

        test_arguments = build_test_arguments(related_tests)
        test_command = "bin/rails test #{test_arguments.join(" ")}"

        if options[:copy]
          copy_to_clipboard(test_command)
        else
          say test_command, :blue
          prepare_argv_for_minitest
          Rails::TestUnit::Runner.parse_options(test_arguments)
          Rails::TestUnit::Runner.run(test_arguments)
        end
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

      def metrics
        @metrics ||= DX::Datadog::MetricsBackend.new
      end

      def build_test_arguments(test_file_paths)
        line_number_index = args.find_index { |arg| arg.match(/:\d+$/) }
        if line_number_index
          line_number = args.delete_at(line_number_index)

          test_file_paths = test_file_paths.map do |test_file_path|
            [test_file_path, line_number].join
          end
        end

        args + test_file_paths
      end

      # Mutate ARGV, removing arguments that this command expects but minitest will complain about if present.
      def prepare_argv_for_minitest
        # args includes everything that wasn't consumed by this command's option parser
        minitest_args = args
        minitest_args << "--verbose" if options[:verbose]

        ARGV.reject! { |_| true }
        minitest_args.each do |arg|
          ARGV << arg
        end
      end

      def find_related_tests
        GitHub::TestFinder.related_tests_regexp(
          merge_base_ref: options["since"],
          pr_sha: nil
        )
      end

      def copy_to_clipboard(command)
        begin
          _stdout, _stderr, _ = Open3.capture3("pbcopy", stdin_data: command)
          say "Command copied to clipboard: ", nil, false # No newline
          say command, :blue
        rescue Errno::ENOENT => e
          say "#{e}"
          say "Failed to copy command to clipboard: ", :red, false # No newline
          say command
        end
      end
    end
  end
end
