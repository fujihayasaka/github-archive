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
    def call(path)
      raise InvalidPath if path.match(%r{\x00})
      first_chunk = path.split("/").first

      # If this seems like an oid, try that code path first
      # to avoid looking for a ref with this name.
      qualified_ref_name = find_ref_or_sha(first_chunk, path)

      ref_or_sha = strip_qualified_ref_if_not_fully_qualified_path(qualified_ref_name, path)

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

    def find_ref_or_sha(maybe_sha, path)
      if symref?(maybe_sha)
        # If it's "HEAD" or "HEAD@{5}", we resolve it first (via rev_parse)
        # to avoid returning a would-be `refs/heads/HEAD` that might be used to cheat the user.
        symref_sha = @repository.rpc.rev_parse(maybe_sha)
        return symref_sha if symref_sha
      end

      if looks_like_an_oid?(maybe_sha)
        sha = find_commit_sha(maybe_sha)
        # We can shortcut only if it was a short SHA matching the found full SHA.
        # Otherwise, it's likely it wasn't a short SHA at all, so we have to find as ref first.
        return sha if sha && sha.start_with?(maybe_sha.downcase)

        find_ref(path) || sha
      else
        find_ref(path) || find_commit_sha(maybe_sha)
      end
    end

    def find_ref(path)
      qualified_ref_name, _ = @repository.rpc.read_ref_from_path(path.b, limit: GitHub.maximum_ref_length)
      qualified_ref_name
    end

    # Resolves short SHA to full SHA, and also symrefs like "HEAD" or
    # relative refs like "HEAD@{5}" or "master@{2021-7-1}" to their full SHA.
    def find_commit_sha(maybe_sha)
      sha = @repository.ref_to_sha(maybe_sha)
      return nil unless sha
      header = @repository.rpc.read_object_headers([sha])&.first
      return nil unless header
      return nil unless header["type"] == "commit"
      sha.downcase
    rescue ::GitRPC::InvalidObject,     # object found but not a commit
           ::GitRPC::InvalidRepository, # repository isn't routed, doesn't exist
           ::GitRPC::ObjectMissing      # bogus commit SHA
    end

    def strip_qualified_ref_if_not_fully_qualified_path(fully_qualified_ref_or_sha, path)
      return nil unless fully_qualified_ref_or_sha
      return fully_qualified_ref_or_sha if path.b.starts_with?(fully_qualified_ref_or_sha)
      fully_qualified_ref_or_sha.sub(%r{\Arefs/heads/|refs/tags/}, "")
    end
  end
end
