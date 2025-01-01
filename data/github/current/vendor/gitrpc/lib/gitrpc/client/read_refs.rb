# frozen_string_literal: true
module GitRPC
  class Client
    include GitRPC::Util

    # Public: Retrieve ref name to oid mapping from the repository. This
    # includes branches, tags, and any other special refs (when not filtered).
    # Signed tags are dereferenced so that the resulting value is the oid of the
    # commit, not the oid of the tag object.
    #
    # filter - String specifying which set of refs should be returned. "default"
    #          means that only heads and tags will be returned. "extended"
    #          returns refs that would show up in `git ls-remote`. "all" returns
    #          all of the refs on the fileserver, including some that are only
    #          intended to be used inside of this app.
    #
    # Returns a hash of fully qualified ref name strings to commit oid mappings.
    def read_refs(filter = "default")
      ensure_valid_read_refs_filter(filter)
      cache_key = refs_key(filter)
      cache_fetch(cache_key, backend_method: :read_refs) do
        send_message(:read_refs, filter)
      end
    end

    # Internal: Cache key used to store the main refs hash.
    def refs_key(filter = "default")
      repository_reference_cache_key("refs", "v4", filter.to_s)
    end

    # Internal: All of the possible refs_keys
    def refs_keys
      READ_REFS_FILTERS.map { |filter| refs_key(filter) }
    end

    # Public: Read a list of fully qualified refs
    #
    # names    - Array of fully qualified ref names
    # do_cache - Boolean indicating whether we should fetch and store references
    #            from the cache to reduce the size of, or eliminate, the remote
    #            request.
    #
    # Returns an Array with pairs of fully qualified refnames and target commit OID
    def read_qualified_refs(ref_names, do_cache: true)
      ref_name_to_cache_key = ref_names.map { |ref_name|
        [ref_name, qualified_ref_cache_key(ref_name)]
      }.to_h

      cached_refs = {}
      missing_ref_names = []

      target_oids_from_cache = if do_cache
        cache_get_multi(ref_name_to_cache_key.values, backend_method: :read_qualified_refs)
      else
        {}
      end
      ref_names.each do |ref_name|
        cache_key = ref_name_to_cache_key[ref_name]
        if target_oids_from_cache.has_key?(cache_key)
          cached_refs[ref_name] = target_oids_from_cache[cache_key]
        else
          missing_ref_names << ref_name
        end
      end

      if missing_ref_names.any?
        target_oids = send_message(:read_qualified_refs, missing_ref_names)
        missing_ref_names.zip(target_oids) do |ref_name, target_oid|
          cached_refs[ref_name] = target_oid
          @cache.set(ref_name_to_cache_key[ref_name], target_oid) if do_cache
        end
      end

      ref_names.zip(cached_refs.values_at(*ref_names))
    end

    private def qualified_ref_cache_key(name)
      repository_reference_cache_key("read_qualified_ref", "v2", Digest::SHA256.hexdigest(name))
    end

    # Public: Number of refs, branches and tags
    #
    # Returns Hash
    def ref_counts
      cache_key = repository_reference_cache_key("ref_counts", "v1")
      cache_fetch(cache_key, backend_method: :ref_counts) do
        send_message(:ref_counts)
      end
    end

    # Public: Read the oid of the HEAD ref
    #
    # Returns a sha1
    def read_head_oid
      cache_key = repository_reference_cache_key("read_head_oid", "v2")
      cache_fetch(cache_key, backend_method: :read_head_oid) do
        send_message(:read_head_oid)
      end
    end

    # Public: list branch names and dates the way BranchFinder likes them
    #
    # Returns an array of [date, refname] arrays.
    def raw_branch_names_and_dates
      cache_key = repository_reference_cache_key("raw_branch_names_and_dates", "v1")
      cache_fetch(cache_key, backend_method: :raw_branch_names_and_dates) do
        send_message(:raw_branch_names_and_dates)
      end
    end

    # Public: Determines if the repository contains at least one branch, at least one tag, or is entirely empty
    #
    # Returns Hash[:empty -> Boolean, :branches -> Boolean, :tags -> Boolean]
    def any_refs(want_tags: false, want_branches: false)
      cache_key = repository_reference_cache_key("any_refs", "v1", want_tags, want_branches)
      cache_fetch(cache_key, backend_method: :any_refs) do
        send_message(:any_refs, want_tags:, want_branches:)
      end
    end

    # Public: Returns the number of branches and/or tags in the repository. Faster than ref_counts since we don't
    # have to enumerate all refs.
    #
    # Returns Hash[:tags -> Integer, :branches -> Integer]
    def branches_and_tags_counts(want_tags: true, want_branches: true)
      cache_key = repository_reference_cache_key("branches_and_tags_counts", "v1", want_tags, want_branches)
      cache_fetch(cache_key, backend_method: :branches_and_tags_counts) do
        send_message(:branches_and_tags_counts, want_tags:, want_branches:)
      end
    end
  end
end
