# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Public: Lists commit objects in reverse chronological order
    #
    # include_oids - Array of String OIDs to start walking from.
    # exclude_oids - Optional Array of String OIDs to exclude from set.
    # reverse - Output the commits in reverse order (default: false)
    # limit - Limit the number of commits returned (default: 10k)
    # merges - Only look for merge commits.
    # symmetric - Return the symmetric difference. Like `git rev-list <commit1>...<commit2>`
    #             Needs a list of exactly 2 commits to be passed as `include_oids`.
    #
    # Returns an Array of String OIDs. Will raise an error if any of the OIDs
    # are missing or non-commits.
    def rev_list(include_oids, exclude_oids: [], paths: [], skip: nil, reverse: false, merges: false, symmetric: false, limit: 10_000)
      sender = ->(cache_key, include_oids, exclude_oids, options) do
        cache_fetch(content_cache_key(cache_key), backend_method: :rev_list) do
          send_message(:rev_list, include_oids, exclude_oids, options)
        end
      end
      rev_list_internal(include_oids, sender, exclude_oids: exclude_oids, paths: paths, skip: skip, reverse: reverse, merges: merges, symmetric: symmetric, limit: limit)
    end

    def async_rev_list(include_oids, exclude_oids: [], paths: [], skip: nil, reverse: false, merges: false, symmetric: false, limit: 10_000)
      sender = ->(cache_key, include_oids, exclude_oids, options) do
        GitHub.cache.async_get_or_cache(content_cache_key(cache_key)) do
          async_send_message(:rev_list, include_oids, exclude_oids, options)
        end
      end
      rev_list_internal(include_oids, sender, exclude_oids: exclude_oids, paths: paths, skip: skip, reverse: reverse, merges: merges, symmetric: symmetric, limit: limit)
    end

    def rev_list_internal(include_oids, sender, exclude_oids: [], paths: [], skip: nil, reverse: false, merges: false, symmetric: false, limit: 10_000)
      include_oids, exclude_oids, paths = Array(include_oids), Array(exclude_oids), Array(paths)

      if include_oids.size < 1
        raise ArgumentError, "wrong number of arguments"
      elsif symmetric && include_oids.size != 2
        raise ArgumentError, "need exactly 2 commits to create a symmetric difference"
      end

      include_oids.each { |oid| ensure_valid_full_oid(oid) }
      exclude_oids.each { |oid| ensure_valid_full_oid(oid) }

      paths.each do |path|
        unless path.kind_of? String
          raise ArgumentError, "all given paths must be String instances"
        end
      end

      options = {
        "limit" => limit,
        "reverse" => reverse,
        "merges" => merges,
        "paths" => paths,
        "skip" => skip,
        "symmetric" => symmetric,
      }

      cache_key = ["rev_list", "v2"]
      cache_key.concat(include_oids)

      if exclude_oids.any?
        cache_key << "^"
        cache_key.concat(exclude_oids)
      end

      cache_key << "n#{options["limit"]}"
      cache_key << "s#{options["skip"]}" if options["skip"]
      cache_key << "reverse" if options["reverse"]
      cache_key << "merges" if options["merges"]
      cache_key << "symmetric" if options["symmetric"]
      cache_key << "use_git=true"

      unless paths.empty?
        cache_key << ::Digest::SHA256.hexdigest(paths.sort.uniq.join(":"))
      end

      sender.call(cache_key, include_oids, exclude_oids, options)
    end
  end
end
