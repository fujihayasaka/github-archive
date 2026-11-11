# typed: true
# frozen_string_literal: true

module GitRPC
  class Client
    # Private: Run and instrument @cache.fetch.
    def cache_fetch(key, *args, backend_method:)
      GitRPC.instrument(:cache_get, backend_method: backend_method) do |instrument_payload|
        instrument_payload[:cache_result] = "hit"
        @cache.fetch(key, *args) do
          instrument_payload[:cache_result] = "miss"
          yield
        end
      end
    end

    # Private: Run and instrument @cache.get.
    def cache_get(key, backend_method:)
      GitRPC.instrument(:cache_get, backend_method: backend_method) do |instrument_payload|
        result = @cache.get(key)
        instrument_payload[:cache_result] = result.nil? ? "miss" : "hit"
        result
      end
    end

    # Private: Run and instrument @cache.get_multi.
    def cache_get_multi(keys, backend_method:)
      GitRPC.instrument(:cache_get_multi, backend_method: backend_method, keys: keys) do |instrument_payload|
        results = @cache.get_multi(keys)
        instrument_payload[:results] = results
        results
      end
    end
  end
end
