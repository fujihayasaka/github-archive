# typed: strict
# frozen_string_literal: true

module Copilot
  module Mcp
    module V1
      # Per RFC github/copilot-ecosystem#934, the v1 endpoint uses a
      # Stripe-style `X-Spec-Version` request header for additive evolution
      # within the path-major envelope (`/v1`).
      #
      # The header layout mirrors `github/mcp-registry`'s dated handler subtrees
      # (`internal/api/handlers/v0/<date>/`), but the selection mechanism here
      # is a request header so it becomes part of the public contract.
      #
      # Resolution rules (see RFC §4 "Spec-Version Negotiation"):
      #   * Absent or empty header  → resolve to `LATEST`.
      #   * Known value             → dispatch to that version's handler.
      #   * Unknown value           → resolve to `LATEST` shape, but echo the
      #                               staleness via `Deprecation` and `Warning`
      #                               response headers so clients can detect
      #                               and fix the pin.
      #
      # The resolved value is always echoed in `_meta` under
      # `com.github.copilot/spec_version`.
      module SpecVersion
        # The newest spec version currently shipping. New dated handler subtrees
        # bump this constant on release; old pins continue to receive their
        # original shape.
        LATEST = T.let("2026-05-13", String)

        # Every spec version this endpoint can serve, oldest → newest. The
        # initial release ships with a single version; the header is a no-op
        # until a second one is introduced.
        KNOWN = T.let([LATEST].freeze, T::Array[String])

        class Resolved < T::Struct
          # The spec version the handler should serve. Always a member of
          # `KNOWN`.
          const :resolved, String
          # The raw `X-Spec-Version` value the client requested, or `nil` when
          # the header was absent. Echoed in `Warning` headers when `unknown?`
          # is true so clients can correlate the response with their stale pin.
          const :requested, T.nilable(String)
          # True when the client pinned a value we do not recognize. The
          # response still carries the latest shape, but the handler must set
          # `Deprecation: true` and a `Warning: 299 …` header.
          const :unknown, T::Boolean

          sig { returns(T::Boolean) }
          def unknown?
            unknown
          end
        end

        # Resolve a raw `X-Spec-Version` header value to a known spec version.
        # Returns a Resolved struct that captures both the resolved version and
        # whether the requested value was unrecognized — see RFC §4.
        sig { params(requested: T.nilable(String)).returns(Resolved) }
        def self.resolve(requested)
          normalized = requested&.strip
          if normalized.nil? || normalized.empty?
            Resolved.new(resolved: LATEST, requested: nil, unknown: false)
          elsif KNOWN.include?(normalized)
            Resolved.new(resolved: normalized, requested: normalized, unknown: false)
          else
            Resolved.new(resolved: LATEST, requested: normalized, unknown: true)
          end
        end
      end
    end
  end
end
