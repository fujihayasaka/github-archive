# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    def interesting_branches(default_branch = "master", limit = 50)
      cache_key = repository_cache_key(
        "interesting_branches", default_branch, limit.to_s)
      timeout = 3600  # 1 hour in seconds
      cache_fetch(cache_key, timeout, backend_method: :interesting_branches) do
        send_message(:interesting_branches, default_branch, limit)
      end
    end
  end
end
