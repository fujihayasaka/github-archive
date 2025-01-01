# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    # Public: resolves the ideal base commit for the given repository and commit "triplet".
    class BaseOidResolver
      def initialize(backend, rugged)
        @results = {}
        @backend = backend
      end

      # Public: Resolves the ideal base object for the given commits and caches the result.
      #   Note: This method writes to the git repository and therefore the result cannot be
      #         guaranteed to remain consistent across file servers.
      #
      # commit1_oid     - String oid of the start of the range.
      # commit2_oid     - String oid of the end of the range.
      # base_commit_oid - String oid of the base commit from the base branch.
      #
      # Returns a string oid of the best commit or proxy tree
      def resolve(commit1_oid, commit2_oid, base_commit_oid)
        args = [commit1_oid, commit2_oid, base_commit_oid]
        return results[args] if results.key?([args])

        results[args] = resolve!(commit1_oid, commit2_oid, base_commit_oid)
      end

      private

      attr_reader :backend, :results

      def resolve!(commit1_oid, commit2_oid, base_commit_oid)
        tmpdir = nil

        # Resolve commit OIDs
        oids = Hash.new
        input = [commit1_oid, commit2_oid, base_commit_oid].compact

        # Check explicitly for NULL_OID and raise GitRPC::Failure (instead of
        # ObjectMissing, which would have happened otherwise). This avoids
        # downstream behavior changes for callers that expect ObjectMissing to
        # specifically represent valid OIDs that may only temporarily be
        # missing.
        raise GitRPC::Failure, "null OID cannot exist" if input.any? { |oid| oid == NULL_OID }

        unless input.empty?
          res = backend.checked_spawn_git!("cat-file", ["--batch-check=%(objectname) %(objecttype)", "-Z"], input.join("\0"))
          oid_list = res["out"].chomp.split("\0")
          raise GitRPC::Failure, "invalid OID result set: expected #{input.length}, got #{oid_list.length}" if input.length != oid_list.length

          input.zip(oid_list).each do |commit, line|
            raise ObjectMissing.new("object not found - no match for id (#{commit})", commit) if line =~ /\A.* (missing|ambiguous)\z/

            oid, type = line.split(" ", 2)
            raise GitRPC::InvalidObject, "Invalid object type, expected commit but was #{type}" unless type == "commit"

            oids[commit] = oid
          end
        end

        commit1     = oids[commit1_oid]
        commit2     = oids[commit2_oid]
        base_commit = oids[base_commit_oid]

        if base_commit.nil? || commit1 == base_commit
          return commit1
        end

        # Get merge bases
        commit1_base = base_commit.nil? || commit1.nil? ? nil : backend.best_merge_base(base_commit, commit1)
        commit2_base = base_commit.nil? || commit2.nil? ? nil : backend.best_merge_base(base_commit, commit2)

        # If head commits originate from the same merge base, just do a simple
        # diff. No hunks to filter out.
        return commit1 if commit1_base && (commit1_base == commit2_base)

        # Compare latest against new merge base if range starts at original merge base.
        # Nothing to filter.
        return commit2_base if commit1_base && (commit1_base == commit1)

        return commit2_base if commit1_base.nil? && commit1.nil?

        tmpdir = @backend.create_custom_tmpdir(@backend.path, "objects/tmp_objdir-resolve-")

        # Create a proxy tree
        res = backend.spawn_git(
          "merge-tree", [
            "--write-tree",
            "--merge-base=#{commit1_base.nil? ? EMPTY_TREE_OID : commit1_base}",
            "--name-only",
            "--no-messages",
            "-Xours",
            "-Xfind-renames=50",
            "-z",
            "--use-tmp-objdir=migrate-on-success",
            "--tmp-objdir-location=#{tmpdir}",
            commit1,
            commit2_base
          ],
          nil,
          {},
          nil,
          nil,
          [
            "-c", "rerere.enabled=false",
          ]
        )

        # If there was a merge conflict, fallback to a regular diff and flag it
        # as degraded.
        return commit1 if !res["ok"]

        res["out"].chomp.sub(/\0+$/, "")
      ensure
        FileUtils.rm_rf(tmpdir) if tmpdir && File.exist?(tmpdir)
      end
    end

    def resolve_base_oid(commit1_oid, commit2_oid, base_commit_oid)
      # cache the resolver for the lifetime of this Backend instance. This allows us to cache
      # the results of multiple invocations.
      @resolver ||= BaseOidResolver.new(self, rugged)
      @resolver.resolve(commit1_oid, commit2_oid, base_commit_oid)
    end

    # We can only accurately determine an ideal base oid (tree or commit) if all of
    # oid1, oid2, and base_oid are commits. But sometimes a diff might need to be
    # between a tree and a commit, or two blobs, etc for reasons. In these
    # cases, we safely fail the resolution process but just default to oid1 instead
    # of raising an error.
    def resolve_base_for_diff(oid1, oid2, base_oid)
      resolve_base_oid(oid1, oid2, base_oid)
    rescue GitRPC::InvalidObject => e
      oid1
    end
  end
end
