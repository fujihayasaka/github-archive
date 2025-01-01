# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    def peel_to_commit_or_tree(oid)
      raise TypeError, "oid must be specified" if oid.nil?
      send_message(:peel_to_commit_or_tree, oid)
    end
  end
end
