# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Public: Determine whether one revision is a descendant of another.
    #
    # commit   - a String commit oid - the "newer" commit
    # ancestor - a String commit oid - the "older" commit
    #
    # Returns Boolean
    def descendant_of?(commit, ancestor)
      key = [commit, ancestor]
      descendant_of([key])[key]
    end

    # Public: Determine whether one revision is a descendant of another,
    # for several revision pairs.
    #
    # The input is an Array of two-element arrays, [commit, ancestor]
    #   commit   - a String commit oid - the "newer" commit
    #   ancestor - a String commit oid - the "older" commit
    #
    # Returns a Hash with Array keys and Boolean values,
    #   where the keys are the two-element input arrays,
    #   and the values indicate whether commit is a descendant of ancestor
    def descendant_of(commits_and_ancestors)
      commits_and_ancestors.flatten.each do |oid|
        ensure_valid_full_oid(oid)
      end

      cache_keys_to_pairs = {}
      needs_computing = {}
      result = {}

      commits_and_ancestors.each do |commit, ancestor|
        cache_keys_to_pairs[descendant_of_key(commit, ancestor)] = [commit, ancestor]
      end

      cached = cache_get_multi(cache_keys_to_pairs.keys, backend_method: :descendant_of)

      cache_keys_to_pairs.each do |cache_key, (commit, ancestor)|
        if !cached[cache_key].nil?
          result[[commit, ancestor]] = cached[cache_key]
        else
          needs_computing[cache_key] = [commit, ancestor]
        end
      end

      return result if needs_computing.empty?

      remaining = send_message(:descendant_of, needs_computing.values)

      needs_computing.each do |cache_key, (commit, ancestor)|
        value = remaining[[commit, ancestor]]
        @cache.set(cache_key, value)
        result[[commit, ancestor]] = value
      end

      result
    end

    def descendant_of_key(commit, ancestor)
      ["descendant_of", commit, ancestor].join(":")
    end
  end
end
