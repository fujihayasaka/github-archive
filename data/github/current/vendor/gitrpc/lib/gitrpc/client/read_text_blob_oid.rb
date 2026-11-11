# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    def read_text_blob_oid(commit_oid)
      cache_key = repository_cache_key("read_text_blob_oid", "v2", commit_oid, true)

      cache_fetch(cache_key, backend_method: :read_text_blob_oid) do
        send_message(:read_text_blob_oid, commit_oid)
      end
    end
  end
end
