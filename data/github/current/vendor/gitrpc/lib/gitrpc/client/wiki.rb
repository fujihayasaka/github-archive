# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    def read_wiki_pages(oid, directory_prefix)
      if !valid_full_oid?(oid)
        raise ::GitRPC::InvalidFullOid, "wrong argument type #{oid.inspect} (expected 40c String OID)"
      end

      hashed_prefix = ::Digest::SHA256.hexdigest(directory_prefix)
      wiki_key = content_cache_key("wiki-pages", oid, hashed_prefix, "v3")
      cache_fetch(wiki_key, backend_method: :read_wiki_pages) do
        send_message(:read_wiki_pages, oid, directory_prefix.b)
      end
    end
  end
end
