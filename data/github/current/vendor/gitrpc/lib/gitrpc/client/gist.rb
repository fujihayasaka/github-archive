# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

require "gitrpc/client/read_text_blob_oid"
require "gitrpc/client/disk"

module GitRPC
  class Client
    # Legacy gist namespaced calls aliased for compatibility.
    alias gist_text_blob_oid read_text_blob_oid

    def gist_title(oid)
      cache_key = repository_cache_key("gist_title", "v1", oid)
      title = cache_fetch(cache_key, backend_method: :gist_title) do
        send_message(:gist_title, oid)
      end

      if title
        title.force_encoding("UTF-8")
      end
    end
  end
end
