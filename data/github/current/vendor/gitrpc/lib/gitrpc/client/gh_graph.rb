# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Public: Return detailed commit log data covering <sha> history.
    #
    # oid - a String commit oid
    #
    # Returns array of data formatted as described by GitRPC::Backend::GraphData#process
    def gh_graph_data(oid, version: 1)
      return [] if oid.nil?

      ensure_valid_full_oid(oid)
      send_message(:gh_graph_data, oid, version: version)
    end

    # Public: clears the graph cache
    #
    # Returns nothing
    def clear_graph_cache
      send_message(:clear_graph_cache)
    end

    def async_clear_graph_cache
      async_send_message(:clear_graph_cache)
    end
  end
end
