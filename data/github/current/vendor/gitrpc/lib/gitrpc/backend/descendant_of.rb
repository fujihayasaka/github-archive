# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    # Public: Determine whether one revision is a descendant of another,
    # for several revision pairs.
    #
    # The input is an Array of two-element arrays, [commit, ancestor]
    #   commit   - a String commitish - the "newer" commit
    #   ancestor - a String commitish - the "older" commit
    #
    # Returns a Hash with Array keys and Boolean values,
    #   where the keys are the two-element input arrays,
    #   and the values indicate whether commit is a descendant of ancestor
    rpc_reader :descendant_of
    def descendant_of(commits_and_ancestors)
      result = {}

      commits_and_ancestors.each do |commit, ancestor|
        ensure_valid_commitish(commit)
        ensure_valid_commitish(ancestor)

        res = spawn_git("merge-base", ["--is-ancestor", ancestor, commit])
        is_ancestor = case res["status"]
        when 0; true
        when 1; false
        else
          handle_missing_or_wrong_object_type(res)
        end

        result[[commit, ancestor]] = is_ancestor
      end

      result
    end
  end
end
