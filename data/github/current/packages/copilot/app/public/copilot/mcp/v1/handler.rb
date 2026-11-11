# typed: strict
# frozen_string_literal: true

module Copilot
  module Mcp
    module V1
      # Dispatcher for `GET /copilot/mcp_registry/v1` requests.
      #
      # Picks the appropriate dated handler based on the already-resolved spec
      # version (the route in `app/api/copilot.rb` is responsible for
      # `X-Spec-Version` resolution and for emitting `Deprecation`/`Warning`
      # headers when a client pinned an unknown value).
      #
      # New dated handlers are added by:
      #   1. Adding the new constant to `Copilot::Mcp::V1::SpecVersion::KNOWN`
      #      and updating `LATEST`.
      #   2. Adding a `handlers/handler_<date>.rb` file.
      #   3. Adding a branch here.
      module Handler
        sig { params(spec_version: String, copilot_user: ::Copilot::User, repo_nwo: T.nilable(String)).returns(T::Hash[T.any(Symbol, String), T.anything]) }
        def self.call(spec_version:, copilot_user:, repo_nwo:)
          handler_for(spec_version).call(copilot_user: copilot_user, repo_nwo: repo_nwo)
        end

        sig { params(spec_version: String).returns(Copilot::Mcp::V1::Handlers::Handler20260513) }
        def self.handler_for(spec_version)
          case spec_version
          when Copilot::Mcp::V1::Handlers::Handler20260513::SPEC_VERSION
            Copilot::Mcp::V1::Handlers::Handler20260513.new
          else
            # The spec version is resolved before reaching the dispatcher, so an
            # unknown value here means `SpecVersion::KNOWN` and the case
            # statement here are out of sync. Failing closed prevents shipping
            # a partially-wired new spec version.
            raise ArgumentError, "Unknown MCP registry v1 spec version: #{spec_version.inspect}"
          end
        end
      end
    end
  end
end
