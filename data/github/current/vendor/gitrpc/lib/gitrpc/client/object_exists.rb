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

      if backend.disagreement_possible?
        healthy_names = backend.all_routes.select { |r| r.healthy }.map { |r| r.original_host }.to_set
        send_demux(:object_exists?, oid, type)
          .select { |route, answer| route.voting? && healthy_names.include?(route.original_host) }
          .map(&:last).all?
      else
        send_message(:object_exists?, oid, type)
      end
    end
  end
end
