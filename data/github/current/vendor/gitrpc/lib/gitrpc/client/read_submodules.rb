# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    def read_submodules(oid)
      ensure_valid_full_oid(oid)

      cache_key = content_cache_key("read_submodules", "v1", oid)
      cache_fetch(cache_key, backend_method: :read_submodules) do
        send_message(:read_submodules, oid)
      end
    end
  end
end
