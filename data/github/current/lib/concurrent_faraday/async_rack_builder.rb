# typed: true
# frozen_string_literal: true
module ConcurrentFaraday
  class AsyncConnectionRackBuilder < ::Faraday::RackBuilder

    def build_response(connection, request)
      warn "WARNING: No adapter was configured for this request" unless adapter_set?

      parallel_manager = connection.parallel_manager || connection.default_parallel_manager
      in_parallel = false

      begin
        env = build_env(connection, request)
        in_parallel = env[:parallel_manager].present?
        env[:parallel_manager] ||= parallel_manager
        resp = app.call(env)
        resp = FutureResponse.new.fulfill(resp) unless resp.is_a?(FutureResponse)
        resp.ready!
      ensure
        if parallel_manager.respond_to?(:clear!) && !in_parallel
          parallel_manager.clear!
        end
      end
    end
  end
end
