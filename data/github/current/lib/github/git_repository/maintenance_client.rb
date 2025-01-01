# typed: true
# frozen_string_literal: true

module GitHub
  module GitRepository
    class MaintenanceClient
      include GitHub::FlipperActor
      include GitHub::VexiActor
      include ::GitRepository::SpokesAdapter

      def initialize(repo, rpc)
        @repo = repo
        @rpc = rpc
      end

      # Use the maintenance RPC
      def rpc
        @rpc
      end

      # Delegate everything else needed by the SpokesAdapter & FlipperActor/VexiActor
      delegate(
        :flipper_id,
        :vexi_id,
        :is_a?,
        :id,
        :repo_name,
        :class,
        to: :@repo
      )
    end
  end
end
