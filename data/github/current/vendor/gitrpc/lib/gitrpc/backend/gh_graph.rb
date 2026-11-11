# frozen_string_literal: true
# typed: true

require_relative "gh_graph/graph_data"
require_relative "contribution_caches"

module GitRPC
  class Backend
    rpc_reader :gh_graph_data
    def gh_graph_data(oid, version: 1)
      ensure_valid_full_oid(oid)
      GraphData.new(self, oid, version: version).process
    end

    rpc_writer :clear_graph_cache
    def clear_graph_cache
      GitRPC::Backend::ContributionCaches.new(self).clear
    end
  end
end
