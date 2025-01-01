# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Public: Find which branches contain a given commit
    #
    # oid - a String commit oid
    #
    # Returns Array of String branch names (empty if no branches contain the commit)
    def branch_contains(oid)
      ensure_valid_full_oid(oid)

      cache_fetch(repository_reference_cache_key("branch_contains", "v1", oid), backend_method: :branch_contains) do
        send_message(:branch_contains, oid)
      end
    end

    # Public: Find which tags contain a given commit
    #
    # oid - a String commit oid
    #
    # Returns Array of String tag names (empty if no tags contain the commit)
    def tag_contains(oid)
      ensure_valid_full_oid(oid)

      cache_fetch(repository_reference_cache_key("tag_contains", "v1", oid), backend_method: :tag_contains) do
        send_message(:tag_contains, oid)
      end
    end

    # Public: Find whether a commit is "visible" (reachable from branches or tags)
    #
    # oid - a String commit oid
    #
    # Returns Boolean
    def commit_visible?(oid)
      commits_visible([oid])[oid]
    end

    # Public: Find whether commits are "visible" (reachable from branches or tags)
    #
    # oids - an Array of String commit oids
    #
    # Returns Hash with String keys and Boolean values,
    #   where the keys are commit oids,
    #   and the values indicate whether the commit is visible
    def commits_visible(oids)
      oids.each do |oid|
        ensure_valid_full_oid(oid)
      end

      cache_keys_to_oids = {}
      needs_computing = {}
      result = {}

      oids.each do |oid|
        key = repository_reference_cache_key("commit_visible", "v1", oid)
        cache_keys_to_oids[key] = oid
      end

      cached = cache_get_multi(cache_keys_to_oids.keys, backend_method: :commits_visible)

      cache_keys_to_oids.each do |cache_key, oid|
        if cached.key?(cache_key)
          result[oid] = cached[cache_key]
        else
          needs_computing[cache_key] = oid
        end
      end

      return result if needs_computing.empty?

      remaining = send_message(:commits_visible, needs_computing.values)

      needs_computing.each do |cache_key, oid|
        value = remaining[oid]
        @cache.set(cache_key, value)
        result[oid] = value
      end

      result
    end
  end
end
