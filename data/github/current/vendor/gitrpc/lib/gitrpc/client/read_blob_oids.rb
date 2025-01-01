# frozen_string_literal: true
# typed: true

module GitRPC
  class Client

    # Public: Returns the blob oid for the the given commit and path combination
    #
    # commit_oid - a String commit_oid
    # path - a String path
    #
    # Options:
    #
    # skip_bad: when true, entries that have problems being resolved are set to nil instead of
    #   the entire operation failing.
    #
    # Returns the blob oid or nil if the blob does not exist for the given commit and path
    def read_blob_oid(commit_oid, path, opts = {})
      read_blob_oids([[commit_oid, path]], **opts).first
    end

    # Public: Use this to resolve a batch of commit_oid and path pairs to blob oids.
    #
    # positioning_data - an array of 2 element arrays containing the commit oid as the first element
    #   and the path as the second, as described in read_blob_oid
    #
    # See read_blob_oid for more info, above
    #
    # Returns an array of blob oids corresponding to the array of pairs given as a parameter
    def read_blob_oids(positioning_data, skip_bad: false)
      positioning_data.each { |commit_oid, _| ensure_valid_full_oid(commit_oid) }

      opts = { "skip_bad" => skip_bad }

      send_message(:read_blob_oids, positioning_data, opts)
    end
  end
end
