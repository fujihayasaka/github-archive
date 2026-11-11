# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  # Fetch a Cascade token for the codespace, ports, and scope.
  class FetchCascadeToken < Command
    attr_reader :codespace

    def initialize(codespace:, ignore_cache: false, ports: [], scope: nil)
      @codespace = codespace
      @ports = ports
      @scope = scope
      @ignore_cache = ignore_cache
    end

    def perform
      client = VscsClient.for_cascade_fetching(
        resource_provider: @codespace.plan.resource_provider,
        vscs_target: @codespace.vscs_target,
        plan: @codespace.plan,
        user: @codespace.owner
      )

      client.fetch_cascade_token(
        user: @codespace.owner,
        cache: !@ignore_cache,
        environment_id: @codespace.guid,
        ports: @ports,
        scope: @scope,
      )
    end
  end
end
