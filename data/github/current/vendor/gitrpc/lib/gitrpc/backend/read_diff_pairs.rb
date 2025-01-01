# rubocop:disable Style/FrozenStringLiteralComment
module GitRPC
  class Backend
    # Internal: Maximum amount of time to take reading a diff.
    @blob_pairs_timeout = 8
    (class << self; attr_accessor :blob_pairs_timeout; end)

    DIFF_TRAILER = "\x00"

    rpc_reader :read_diff_pairs_with_base
    def read_diff_pairs_with_base(oid1, oid2, base_oid, delta_buffer, opts = {})
      # we don't actually use the resolved object, we just create it if it doesn't exist
      # so that the expected blobs are present when reading the diff pairs.
      resolve_base_for_diff(oid1, oid2, base_oid)

      read_diff_pairs(delta_buffer, opts)
    end

    def read_diff_pairs(delta_buffer, opts = {})
      # FIXME: After we are fully on ruby 2.7, we can remove this line that explicitly
      # stringifies as well as the matching line in client/read_diff_pairs symbolizing.
      # 2.7 will honor key types, but 2.6 does not allow string keyed hashes to be
      # splatted out for kwargs.
      opts = stringify_keys(opts)
      argv = ["--add-trailer"]
      argv << "--max-diff-size=#{opts["max_diff_size"]}" if opts["max_diff_size"]
      argv << "--max-total-size=#{opts["max_total_size"]}" if opts["max_total_size"]
      argv << "--max-diff-lines=#{opts["max_diff_lines"]}" if opts["max_diff_lines"]
      argv << "--max-total-lines=#{opts["max_total_lines"]}" if opts["max_total_lines"]
      argv << "--current-total-lines=#{opts["current_total_lines"]}" if opts["current_total_lines"]
      argv << "--current-total-size=#{opts["current_total_size"]}" if opts["current_total_size"]
      argv << "diff-pairs" << "-p" << "--full-index"
      argv << "-w" if opts["ignore_whitespace"]
      argv << "--inter-hunk-context=1"

      timeout = opts["timeout"] || Backend.blob_pairs_timeout

      result = { "data" => "", "timed_out" => false }

      child = build_git("condense-diff", argv, delta_buffer, {}, timeout)

      begin
        child.exec!
      rescue Progeny::TimeoutExceeded
        result["timed_out"] = true
      rescue Errno::ENOENT => boom
        if Dir.exist?(@path)
          raise boom
        else
          raise GitRPC::InvalidRepository, "Does not exist: #{@path}"
        end
      end

      if result["timed_out"] || child.status.success?
        result["data"] = child.out unless child.out.empty?
      elsif child.status.exitstatus == GITMON_BUSY
        raise GitRPC::CommandBusy
      elsif child.err =~ /unknown revision|bad object|fatal: unable to read/
        raise GitRPC::ObjectMissing.new(child.err)
      else
        raise GitRPC::Error, child.err
      end

      output = result["data"]
      if output && !output.empty?
        if result["timed_out"]
          # If the last line of the output was our trailer, the timeout occured
          # while we were either waiting for git to compute the diff, or
          # condense-diff to parse it.
          #
          # If the last line isn't our trailer, the timeout occured while we
          # were in the middle of reading the diff for a file, so we need to
          # walk backwards up to its header and truncate it from the output.
          unless output.end_with?(DIFF_TRAILER)
            if last_trailer_index = output.rindex(DIFF_TRAILER)
              output = output.slice(0, last_trailer_index)
            else
              # we timed out while reading the first file's diff but didn't get
              # to the end of it
              output = ""
            end
          end

          if output && output.bytesize > 0
            if !output.end_with?("\n")
              output << "\n"
            end

            output << "#timed_out\n"
            output << "Truncating diff: timeout reached.\n"
          end
        end
        output.gsub!("\n#{DIFF_TRAILER}\n", "\n")

        result["data"] = output
      end

      result
    end
  end
end
