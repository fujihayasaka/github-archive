# typed: true
# frozen_string_literal: true

class LoggerTracker
  attr_reader :owner, :logger_calls, :codeowners, :local

  CODEOWNERS = "CODEOWNERS".freeze
  LOGGER_CALLS = [
                  "GitHub::Logger.log",
                  "GitHub::Logger.log_exception",
                  "GitHub::Logger.info",
                  "GitHub::Logger.warn",
                  "GitHub::Logger.error",
                  "GitHub::Logger.log_context",
                  "GitHub::Logger.log_with_context",
                ].freeze

  def initialize(owner, logger_calls, codeowners, local)
    @owner        = owner
    @logger_calls = logger_calls
    @codeowners   = codeowners
    @local        = local
  end

  def self.call(owner:, logger_calls: LOGGER_CALLS, codeowners: CODEOWNERS, local: false)
    new(owner, logger_calls, codeowners, local).call
  end

  def call
    results = `CODEOWNERS=#{codeowners} #{script_command}/codeowners-ls-files #{owner}`
    files = results.split("\n")
    callsites(files)
  end

  def script_command
    local ? "bin" : "script"
  end

  def callsites(files)
    files.flatten.reduce([]) do |acc, file|
      next acc unless File.exist?(file)
      next acc if file_does_not_log(file)
      callsites_for(file) do |result|
        acc << result
      end
      acc
    end
  end

  def callsites_for(file, &block)
    File.foreach(file) do |line|
      yield LoggerTracker::Result.new(file, $.) if line_makes_logger_call?(line)
    end
  end

  def line_makes_logger_call?(line)
    line.valid_encoding? && line.match?(logger_calls_regex)
  end

  def logger_calls_regex
    /#{logger_calls.join("|").gsub(".", '\.')}/
  end

  def file_does_not_log(file)
    File.fnmatch("*node_modules/*", file) ||
      File.fnmatch("*vendor/*", file) ||
      File.fnmatch("*assets/*", file) ||
      File.fnmatch("*sorbet/*", file) ||
      File.fnmatch("*db/migrate/*", file) ||
      File.fnmatch("*public/*", file) ||
      File.fnmatch("*.git*", file) ||
      File.fnmatch("*.ts", file) ||
      File.fnmatch("*.js", file) ||
      File.fnmatch("*.css", file)
  end
end
