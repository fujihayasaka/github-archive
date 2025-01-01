# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Read the signatures and signing payloads from commit headers.
    #
    # oids - An Array of String OIDs. Must be 40 char sha1s.
    #
    # Returns an Array of results. For each result, the first element is the
    # signature header String, if present, or nil otherwise. The second element
    # is the signing payload String.
    #
    # Raises GitRPC::InvalidObject if object isn't a commit.
    # Raises GitRPC::ObjectMissing if an object is missing.
    # Raises GitRPC::InvalidFullOid if an OID is invalid.
    def parse_commit_signatures(oids)
      parse_signatures(oids, :commit)
    end

    # Read the signatures and signing payloads from tags.
    #
    # oids - An Array of String OIDs. Must be 40 char sha1s.
    #
    # Returns an Array of results. For each result, the first element is the
    # signature String, if present, or nil otherwise. The second element is the
    # signing payload String.
    #
    # Raises GitRPC::InvalidObject if object isn't a tag.
    # Raises GitRPC::ObjectMissing if an object is missing.
    # Raises GitRPC::InvalidFullOid if an OID is invalid.
    def parse_tag_signatures(oids)
      parse_signatures(oids, :tag)
    end

    # Read the signatures and signing payloads from tags or commits.
    #
    # oids - An Array of String OIDs. Must be 40 char sha1s.
    # type - The Symbol type of object we're reading.
    #
    # Returns an Array of results. For each result, the first element is the
    # signature String, if present, or nil otherwise. The second element is the
    # signing payload String.
    #
    # Raises GitRPC::InvalidObject if object isn't the correct type.
    # Raises GitRPC::ObjectMissing if an object is missing.
    # Raises GitRPC::InvalidFullOid if an OID is invalid.
    def parse_signatures(oids, type)
      raise ArgumentError unless [:commit, :tag].include?(type)
      return [] if oids.empty?

      keys = oids.map do |oid|
        ensure_valid_full_oid(oid)
        signature_key(oid, type)
      end

      # Load cached results.
      results = cache_get_multi(keys, backend_method: :parse_x_signatures) || {}

      # Find cache misses.
      missing_oids = keys.zip(oids).select do |key, _oid|
        # Checking for nil? instead of results.key? because cache returns hash
        # with nil values when memcache is offline.
        results[key].nil?
      end.map(&:last)

      # Load cache misses.
      if missing_oids.any?
        new_results = case type
        when :commit
          send_message(:parse_commit_signatures, missing_oids)
        when :tag
          send_message(:parse_tag_signatures, missing_oids)
        end

        missing_oids.zip(new_results).each do |oid, res|
          key = signature_key(oid, type)
          results[key] = res
          @cache.set(key, res)
        end
      end

      # Maintain original ordering
      keys.map { |key| results[key] }
    end

    def signature_key(oid, type)
      content_cache_key("parse_signature", oid, type, "v2")
    end
  end
end
