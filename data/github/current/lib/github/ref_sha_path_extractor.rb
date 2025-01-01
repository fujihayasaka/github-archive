# typed: true
# frozen_string_literal: true

module GitHub
  class RefShaPathExtractor
    include Scientist

    class InvalidPath < StandardError; end

    def initialize(repository)
      @repository = repository
    end

    # Public: Extract a branch/ref name or a commit SHA and a tree/blob
    # path from a path that we get from the params of a Rails request for a
    # blob or tree. This method verifies the presence of the branch/ref/commit,
    # but not the path. The whole reason this exists is simply to be able to
    # differentiate the two, so verifying the presence of the base is just a
    # necessary step.
    #
    # path - The String to extract from
    #
    # Examples
    #
    #   # where somebranch exists
    #   call("somebranch/lib/foo/bar.rb")
    #   # => ["somebranch", "lib/foo/bar.rb"]
    #
    #   # where master exists
    #   call("master")
    #   # => ["master", nil]
    #
    #   # where blahblah does not exist
    #   call("blahblah")
    #   # => [nil, "blahblah"]
    #
    #   # where 951eb57e171dd651192468aeac6465d3f3fef062 exists
    #   call("951eb57e171dd651192468aeac6465d3f3fef062/lib/foo/bar.rb")
    #   # => ["951eb57e171dd651192468aeac6465d3f3fef062", "lib/foo/bar.rb"]
    #
    # Returns an Array of the ref/SHA and the path.
    #   If no ref/SHA is found, the first array entry will be nil
    #   and the second entry will be the entire string that was provided.
    #   If the ref/SHA is found but no path follows, the second entry
    #   will be nil.
    def call(path, include_custom_refs: false)
      raise InvalidPath if path.match(%r{\x00})
      first_chunk = path.split("/").first

      # If this seems like an oid, try that code path first
      # to avoid looking for a ref with this name.
      qualified_ref_name = find_ref_or_sha(first_chunk, path, include_custom_refs:)

      ref_or_sha = strip_qualified_ref_if_not_fully_qualified_path(qualified_ref_name, path, include_custom_refs:)

      result_path =
        if ref_or_sha.nil?
          path
        elsif ref_or_sha == path
          nil
        else
          # we want to get the path without the ref or sha that it started with.
          # this is a little tricky if it was a short SHA that got expanded.
          to_remove =
            if path.b.starts_with?(ref_or_sha.b)
              ref_or_sha
            else
              first_chunk
            end
          path_param = path.b.sub(%r{#{Regexp.escape(to_remove.b)}(/|$)+}, "")
          File.expand_path("/#{path_param}")[1..-1]
        end

      [ref_or_sha, result_path, qualified_ref_name]
    end

    def looks_like_an_oid?(str)
      str&.match?(/\A[0-9a-f]{40}\z/)
    end

    def symref?(str)
      str == "HEAD" || str&.start_with?("HEAD@{")
    end

    def find_ref_or_sha(maybe_sha, path, include_custom_refs: false)
      if symref?(maybe_sha)
        # If it's "HEAD" or "HEAD@{5}", we resolve it first (via rev_parse)
        # to avoid returning a would-be `refs/heads/HEAD` that might be used to cheat the user.
        symref_sha = @repository.spokes_api.resolve_object(object_name: maybe_sha)
        return symref_sha if symref_sha
      end

      if looks_like_an_oid?(maybe_sha)
        sha = find_commit_sha(maybe_sha)
        # We can shortcut only if it was a short SHA matching the found full SHA.
        # Otherwise, it's likely it wasn't a short SHA at all, so we have to find as ref first.
        return sha if sha && sha.start_with?(maybe_sha.downcase)

        find_ref(path, include_custom_refs:) || sha
      else
        find_ref(path, include_custom_refs:) || find_commit_sha(maybe_sha)
      end
    end

    def find_ref(path, include_custom_refs: false)
      qualified_ref_name, _ = read_ref_from_path(path.b, limit: GitHub.maximum_ref_length, include_custom_refs:)
      qualified_ref_name
    end

    # Resolves short SHA to full SHA, and also symrefs like "HEAD" or
    # relative refs like "HEAD@{5}" or "master@{2021-7-1}" to their full SHA.
    def find_commit_sha(maybe_sha)
      sha = @repository.ref_to_sha(maybe_sha)
      return nil unless sha
      header = @repository.read_object_headers([sha])&.first
      return nil unless header
      return nil unless header["type"] == "commit"
      sha.downcase
    rescue ::GitRPC::InvalidObject,     # object found but not a commit
           ::GitRPC::InvalidRepository, # repository isn't routed, doesn't exist
           ::GitRPC::ObjectMissing      # bogus commit SHA
    end

    def strip_qualified_ref_if_not_fully_qualified_path(fully_qualified_ref_or_sha, path, include_custom_refs: false)
      return nil unless fully_qualified_ref_or_sha
      return fully_qualified_ref_or_sha if path.b.starts_with?(fully_qualified_ref_or_sha)
      return fully_qualified_ref_or_sha.sub(%r{\Arefs/heads/|refs/tags/}, "") unless include_custom_refs

      qualified_ref_parts = fully_qualified_ref_or_sha.split("/")
      while qualified_ref_parts.length > 0
        return qualified_ref_parts.join("/") if path.b.starts_with?(qualified_ref_parts.join("/"))
        qualified_ref_parts.shift
      end

      fully_qualified_ref_or_sha
    end

    private

    # Internal: Return the ref name that most closely matches the path
    #
    # path - the path, typically of the form ref_name/path_string
    # limit - Integer indicating the maximum length of ref names
    # include_custom_refs - Boolean indicating whether to include custom refs
    #
    # Returns a two-element Array consisting of fully qualified refname and
    # target commit OID, or nil if no ref name was found.
    def read_ref_from_path(path, limit: nil, include_custom_refs: false)
      path = limit_path(path.b, limit) if limit
      ref_names = candidate_ref_names_from_path(path.b, include_custom_refs:)
      target_oids = @repository.resolve_references(ref_names).to_h

      ref_names.each do |ref_name|
        target_oid = target_oids[ref_name]
        return [ref_name, target_oid] if target_oid
      end

      nil
    end

    # Internal: Limit path by given limit
    #
    # Returns String
    def limit_path(path, limit)
      return path if path.bytesize <= limit

      sliced_path = path.byteslice(0, limit)
      return sliced_path if path[limit] == "/"

      sliced_path.gsub(%r{\/[^\/]*\z}, "")
    end

    # Internal: Splits up path into potential fully qualified ref names
    #
    # Returns Array<String>
    def candidate_ref_names_from_path(path, include_custom_refs: false)
      default_prefixes = ["refs/heads/", "refs/tags/"]
      # Initialize as an empty array of strings for sorbet type checking
      fully_qualified_prefixes = T.let([], T::Array[String])
      fully_qualified_prefixes = default_prefixes

      # If the prefix matches, we update the fully_qualified_prefixes
      # and ref_paths to be the split path.
      # For example, a path of refs/heads/foo/v1 would be split into
      # fully_qualified_prefixes = ["refs/heads/"]
      # ref_paths = ["foo/v1"]
      #
      # For example, a path of v1/foo/bar
      # If no prefix matches, we default to the default prefixes.
      # fully_qualified_prefixes = ["refs/heads/", "refs/tags/"]
      # ref_paths would be ["v1/foo/bar"]
      ref_paths = [path]
      default_prefixes.each do |prefix|
        match_before, qualifier_prefix, unqualified_path = path.partition(prefix)
        if match_before.empty? && !qualifier_prefix.empty? && !unqualified_path.empty?
          fully_qualified_prefixes = [qualifier_prefix]
          ref_paths = [unqualified_path]
          break
        end
      end

      # For each ref path, we get the candidate ref name combinations
      # e.g. for "v1/foo/bar" this will return ["v1","v1/foo","v1/foo/bar"]
      candidate_ref_names = ref_paths.flat_map { |ref_path| get_candidate_ref_name_combinations(ref_path) }

      # construct the potential ref names by combining the prefixes with the candidate ref names
      candidate_ref_names = candidate_ref_names.reverse.flat_map do |candidate_ref_name|
        fully_qualified_prefixes.map do |fully_qualified_prefix|
          "#{fully_qualified_prefix}#{candidate_ref_name}"
        end
      end

      if include_custom_refs
        # For paths with custom refs like "refs/pull/1234/merge/file.txt"
        # we need to add the custom ref names to the candidate ref names.
        path_parts = path.split("/")
        if path.start_with?("refs/")
          while path_parts.length > 2
            candidate_ref_names << path_parts.join("/")
            path_parts.pop
          end
        else
          while !path_parts.length.zero?
            candidate_ref_names << "refs/#{path_parts.join("/")}"
            path_parts.pop
          end
        end
      end

      candidate_ref_names.uniq
    end

    # Internal: Finds the potential ref name combinations in a path to send to git
    # so we can try and find which one is a valid ref.
    # e.g. for "v1/foo/bar" this will return ["v1","v1/foo","v1/foo/bar"]
    #
    # Returns Array<String>
    def get_candidate_ref_name_combinations(path)
      candidate_ref_names = []

      path.each_char.with_index do |char, index|
        next if char != "/"
        candidate_ref_names << path[0...index]
      end
      candidate_ref_names << path
    end
  end
end
