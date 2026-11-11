# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    module Loops
      # Service-backed loader for Loops::Loop objects keyed by uuid and viewer.
      # Performs a single fetch per (viewer.id, uuid) within a request.
      class Loop
        class << self
          # Public entry point
          def load(uuid, viewer:)
            cache_key = [viewer.id, uuid]
            request_cache[cache_key] ||= begin
              fetch(uuid, viewer)
            end
          end

          private

          def fetch(uuid, viewer)
            return nil unless viewer.is_a?(::User)
            ::Loops::Client.new(user: viewer).fetch_loop(loop_id: uuid, version_constraint: ">=0.0.0")
          rescue StandardError
            nil
          end

          def request_cache
            Thread.current[:_loops_loop_loader_cache] ||= {}
          end
        end
      end
    end
  end
end
