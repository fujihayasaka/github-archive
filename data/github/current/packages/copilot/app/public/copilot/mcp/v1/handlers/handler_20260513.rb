# typed: strict
# frozen_string_literal: true

module Copilot
  module Mcp
    module V1
      module Handlers
        # Handler for spec version `2026-05-13` of `GET /copilot/mcp_registry/v1`.
        #
        # This is the initial v1 dated handler subtree, mirroring
        # `github/mcp-registry`'s `internal/api/handlers/v0/2026-05-13/` layout
        # so future additive shape changes are isolated to a new dated handler
        # and old pins keep their original shape.
        #
        # The handler is intentionally thin: it fetches the legacy registry
        # list (the same data source as the unversioned
        # `GET /copilot/mcp_registry` endpoint, but with `for_v1: true`
        # filtering applied via `get_mcp_registries`), projects each entry to
        # the v1 wire shape, and wraps the result with the `_meta` envelope
        # built by `Copilot::Mcp::V1::Meta`.
        class Handler20260513
          include Copilot::Mcp::RegistryApiHelper

          SPEC_VERSION = T.let("2026-05-13", String)

          sig { params(copilot_user: ::Copilot::User, repo_nwo: T.nilable(String)).returns(T::Hash[T.any(Symbol, String), T.anything]) }
          def call(copilot_user:, repo_nwo:)
            legacy_registries = get_mcp_registries(copilot_user, repo_nwo: repo_nwo, for_v1: true)
            v1_registries = legacy_registries.map { |legacy| Copilot::Mcp::V1::Convert.from_legacy(legacy) }

            {
              mcp_registries: v1_registries.map(&:to_h),
              _meta: Copilot::Mcp::V1::Meta.build(copilot_user, SPEC_VERSION),
            }
          end
        end
      end
    end
  end
end
