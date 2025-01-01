# typed: true
# frozen_string_literal: true

module GitRPC
  class Backend
    MODIFIED_BLOBS_MATCHER = %r{(
      (?<status>[CR])
      (?<similarity>\d{3})
      \x00(?<src_path>[^\x00]+)\x00(?<dst_path>[^\x00]+)\x00
      |
      (?<status>[M])
      \x00(?<src_path>[^\x00]+)\x00
      |
      (?<status>[ADTUX])
      \x00(?<src_path>[^\x00]+)\x00
    )}x
    # Public: Finds all blobs which were changed between two commit oids.
    # Each hash returned will at least have a 'modified_status' key
    # denoting an addition, modification, rename, copy, deletion or type
    # change.
    #
    # A 'path' key is also returned which is the full nested path to the blob.
    # For deletions only the 'modified_status' and 'path' keys are returned.
    # For all other types of changes which result in a new blob, the new
    # blob's oid is included as 'oid'.
    #
    # When a modification does not result in a new blob (for example,
    # when a submodule is modified, or a path that was a blob changes
    # type and becomes a submodule), the 'oid' key is not returned.
    #
    # All modifications that aren't deletions are stored under the 'modified'
    # key of the returned hash.
    #
    # All deletions are stored under the 'deleted' key.
    #
    # before - The old commit oid
    # after - The new commit oid
    #
    # Returns an array of simple hashes representing the blobs that changed.
    rpc_reader :modified_blobs
    def modified_blobs(before, after)
      begin
        ensure_valid_oid(before)
        ensure_valid_oid(after)
      rescue GitRPC::InvalidOid
        raise ::GitRPC::ObjectMissing
      end

      modifications = {
        "modified" => [],
        "deleted" => []
      }

      ret = spawn_git("diff", ["-z", "--name-status", before, after])

      if ret["ok"]
        diff_status = ret["out"]
      else
        if ret["err"] =~ /unknown revision|bad object/
          # XXX we don't know which commit was missing in a range of 2 commits
          raise GitRPC::ObjectMissing.new(ret["err"])
        else
          return modifications
        end
      end

      scanner = StringScanner.new(diff_status)

      while scanner.scan(MODIFIED_BLOBS_MATCHER)
        status = scanner["status"]
        path   = scanner["dst_path"] || scanner["src_path"]

        hash = {
          "modified_status" => status,
          "path"            => path,
        }

        case status
        when "A", "M", "C", "R", "T"
          oid = blob_oid_by_path(after, path)
          hash["oid"] = oid if oid
          modifications["modified"] << hash
        when "D"
          modifications["deleted"] << hash
        end
      end

      modifications
    end

    def blob_oid_by_path(commit_oid, path)
      tree = rugged.lookup(commit_oid).tree
      obj = tree.path(path)
      obj[:type] == :blob ? obj[:oid] : nil
    rescue Rugged::OdbError, Rugged::TreeError => boom
      raise GitRPC::ObjectMissing.new(boom.message, commit_oid)
    end
  end
end
