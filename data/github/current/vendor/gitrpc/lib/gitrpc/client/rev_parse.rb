# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Public: Resolve an object name to a 40 char sha1 oid string.
    #
    # The implementation tries hard to avoid hitting the backend by first
    # checking for some obviously malformed object names and also consults
    # the cached refs hash.
    #
    # object_name - String revision specifier as described in gitrevisions(7).
    #               Simple branch and tag names are fast-pathed at the cache
    #               layer by interogating the list of cached refs. More complex
    #               revision specifiers like `"master@{1.day.ago}"` always
    #               generate an RPC call.
    # use_cache - If false, read_qualified_refs and the refs_cache are bypassed
    #             in favor of a backend call to rev_parse.
    #
    # Returns the string oid of the object pointed to by object_name or nil when
    # the name can not be resolved.
    def rev_parse(object_name, use_cache: true)
      if object_name.nil?
        raise TypeError, "object_name must be specified"
      elsif !sanitary_revspec?(object_name)
        return
      elsif valid_full_oid?(object_name)
        return object_name
      end

      if use_cache
        oid = read_qualified_refs([
          object_name,
          "refs/heads/#{object_name}",
          "refs/tags/#{object_name}"
        ]).map(&:last).find { |target_oid| !target_oid.nil? }
        return oid if oid
      end

      # fall back to making the call on the backend for special revision
      # syntaxes and other stuff
      send_message(:rev_parse, object_name)
    end
  end
end
