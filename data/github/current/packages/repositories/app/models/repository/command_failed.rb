# typed: true
# frozen_string_literal: true

class Repository
  class CommandFailed < StandardError
    # The full git command that failed as a String.
    attr_reader :command

    # The integer exit status.
    attr_reader :exitstatus

    # Everything output on the command's stderr as a String.
    attr_reader :err

    def needs_redacting?
      true
    end

    def initialize(command, exitstatus = nil, err = "")
      if exitstatus
        @command = command
        @exitstatus = exitstatus
        @err = err
        message = "Command failed [#{exitstatus}]: #{command}".dup
        message << "\n\n" << err unless err.nil? || err.empty?
        super message
      else
        super command
      end
    end

    def info
      { command: command, exitstatus: exitstatus, err: err }
    end
  end
end
