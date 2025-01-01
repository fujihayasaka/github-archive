# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

require "gitrpc/client/read_text_blob_oid"
require "gitrpc/client/disk"

module GitRPC
  class Client
    # Legacy gist namespaced calls aliased for compatibility.
    alias gist_text_blob_oid read_text_blob_oid

    def gist_blob_by_path(path, commit_oid)
      read_tree_entry(commit_oid, path)
    end

    def gist_blob_oid_by_path(path, commit_oid)
      read_tree_entry_oid(commit_oid, path, "type" => "blob")
    end

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
