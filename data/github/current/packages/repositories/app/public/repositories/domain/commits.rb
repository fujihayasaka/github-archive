# typed: strict
# frozen_string_literal: true

module Repositories
  class Domain
    class Commits < GH::Domain::Base
      # Find a single commit from the underying git repository. This is the
      # main commit reading chokepoint. Commit metadata should not be read without
      # going through this method.
      #
      # commit_oid         - Single string oid.
      # check_reachability - check if the commits is reachable (from branches or tags)
      #                      non-reachable commits will be treated as if they don't exist
      #                      (optional, default: false)
      #
      # Returns a single Commit object. Returns nil for
      # a nil argument or if any other GitRPC errors are raised.
      #
      # Raises ArgumentError when commit_oids includes a malformed oid.
      # Raises GitRPC::ObjectMissing when the requested commit does not exist.
      # Raises GitRPC::InvalidObject when an object was found but is not a commit.
      sig do
        params(
          repository: IRepository,
          commit_oid: String,
          check_reachability: T::Boolean,
        ).returns(T.nilable(Commit))
        .checked(:always)
        .on_failure(:raise)
      end
      def by_oid(repository:, commit_oid:, check_reachability: false)
        by_oids(repository: repository, commit_oids: [commit_oid], check_reachability: check_reachability).first
      end


      # Find multiple commits from the underying git repository. This is the
      # main commit reading chokepoint. Commit metadata should not be read without
      # going through this method.
      #
      # commit_oids        - An array of oids.
      # check_reachability - check if the commits are reachable (from branches or tags)
      #                      non-reachable commits will be treated as if they don't exist
      #                      (optional, default: false)
      #
      # Returns an array of Commit objects. Returns an empty array for
      # a nil argument or if any other GitRPC errors are raised.
      #
      # Raises ArgumentError when commit_oids includes malformed oids.
      # Raises GitRPC::ObjectMissing when any of the requested commits does not exist.
      # Raises GitRPC::InvalidObject when an object was found but is not a commit.
      sig do
        params(
          repository: IRepository,
          commit_oids: T::Array[String],
          check_reachability: T::Boolean,
        ).returns(T::Array[Commit])
        .checked(:always)
        .on_failure(:raise)
      end
      def by_oids(repository:, commit_oids:, check_reachability: false) # rubocop:todo Metrics/MethodLength
        return [] if commit_oids.nil?

        repository = T.cast(repository, Repository) # rubocop:todo GitHub/AvoidCast
        oids = commit_oids.map(&:downcase)
        objects = repository.objects.read(oids, "commit")

        return objects unless check_reachability

        repository.rpc.commits_visible(Array(oids)).each do |oid, visible|
          raise GitRPC::ObjectMissing.new("commit not reachable", oid) unless visible
        end

        objects
      rescue GitRPC::Failure => boom
        if boom.original.class == Rugged::InvalidError
          raise ArgumentError, boom.original.message
        else
          []
        end
      end

      # Public: Given a merge commit for a pull request, and a new message and author,
      # create a new merge commit with the same tree.
      #
      # repository - The repository to update the merge commit in.
      # commit_oid - The sha of the merge commit to update the information for.
      # info       - The hash of information to update on the merge commit.
      # squash     - If true, squash the merge commit to a single parent.
      # require_signature - If true, raise an exception if the commit signing fails.
      #                     If false, proceed silently whether the commit signing succeeds or not.
      #
      # The info argument is for specifying commit metadata. It has the
      # following structure:
      #
      #     { 'message'   => required string commit message,
      #       'committer' => required committer information hash,
      #       'author'    => optional author information hash }
      #
      # The committer and author hashes have the following members:
      #
      #     { 'name'      => required full name string,
      #       'email'     => required email address string,
      #       'time'      => required ISO8601 time string }
      #
      # The committer information hash is required; the author is optional. If
      # no author is given the committer information is used in both places.
      #
      # Returns the string oid of the newly created merge commit.
      #
      # Raises a Repositories::Error::SignatureError if the commit signing fails and the require_signature option is true.
      sig do
        params(
          repository: IRepository,
          commit_oid: String,
          info: T::Hash[String, T.untyped],
          squash: T::Boolean,
          require_signature: T.nilable(T::Boolean),
        ).returns(String)
        .checked(:always)
        .on_failure(:raise)
      end
      def rewrite_merge_commit(repository:, commit_oid:, info:, squash: false, require_signature: false) # rubocop:todo Metrics/MethodLength
        repository = T.cast(repository, Repository) # rubocop:todo GitHub/AvoidCast
        created_sha = repository.rpc.rewrite_merge_commit(commit_oid, info, squash) do |commit_body|
          if signature = repository.sign_commit(commit_body)
            signature
          elsif require_signature
            raise Repositories::Error::SignatureError
          else
            nil # continue with unsigned commit
          end
        end
        publish_commit_created_event(repository: repository, created_shas: created_sha)
        created_sha
      end

      # Public: Update the committer info for a range of commits
      #
      # repository     - The id of the repository to update the merge commit in.
      # start_commit_oid  - String the commit oid for the start of the range.
      # end_commit_oid    - String the commit oid for the end of the range. Commit
      #                     information for this commit will not be updated.
      # name - String containing the committer's full name
      # email - String containing the committer's email
      # time - String containing the commit time
      #
      # Returns a String containing the oid of the updated version of
      # the `start_commit_oid` commit.
      sig do
        params(
          repository: IRepository,
          start_commit_oid: String,
          end_commit_oid: String,
          email: String,
          name: String,
          time: String,
        ).returns(String)
        .checked(:always)
        .on_failure(:raise)
      end
      def update_committer_info(repository:, start_commit_oid:, end_commit_oid:, email:, name:, time:)
        repository = T.cast(repository, Repository) # rubocop:todo GitHub/AvoidCast
        new_start_commit_oid = repository.rpc.update_committer_info(start_commit_oid, end_commit_oid, {
          email: email,
          name: name,
          time: time,
        })

        # start_oid and end_oid above are backwards from how we typicall use them. update_committer_info
        # looks backwards through commits from a child start_commit_oid to its parent end_commit_oid. Other places,
        # like the job that listens to this event, iterate forward through commits starting from the parent and
        # ending at a child. So, we need to use the end_commit_oid as the start_sha and the new_start_commit_oid
        # as the end_sha.
        publish_commit_created_event(
          repository: repository,
          created_shas: { start_sha: end_commit_oid, end_sha: new_start_commit_oid }
        ) unless new_start_commit_oid == start_commit_oid
        new_start_commit_oid
      end

      # Public: Create a new commit with a set of changes to an existing commit.
      # The changes specified may be applied as offsets to an existing tree (e.g.,
      # only modify the `README`) or as a whole new tree that replaces the prior
      # tree entirely.
      #
      # repository  - The id of the repository to update the merge commit in.
      # parent_oids    - Array of oid string(s) of the parent commit(s) or nil to create
      #                  a commit with no parents and an entirely new tree.
      # info      - The commit information hash. See the extended documention for
      #             details on this data structure.
      # files     - Hash of filename => data pairs. The filename must be a
      #             string and may include slashes into subtrees. The data should
      #             be a Hash with the following acceptable keys.
      #
      #             data   - String blob content of the new tree entry
      #             mode   - Numeric (octal) file mode, e.g. 0100644 or 0100755
      #             source - String path of an old tree entry to remove (for file
      #                      moves). Will also provide mode and data if not
      #                      overridden.
      #
      #             For simplicity, the data may also be a string with the entire
      #             blob content of the new tree entry.
      # sign_commit - If true, signature parameter is ignored and we will try to sign the commit
      #               with GitHub's web-committer GPG key.
      # signature - String signature to include in commit. (Optional)
      #
      # The info argument is for specifying commit metadata. It has the
      # following structure:
      #
      #     { "message"   => required string commit message,
      #       "committer" => required committer information hash,
      #       "author"    => optional author information hash }
      #
      # The committer and author hashes have the following members:
      #
      #     { "name"      => required full name string,
      #       "email"     => required email address string,
      #       "time"      => optional ISO8601 time string }
      #
      # The committer information hash is required; the author is optional. If
      # no author is given the committer information is used in both places.
      #
      # Returns the string oid of the newly created commit.
      sig do
        params(
          repository: IRepository,
          parent_oids: T.nilable(T::Array[String]),
          info: T::Hash[String, T.untyped],
          files: T.nilable(T::Hash[String, T.any(T::Hash[T.any(String, Symbol), T.untyped], String)]),
          sign_commit: T.nilable(T::Boolean),
          signature: T.nilable(String)
        ).returns(String)
        .checked(:always)
        .on_failure(:raise)
      end
      def create_tree_changes(repository:, parent_oids:, info:, files:, sign_commit: false, signature: nil)
        repository = T.cast(repository, Repository) # rubocop:todo GitHub/AvoidCast
        created_sha = if sign_commit
          repository.rpc.create_tree_changes(parent_oids, info, files, &repository.method(:sign_commit))
        else
          repository.rpc.create_tree_changes(parent_oids, info, files, signature)
        end
        publish_commit_created_event(repository: repository, created_shas: created_sha)
        created_sha
      end

      private

      sig do
        params(
          repository: T.any(::Repository, ::Gist, GitHub::Unsullied::Wiki),
          created_shas: T.any(String, T::Array[String], { start_sha: String, end_sha: String }),
        ).void
      end
      def publish_commit_created_event(repository:, created_shas:)
        # We only publish events for commits in a repository - not Gists or Wikis.
        return unless repository.is_a?(::Repository)
        created_shas = Array(created_shas) if created_shas.is_a?(String)

        GitHub.aqueduct_fallback_hydro_publisher.publish(
          {
            repository_id: repository.id,
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            created_at: Time.now,
            commit_shas: created_shas.is_a?(Array) ? created_shas : nil,
            start_sha: created_shas.is_a?(Hash) ? created_shas[:start_sha] : nil,
            end_sha: created_shas.is_a?(Hash) ? created_shas[:end_sha] : nil,
            user_login: actor&.display_login,
            enabled_flags: Repositories::HydroPushJobFlags.enabled_for_repo(repository)
          },
          schema: "github.repositories.v1.CommitsCreated",
          partition_key: repository.id
        )
      end
    end
  end
end
