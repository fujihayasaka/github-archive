# typed: true
# frozen_string_literal: true

module GitRPC
  class Backend
    # Returns a map of blob lookup data to maps of position mappings. See
    # client documentation and reducer output for details.
    #
    # NOTE: This endpoint is used for both read_adjusted_positions and
    # read_commit_adjusted_positions
    rpc_reader :read_adjusted_positions
    def read_adjusted_positions(positioning_data, options = {})
      skip_bad = !!options["skip_bad"]

      positioning_data.each_with_object({}) do |row, oid_mappings|
        # Get source & destination
        positions, source, destination = row
        adjusted_positions = adjust_positions(positions, source, destination, skip_bad:)
        oid_mappings[[source, destination]] = Hash[positions.zip(adjusted_positions)]
      end
    end

    def adjust_positions(positions, source, destination, skip_bad:)
      source_blob = parse_target(source)
      dest_blob = parse_target(destination)

      # Get the adjusted line numbers from Git
      linenos = positions.map { |p| p + 1 }
      res = spawn_git("diff-positions",
                      ["--max-blob-size=1m", "--end-of-options", source_blob, dest_blob],
                      linenos.join("\n"),
                      {}, nil, nil,
                      ["-c", "diff.indentHeuristic=false"])
      err = res["err"].chomp
      if res["ok"]
        res["out"].split("\n").map do |adjusted|
          new_lineno = adjusted.to_i
          new_lineno == -1 ? nil : new_lineno - 1
        end
      elsif res["status"] == 1
        # A status of 1 when --max-blob-size is specified means one or both
        # blobs exceeded the max size. To match Rugged behavior, just return
        # the unmodified positions.
        positions
      elsif err =~ /^fatal: ([0-9a-f]+) is not a valid object$/
        raise GitRPC::ObjectMissing.new("Cannot load blob for source #{source_blob}, destination #{dest_blob}", $1)
      elsif err =~ /^fatal: ([0-9a-f]+) is not a valid 'blob' object$/ || err =~ /^fatal: invalid object name '(.*)'.$/
        raise GitRPC::InvalidObject.new(err, $1)
      elsif err =~ /^fatal: path '(.*)' does not exist in '.*'$/ || err =~ /^fatal: path '(.*)' exists on disk, but not in '.*'$/
        raise GitRPC::NoSuchPath, $1
      else
        raise GitRPC::Failure, GitRPC::CommandFailed.new(res)
      end
    rescue GitRPC::InvalidObject, GitRPC::ObjectMissing, GitRPC::NoSuchPath => e
      return Array.new(positions.count, :bad) if skip_bad
      fail e
    end

    def parse_target(target)
      if target.is_a?(String)
        target
      else
        path = target[:path]
        treeish = if target[:start_commit_oid] && target[:end_commit_oid]
          start_commit_oid = target[:start_commit_oid]
          end_commit_oid   = target[:end_commit_oid]
          base_commit_oid  = target[:base_commit_oid]
          resolve_base_oid(start_commit_oid, end_commit_oid, base_commit_oid)
        else
          target[:commit_oid]
        end

        "#{treeish}^{tree}:#{path}"
      end
    end
  end
end
