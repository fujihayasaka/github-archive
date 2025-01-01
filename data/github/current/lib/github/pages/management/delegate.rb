# typed: true
# frozen_string_literal: true

require "progeny"
require "github/pages/management"

module GitHub::Pages::Management
  class Delegate
    SSHTimeoutError = Class.new(GitHub::Pages::Management::ExecutionError)


    attr_reader :logger


    attr_reader :logged

    def initialize(logger: Logger.new(STDOUT))
      @logger = logger
      @logged = []
      nil
    end

    def log(msg)
      if l = logger
        l.info(msg)
      end
      logged << "[#{Time.now.strftime("%Y-%m-%d %H:%M:%S %z")}] pid #{$$} -- #{msg}"
      nil
    end

    def puts(msg)
      STDOUT.puts(msg)
    end

    def ssh(host, command, timeout: nil)
      child = Progeny::Command.new("ssh", "-A", "-v", host, "--", command, timeout: timeout, noexec: true)
      begin
        child.exec!
        log("ssh command `#{command}` #{child.success? ? "succeeded" : "failed"} on host #{host} #{child.success? ? "" : child.err }")
        child.success?
      rescue Progeny::TimeoutExceeded
        error = SSHTimeoutError.new("ssh command timed out after #{timeout}s")
        Failbot.report(error, {
          # currently will only go to splunk until support for this is removed https://github.com/github/security-exceptions/issues/109
          "gh.pages.fileserver.hostname" => host,
          "gh.pages.command" => command,
          "gh.pages.ssh.output" => child.out.to_s + child.err.to_s,
        })
        false
      end
    end
  end
end
