# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    def ahead_behind(base, other, timeout: nil)
      other = Array(other)

      result = {}
      cache_keys = ahead_behind_keys(base, other)
      cached = cache_get_multi(cache_keys.values, backend_method: :ahead_behind)
      need_query = []

      cache_keys.each do |o, key|
        if ab = cached[key]
          result[o] = ab
        else
          need_query << o
        end
      end

      if !need_query.empty?
        raise GitRPC::Timeout if timeout && timeout <= 0
        query = send_message(:ahead_behind, base, need_query, timeout)
        query.each do |o, ab|
          @cache.set(cache_keys[o], ab)
          result[o] = ab
        end
      end

      result
    end

    def ahead_behind_keys(base, others)
      cache_keys = {}
      others.each do |o|
        cache_keys[o] = ahead_behind_key(base, o)
      end

      cache_keys
    end

    def ahead_behind_key(base, other)
      ["ahead-behind", "v1", sha256(base), sha256(other)].join(":")
    end
  end
end
