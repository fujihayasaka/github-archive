require "json"
require "socket"
require "rollup"
require "minitest/reporters"

module MinitestJSONDumper
  class Reporter < Minitest::Reporters::BaseReporter
    def initialize(options = {})
      super

      @failures = 0
      @errors = 0
      @skips = 0
    end

    def format_failure(result)
      suite = result.class

      aors, aor_error = if suite.respond_to?(:areas_of_responsibility)
                          suite.areas_of_responsibility(result.failure.backtrace)
                        else
                          [[], "No #areas_of_responsibility method for #{suite.name}"]
                        end

      fingerprint_elements = [suite, result.name]
      fingerprint_elements << Rollup.generate(result.failure.error) if result.failure

      report = {
        :suite => suite.name, # a string, do we need the class object for something?
        :name => result.name,
        :areas_of_responsibility => aors,
        :areas_of_responsibility_error => aor_error,
        :message => result.failure.message,
        :location => result.failure.location,
        :duration => result.time,
        :fingerprint => Digest::MD5.hexdigest(fingerprint_elements.join("|")),
        :hostname => Socket.gethostname,
      }

      if result.failure.is_a?(Minitest::UnexpectedError)
        report[:backtrace] = result.failure.backtrace.join("\n")
        report[:exception_class] = result.failure.error.class.name
      end

      report
    end

    def record result, tag="FAILURE"
      return if result.passed? || result.skipped?
      return unless result.failure

      io.puts "",
        "===#{tag}===",
        JSON.pretty_generate(format_failure(result)),
        "===END #{tag}==="
    end

    # no-op; we've already printed the failures individually as they occur
    def report tag="FAILURE"; end
  end
end
