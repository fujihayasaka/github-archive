# typed: true
# frozen_string_literal: true

require "sorbet-runtime"

module GitRPC
  class Backend
    class AttributeReader
      attr_reader :attributes
      attr_reader :source

      # Public: Create a new attribute reader.
      #
      # native     - GitRPC::Native instance for the repository in question.
      # source     - String tree-ish the attribute information should be
      #              sourced from.
      # attributes - Array of attributes to read for each path given. If nil
      #              or empty, no attributes are read.
      def initialize(native, source:, attributes:)
        @native = native
        @attributes = attributes
        @source = source

        @attributes ||= []
        return if @attributes.empty? # don't set up the rest of the reader, we'll always return an empty hash

        argv = [
          "git",
          "check-attr",
          "-z",
          "--stdin",
          "--source=#{@source}",
          "--end-of-options",
          *@attributes,
        ]

        @pid, @w, @r, @err = @native.spawn_piped(argv)
        @process_started = true
      rescue Errno::ENOENT => boom
        if Dir.exist?(@native.path)
          raise boom
        else
          raise GitRPC::InvalidRepository, "Does not exist: #{@native.path}"
        end
      end

      # Public: Return attribute information for this path
      #
      # path - String representing the path from root to get attributes for
      #
      # Returns a Hash mapping attribute names to their values
      def get_attributes(path)
        return {} if attributes.empty?
        @w.printf "%s\0", path
        @w.flush
        attrs = {}
        attributes.length.times do
          attr_path = @r.gets("\0", chomp: true)
          if attr_path.nil?
            begin
              # EOF, indicates Git exited with an error
              err_msg = @err.read
              if err_msg =~ /^fatal: (.*): not a valid tree-ish source$/
                raise GitRPC::InvalidObject, "Invalid tree oid #{source}"
              elsif err_msg =~ /^error: (.*): not a valid attribute name$/
                raise GitRPC::InvalidAttributeName, "Invalid attribute name #{$1}"
              elsif err_msg.include?(NOT_GIT_REPO)
                raise GitRPC::InvalidRepository, "path is not a repository: #{@native.path}"
              else
                # Unknown error, fall back on bad repo state
                raise GitRPC::BadRepositoryState, err_msg
              end
            ensure
              # Close the reader, it's no longer running
              close
            end
          end
          attr_name = @r.gets("\0", chomp: true)&.b
          attr_value = @r.gets("\0", chomp: true)&.b

          next if attr_value == "unspecified"

          if attr_value == "set"
            attr_value = true
          elsif attr_value == "unset"
            attr_value = false
          end

          attrs[attr_name] = attr_value
        end

        attrs
      end

      # Public: Free resources associated with this object.
      #
      # This must be called to kill the process and free resources.  It's
      # recommended to do so in an ensure block.
      def close
        return unless @process_started
        @w.close
        @r.close
        @err.close
        Process.waitpid @pid
        @pid = nil
        @process_started = false
        raise GitRPC::CommandBusy if $?.exitstatus == GITMON_BUSY
      rescue Errno::ECHILD, SystemCallError
      rescue Errno::ENOENT => boom
        if Dir.exist?(@native.path)
          raise boom
        else
          raise GitRPC::InvalidRepository, "Does not exist: #{@native.path}"
        end
      end
    end
  end
end
