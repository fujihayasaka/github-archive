# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Public: Check if object exists in the repository.
    #
    # oid - String OID
    # type - "commit", "tree", "blob", "tag" or nil
    #
    # Returns true if object exists with specific type or false.
    def object_exists?(oid, type = nil)
      ensure_valid_full_oid(oid)

      send_message(:object_exists?, oid, type)
    end
  end
end
