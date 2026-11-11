# typed: false
# frozen_string_literal: true

module GitHub
  # The GitHub::Rsync module adds #rsync and #rsync_command methods to the class
  # where it is included and assists in copying files locally or across a
  # network.
  #
  # Usage:
  #
  # copy everything in /foo to /bar
  # => rsync from: "/foo", to: "/bar"
  #
  # supports filters: copy all directories in /foo to /bar
  # => rsync from: "/foo", to: "/bar", filters: [ "-! */" ]
  #
  # supports exclude: copy everything except tmp from /foo to /bar
  # => rsync from: "/foo", to: "/bar", exclude: [ "/tmp" ]
  module Rsync

    # Public: Rsyncs files in 'from' path to 'to' path respecting any 'exclude'
    # and 'filters' rules.
    #
    # from    - Pathname or String path of source files and directories.
    # to      - Pathname or String path of destination.
    # exclude - Array of strings for rsync --exclude option.
    # filters - Array of strings for rsync --filter option.
    #
    # Returns a Progeny::Command instance.
    def rsync(args)
      command = rsync_command(**args)
      child   = Progeny::Command.new(*command)

      if !child.success?
        error = ChildProcessError.new("#{command.join(" ")}: #{child.status.inspect}\n\nSTDOUT:\n#{child.out}\nSTDERR:\n#{child.err}")

        # Log full message to splunk, but generic message to sentry
        GitHub::Logger.log_exception({ class: error.class.name }, error)
        raise ChildProcessError, "Error running rsync command"
      end

      child
    end

    # Public: Build Array of strings representing rsync command.
    #
    # from    - Pathname or String path of source files and directories.
    # to      - Pathname or String path of destination.
    # options - Array of rsync option strings to include
    # exclude - Array of strings for rsync --exclude option.
    # filters - Array of strings for rsync --filter option.
    #
    # Returns an Array.
    def rsync_command(from:, to:, options: [], exclude: [], filters: [])
      from, to = [from.to_s, to.to_s]

      # Make sure that rsync doesn't add an extra dir into the dir hierarchy.
      if !from.end_with?("/")
        from = from + "/"
      end

      command = ["rsync", "-av", "--stats"]
      command += options
      exclude.each { |pattern| command += ["--exclude", pattern] }
      filters.each { |rule| command += ["--filter", rule] }
      command += [from, to]

      command
    end

    class ChildProcessError < StandardError; end
  end
end
