# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Private: read a single tree entry given a path and a sha.
    #
    # oid - the oid of the commit or tree to find the entry in.
    # path - The path of the blob or tree to look for.
    private def read_tree_entry(oid, path = nil, options = {})
      ensure_valid_full_oid(oid)

      defaults = {
        "truncate" => GitRPC::Backend::TREE_ENTRY_TRUNCATE_LIMIT,
        "limit" => GitRPC::Backend::TREE_ENTRY_SIZE_LIMIT,
        "type" => nil
      }
      opts = defaults.merge(stringify_keys(options))

      path = normalize_path(path)
      key = "#{path}:#{opts["truncate"]}:#{opts["limit"]}:#{opts["type"]}"

      cache_key = content_cache_key("read_tree_entry:v5", oid, sha256(key))
      cache_fetch(cache_key, backend_method: :read_tree_entry) do
        send_message(:read_tree_entry, oid, path, opts).tap do |response|
          response["content"] = response["data"] # For legacy gist usage
          GitRPC::Encoding.tag_compatible(response["data"], response["encoding"])
        end
      end
    end
  end
end
