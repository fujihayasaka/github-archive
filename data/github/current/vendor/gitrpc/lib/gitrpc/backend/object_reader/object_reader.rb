# typed: true
# frozen_string_literal: true

require "sorbet-runtime"

module GitRPC
  class Backend
    class ObjectReader
      # Public: Create a new object reader.
      #
      # native - GitRPC::Native instance for the repository in question
      # git_opts - Array of additional git command options
      # limit  - Integer maximum object size or nil
      # follow_symlinks - Boolean indicating whether to follow symlinks while reading objects
      def initialize(native, git_opts = [], limit: Backend.blob_maximum_data_size, follow_symlinks: false)
        @native = native
        @limit = limit

        command = ["cat-file", "--batch-command=%(objectname) %(objecttype) %(objectsize) %(objectmode)", "-Z"]
        command << "--follow-symlinks" if follow_symlinks

        argv = [
          "git",
          *git_opts,
          *command,
        ]

        @pid, @w, @r = @native.spawn_piped(argv)
      rescue Errno::ENOENT => boom
        if Dir.exist?(@path)
          raise boom
        else
          raise GitRPC::InvalidRepository, "Does not exist: #{@path}"
        end
      end

      # Public: Return information about this revision.
      #
      # revision - String valid Git revision
      # mode - Symbol (:info or :contents) depending on the desired information
      #
      # Returns a Hash containing some or all of the following keys:
      #
      # oid  - String object ID
      # type - Symbol (:blob, :tree, :commit, or :tag) or nil if the object is
      #        missing
      # size - Integer object size
      # filemode - Integer object mode
      # data - String object data when mode is :contents or nil if the object
      #        size exceeds the limit
      def object(revision, mode)
        if !%i[info contents].include?(mode)
          raise ArgumentError, "Invalid mode: #{mode}"
        end

        @w.set_encoding(::Encoding::BINARY)
        @w.printf "%s %s\0", mode, revision
        @w.flush
        ln = @r.gets("\0")
        return nil unless ln
        ln.chomp!("\0")
        ln = ln.b
        if ln.match(/\A[0-9a-f]+ /)
          oid, type, size, filemode = ln.split(" ")
        elsif ln.match(/^dangling [0-9]+/)
          oid, type, size, filemode = nil, "dangling", ln.split(" ")[1].to_i, nil
        elsif ln.match(/^symlink [0-9]+/)
          oid, type, size, filemode = nil, "external_symlink", ln.split(" ")[1].to_i, nil
        else
          # This is probably an error from a revision that isn't valid.
          # Split carefully, because the revision might have spaces or arbitrary
          # bytes.
          rlen = revision.bytesize
          oid, type, size, filemode = ln.byteslice(0...rlen), ln.byteslice(rlen + 1..), nil, nil
        end
        fm = filemode.nil? ? nil : filemode.to_i(8)
        type = type.to_sym
        if type == :missing
          { oid: oid, type: nil }
        elsif size.nil?
          { oid: oid, type: type }
        else
          size = size.to_i
          if mode == :info
            { oid: oid, type: type, size: size , filemode: fm }
          elsif @limit.nil? || size <= @limit || type != :blob
            data = @r.read(size)
            # Trailing NUL
            @r.read(1)
            { oid: oid, type: type, size: size, data: data, filemode: fm }
          else
            read = 0
            data = T.let("", T.nilable(String))
            while read < size && data
              to_read = [size - read, 16 * 1024].min
              data = @r.read(to_read)
              read += data&.length
            end
            @r.read(1)
            { oid: oid, type: type, size: size, data: nil, filemode: fm }
          end
        end
      end

      # Public: Free resources associated with this object.
      #
      # This must be called to kill the process and free resources.  It's
      # recommended to do so in an ensure block.
      def close
        @w.close
        @r.close
        Process.waitpid @pid
        @pid = nil
        raise GitRPC::CommandBusy if $?.exitstatus == GITMON_BUSY
      rescue Errno::ECHILD, SystemCallError
      rescue Errno::ENOENT => boom
        if Dir.exist?(@path)
          raise boom
        else
          raise GitRPC::InvalidRepository, "Does not exist: #{@path}"
        end
      end
    end
  end
end
