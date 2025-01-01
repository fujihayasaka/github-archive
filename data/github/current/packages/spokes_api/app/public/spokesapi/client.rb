# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SpokesAPI
  class Client
    include Scientist

    # Public: returns a new Client for the given Repository.
    def self.for_repository(repository_id, network_id:, timeout: nil)
      new(Types.new_repository(repository_id), headers: { "GitHub-Network-Id-Hint" => network_id.to_s }, timeout: timeout)
    end

    # Public: returns a new Client for the given Gist.
    def self.for_gist(gist_id, gist_name:, timeout: nil)
      new(Types.new_gist(gist_id), headers: { "GitHub-Gist-Name-Hint" => gist_name }, timeout: timeout)
    end

    # Public: returns a new Client for the given Repository's wiki.
    def self.for_wiki(repository_id, network_id:, timeout: nil)
      new(Types.new_wiki(repository_id), headers: { "GitHub-Network-Id-Hint" => network_id.to_s }, timeout: timeout)
    end

    # Public: returns a new Client for multiple Repositories.
    def self.for_repositories(repository_ids, timeout: nil)
      new(nil, repositories: repository_ids.map { |id| Types.new_repository(id) }, timeout: timeout)
    end

    def initialize(repository, headers: nil, repositories: nil, timeout: nil)
      request_headers = {}
      request_headers["Request-Timeout"] = SpokesAPI.timeout.to_s if SpokesAPI.timeout
      request_headers["Request-Timeout"] = timeout.to_s if timeout
      request_headers.update(headers) if headers

      @repository = repository
      @repositories = repositories
      @req_opts = { headers: request_headers }
    end

    # The repository stored here is the one from Spokes API, that is
    # types.Repository.
    attr_reader :repository
    attr_reader :repositories

    # Public: Fetch a single entry in a tree by the path using TreesAPI.ReadTreeEntryOid.
    #
    # oid:
    #   (String, required) OID of the commit to find the tree entry in.
    # path:
    #   (String, optional) Path to the tree entry to return. If path is not
    #     passed the root tree is returned.
    # type:
    #   (String, optional) The type of object we are expecting. If type is not
    #     does not match, an exception is raised. Defaults to returning any type.
    #
    # Returns the OID of the tree entry.
    def read_tree_entry_oid(oid:, path: nil, type: nil, qos: nil)
      GitRPC::Util.ensure_valid_full_oid(oid)

      path = GitRPC::Util.normalize_path(path)
      if path != nil && path != ""
        path = { name: path }
      end

      if type != nil && type != ""
        type = case type
        when "commit"
          { type: :TYPE_COMMIT }
        when "tree"
          { type: :TYPE_TREE }
        when "blob"
          { type: :TYPE_BLOB }
        when "tag"
          { type: :TYPE_TAG }
        else
          raise ArgumentError, "invalid type #{type.inspect}"
        end
      end

      request = {
        repository: repository,
        treeish_selector: {
          treeish: { oid: { id: oid } },
        },
        path: path,
        type: type,
      }

      request[:request_context] = default_request_context(qos: qos)
      resp = process_response(client.trees.read_tree_entry_oid(request, @req_opts))
      resp.oid.id
    end

    # Public: Compare two trees using TreesAPI.CompareTrees.
    #
    # before:
    #   (String, required) OID of starting commit or tree
    # after:
    #   (String, required) OID of ending commit or tree
    # include_renames:
    #   (Bool, default is false) If set, combine renames into a "rename" diff
    #   entry rather than a separate delete and add.
    # max_entries:
    #   (Number, default is 1) Request more pages of results until this number
    #   of entries has been received.
    # paths:
    #   (Array of Strings, optional) If set, only include diffs for these paths.
    #
    # Returns a list of SpokesAPI::Types::DiffEntry.
    def compare_oids(before:, after:, include_renames: false, max_entries: 1, paths: nil)
      # When either OID is not set, GitRPCd will return an error. The callers
      # don't need results in those cases, though, so we'll skip the RPC call.
      #
      # See https://github.com/github/git-storage/issues/564 for a related issue.
      return [] if before == NULL_OID || after == NULL_OID

      request = {
        repository: repository,
        range_selector: {
          start: { oid: { id: before } },
          end: { oid: { id: after } },
          paths: paths&.map { |path| { name: path } }
        },
        include_renames: include_renames,
        recursive: true,
      }

      request[:request_context] = default_request_context

      result = []

      while result.size < max_entries
        resp = process_response(client.trees.compare_trees(request, @req_opts))
        resp.entries.each do |e|
          result << Types::DiffEntry.new(e)
        end
        if resp.next_cursor
          request[:cursor] = resp.next_cursor
        else
          break
        end
      end

      result
    end

    # Public: Return the list of tree entries associated for a given tree OID.
    #
    # tree_oid: (String, required) OID of the tree
    # recursive: (Bool, optional, default is false) Indicates if the tree should be traversed recursively
    # cursor: (String, optional) The cursor to fetch
    #
    # Returns a list of GitHub::Spokes::Proto::Types::V1::TreeEntry and the cursor to fetch the next page.
    def list_tree_entries(tree_oid:, recursive: false, cursor: nil)
      req = {
        repository: repository,
        treeish_selector: {
          treeish: {
            oid: { id: tree_oid }
          },
        },
        recursive:,
      }

      req[:request_context] = default_request_context
      req[:cursor] = cursor unless cursor.nil?

      process_response(client.trees.list_trees(req, @req_opts))
    end

    # Public: Return the list of authors and coauthors for a ref update.
    #
    # Optionally takes a block that will be called after each batch of contributors.
    #
    # reference_updates (Array, required):
    #   ref_name:
    #     (String, required) A ref
    #   previous_ref_oid:
    #     (String, required) OID of starting commit or tree
    #   current_ref_oid:
    #     (String, required) OID of ending commit or tree
    # historical:
    #   (Bool, optional, default is false) Unless set, only consider commits distinct to these ref updates
    #
    # Returns a list of contributor emails.
    def list_contributors(reference_updates:, historical: false)
      selector = if historical
        :historical_push_selector
      else
        :push_selector
      end

      request = {
        :repository => repository,
        selector => {
          reference_updates: reference_updates.map do |update|
            {
              reference: { name: update[:ref_name].b },
              before: { id: update[:previous_ref_oid] },
              after: { id: update[:current_ref_oid] },
            }
          end
        },
      }
      request[:request_context] = default_request_context

      emails = Set.new

      loop do
        resp = process_response(client.commits.list_contributors(request, @req_opts))
        request[:cursor] = resp.next_cursor
        emails.merge resp.contributors.map(&:email_bytes)
        break if request[:cursor].nil?
        yield if block_given?
      end

      emails
    end

    # Public: Return a single resolved object by revision.
    #
    # object_name:
    #   (String, required) A revision that will be used to look up the object
    def resolve_object(object_name:)
      raise TypeError, "object_name must be specified" if object_name.nil?
      return nil unless object_name.valid_encoding?
      return if object_name.split(":").first.include?("..")
      return object_name if SpokesAPI::Util.valid_oid?(object_name)

      req = {
        repository: repository,
        object_name: {
          name: object_name.b,
        },
      }

      # Override qos to be "no-delay".
      #
      # ResolveObject is not computationally complex, and the callers are
      # spread throughout the app and probably assume that they can get a valid
      # response to this request. So we should prefer the small amount of extra
      # load so that we can get a result.

      raw = science "spokes_api.resolve_object_read_after_write" do |e|
        e.context({ req: req, req_opts: @req_opts })
        e.use do
          req[:request_context] = default_request_context(qos: :QUALITY_OF_SERVICE_NO_DELAY)
          client.objects.resolve_object(req, @req_opts)
        end
        e.try do
          req[:request_context] = default_request_context(qos: :QUALITY_OF_SERVICE_NO_DELAY, read_after_write: false)
          client.objects.resolve_object(req, @req_opts)
        end
        e.compare do |control, candidate|
          if control.error && candidate.error
            control.error.code == candidate.error.code
          else
            control.data == candidate.data
          end
        end
      end

      return nil if raw.error && raw.error.code == :not_found
      return nil if raw.error && raw.error.code == :unavailable
      return nil if raw.error && raw.error.code == :invalid_argument
      resp = process_response(raw)
      resp.oid.id
    end

    # Public: Return a list of resolved objects by OIDs.
    #
    # oids:
    #  (String, required) A list of OIDs to resolve
    # read_uncommitted: (Bool, optional, default is false) Should only be set when data is read during _commit_refs
    def resolve_objects(oids:, read_uncommitted: false)
      req = {
        request_context: default_request_context,
        repository: repository,
        selectors: oids.map { |oid| { by_id: { id: oid } } },
      }

      req[:request_context][:read_uncommitted] = read_uncommitted
      process_response(client.objects.resolve_objects(req, @req_opts))
    end

    # Public: Return a list of resolved objects for each selector
    #
    # selectors:
    #  (Array<Hash>, required) A list of selectors to resolve.
    #   Each selector is a hash with the following keys:
    #    by_id { id: }: The OID to resolve
    #    by_name: { name: }: The ref to resolve
    #    by_treeish_and_path: { treeish: { reference: { name: }, oid: { id: } }, path: { name: } }: The treeish and path to resolve
    #
    # read_uncommitted: (Bool, optional, default is false) Should only be set when data is read during _commit_refs
    def resolve_objects_by(selectors, read_uncommitted: false)
      req = {
        request_context: default_request_context,
        repository: repository,
        selectors: selectors,
      }

      req[:request_context][:read_uncommitted] = read_uncommitted
      process_response(client.objects.resolve_objects(req, @req_opts))
    end

    # Public: Return the list of historical reachable blobs.
    #
    # reference_updates (Array, required):
    #   ref_name:
    #     (String, required) A ref
    #   previous_ref_oid:
    #     (String, required) OID of starting commit or tree
    #   current_ref_oid:
    #     (String, required) OID of ending commit or tree
    # cursor: (String, required) The cursor to fetch
    # read_uncommitted: (Bool, optional, default is false) Should only be set when data is read during _commit_refs
    #
    # Returns a list of blobs and the cursor to fetch the next page.
    def list_historical_reachable_blobs(reference_updates:, cursor:, read_uncommitted: false)
      reference_updates = reference_updates.map do |update|
        {
          reference: { name: update[:ref_name].b },
          before: { id: update[:previous_ref_oid] },
          after: { id: update[:current_ref_oid] },
        }
      end

      req = {
        request_context: default_request_context,
        repository: repository,
        historical_push_selector: {
          reference_updates: reference_updates
        },
      }

      req[:request_context][:read_uncommitted] = read_uncommitted
      req[:cursor] = cursor unless cursor.nil?

      process_response(client.blobs.list_reachable_blobs(req, @req_opts))
    end

    # Public: Return the list of newly reachable blobs.
    #
    # reference_updates (Array, required):
    #   ref_name:
    #     (String, required) A ref
    #   previous_ref_oid:
    #     (String, required) OID of starting commit or tree
    #   current_ref_oid:
    #     (String, required) OID of ending commit or tree
    # cursor: (String, required) The cursor to fetch
    # base_repository_id: (Integer, optional, default is nil) The root repository id for forks
    # read_uncommitted: (Bool, optional, default is false) Should only be set when data is read during _commit_refs
    #
    # Returns a list of blobs and the cursor to fetch the next page.
    def list_newly_reachable_blobs(reference_updates:, cursor:, base_repository_id:, read_uncommitted: false)
      reference_updates = reference_updates.map do |update|
        {
          reference: { name: update[:ref_name].b },
          before: { id: update[:previous_ref_oid] },
          after: { id: update[:current_ref_oid] },
        }
      end

      if base_repository_id.nil?
        selector_type = :push_selector
        selector = {
          reference_updates: reference_updates
        }
      else
        selector_type = :fork_push_selector
        selector = {
          base_repository: Types.new_repository(base_repository_id),
          reference_updates: reference_updates
        }
      end

      req = {
        :request_context => default_request_context,
        :repository => repository,
        selector_type => selector,
      }

      req[:request_context][:read_uncommitted] = read_uncommitted
      req[:cursor] = cursor unless cursor.nil?

      process_response(client.blobs.list_reachable_blobs(req, @req_opts))
    end

    # Public: Return the list of commits based on a list of OIDs.
    #
    # oids (Array, required):
    # cursor: (String, required) The cursor to fetch
    # read_uncommitted: (Bool, optional, default is false) Should only be set when data is read during _commit_refs
    #
    # Returns a list of reachable blobs and the cursor to fetch the next page.
    sig { params(oids: T::Array[String], cursor: T.nilable(String), read_uncommitted: T::Boolean).returns(GitHub::Spokes::Proto::Commits::V1::ListCommitsResponse) }
    def list_commits_for_ids(oids:, cursor:, read_uncommitted: false)
      req = {
        request_context: default_request_context,
        repository: repository,
        object_id_selector: {
          oids: oids.map { |oid| { id: oid } }
        }
      }

      req[:request_context][:read_uncommitted] = read_uncommitted
      req[:cursor] = cursor unless cursor.nil?

      process_response(client.commits.list_commits(req, @req_opts))
    end

    # Public: Return the list of commits based on git revisions.
    #
    # revisions (Array, required): String(s) in the format of a Git revision (https://git-scm.com/docs/gitrevisions)
    #                              to list commits for.
    # cursor: (String, required) The cursor to fetch
    #
    # Returns a list of commits that are reachable by following the parent links from the commit(s), but exclude
    # commits that are reachable from the one(s) given with a ^ in front of them. The output is given in reverse
    # chronological order by default.
    sig { params(revisions: T::Array[String], cursor: T.nilable(String)).returns(GitHub::Spokes::Proto::Commits::V1::ListCommitsResponse) }
    def list_commits_for_revisions(revisions:, cursor:)
      req = {
        request_context: default_request_context,
        repository: repository,
        revision_selector: {
          revisions: revisions.map { |revision| { name: revision } }
        }
      }

      req[:cursor] = cursor unless cursor.nil?

      process_response(client.commits.list_commits(req, @req_opts))
    end

    # Public: Return the list of historical commits.
    #
    # reference_updates (Array, required):
    #   ref_name:
    #     (String, required) A ref
    #   previous_ref_oid:
    #     (String, required) OID of starting commit or tree
    #   current_ref_oid:
    #     (String, required) OID of ending commit or tree
    # cursor: (String, required) The cursor to fetch
    # read_uncommitted: (Bool, optional, default is false) Should only be set when data is read during _commit_refs
    #
    # Returns a list of commits and the cursor to fetch the next page.
    def list_historical_commits(reference_updates:, cursor:, read_uncommitted: false)
      reference_updates = reference_updates.map do |update|
        {
          reference: { name: update[:ref_name].b },
          before: { id: update[:previous_ref_oid] },
          after: { id: update[:current_ref_oid] },
        }
      end

      req = {
        request_context: default_request_context,
        repository: repository,
        historical_push_selector: {
          reference_updates: reference_updates
        },
      }

      req[:request_context][:read_uncommitted] = read_uncommitted
      req[:cursor] = cursor unless cursor.nil?

      process_response(client.commits.list_commits(req, @req_opts))
    end

    # Public: Return the list of newly reachable commits.
    #
    # reference_updates (Array, required):
    #   ref_name:
    #     (String, required) A ref
    #   previous_ref_oid:
    #     (String, required) OID of starting commit or tree
    #   current_ref_oid:
    #     (String, required) OID of ending commit or tree
    # cursor: (String, required) The cursor to fetch
    # base_repository_id: (Integer, optional, default is nil) The root repository id for forks
    # read_uncommitted: (Bool, optional, default is false) Should only be set when data is read during _commit_refs
    #
    # Returns a list of commits and the cursor to fetch the next page.
    def list_newly_reachable_commits(reference_updates:, cursor:, base_repository_id:, read_uncommitted: false)
      reference_updates = reference_updates.map do |update|
        {
          reference: { name: update[:ref_name].b },
          before: { id: update[:previous_ref_oid] },
          after: { id: update[:current_ref_oid] },
        }
      end

      if base_repository_id.nil?
        selector_type = :push_selector
        selector = {
          reference_updates: reference_updates
        }
      else
        selector_type = :fork_push_selector
        selector = {
          base_repository: Types.new_repository(base_repository_id),
          reference_updates: reference_updates
        }
      end

      req = {
        :request_context => default_request_context,
        :repository => repository,
        selector_type => selector,
      }

      req[:request_context][:read_uncommitted] = read_uncommitted
      req[:cursor] = cursor unless cursor.nil?

      process_response(client.commits.list_commits(req, @req_opts))
    end

    # Public: Return the list of pushed commits.
    #
    # reference_updates (Array, required):
    #   ref_name:
    #     (String, required) A ref
    #   previous_ref_oid:
    #     (String, required) OID of starting commit or tree
    #   current_ref_oid:
    #     (String, required) OID of ending commit or tree
    # cursor: (String, required) The cursor to fetch
    # base_repository_id: (Integer, optional, default is nil) The root repository id for forks
    #
    # Returns a list of blobs and the cursor to fetch the next page.
    def list_pushed_blobs(reference_updates:, cursor:, base_repository_id:)
      reference_updates = reference_updates.map do |update|
        {
          reference: { name: update[:ref_name].b },
          before: { id: update[:previous_ref_oid] },
          after: { id: update[:current_ref_oid] },
        }
      end

      if base_repository_id.nil?
        selector_type = :push_selector
        selector = {
          reference_updates: reference_updates
        }
      else
        selector_type = :fork_push_selector
        selector = {
          base_repository: Types.new_repository(base_repository_id),
          reference_updates: reference_updates
        }
      end

      req = {
        :request_context => default_request_context,
        :repository => repository,
        selector_type => selector,
      }

      req[:cursor] = cursor unless cursor.nil?

      process_response(client.blobs.list_pushed_blobs(req, @req_opts))
    end

    # Public: Return the list of commits in quarantine based on a push_state.
    #
    # push_state (String, required): The push state to use to look up the quarantine
    # cursor: (String, required) The cursor to fetch
    #
    # Returns a list of commits and the cursor to fetch the next page.
    def list_quarantine_commits(push_state:, cursor: nil)
      req = {
        request_context: default_request_context.merge(push_state: push_state),
        repository: repository,
        quarantine_commits_selector: {},
      }
      req[:cursor] = cursor unless cursor.nil?

      process_response(client.commits.list_commits(req, @req_opts))
    end

    def list_references_with_details(globs:, ignore_case: true)
      request = {
        repository: repository,
        ref_glob_selector: {
          globs: globs.map { |glob| { glob: glob } },
          ignore_case: ignore_case
        }
      }

      request[:request_context] = default_request_context

      result = client.references.list_references_with_details(request, @req_opts)

      result
    end

    # Public: Return the name of the repo's default branch, represented by the
    # value pointed to by the HEAD symbolic ref.
    #
    # TODO: this endpoint currently runs with a forced "no-delay" quality of
    # service to alleviate the immediate issues encountered due to throttling.
    # The override will be removed in the future to ensure our systems are
    # properly protected.
    #
    # Returns the name of the default branch.
    def get_default_branch
      request = {
        request_context: default_request_context(qos: :QUALITY_OF_SERVICE_NO_DELAY),
        repository: repository
      }

      resp = process_response(client.references.get_default_branch(request, @req_opts))
      resp.reference.name.dup.force_encoding("UTF-8")
    end

    # Public: Get replica list and extra sockstat variables for a Git operation.
    #
    # action:
    #   (String, required) one of "write" or "read".
    # protocol:
    #   (String, required) one of "http", "git", "ssh", or "svn".
    #
    # Returns a GitHub::Spokes::Proto::Gitauth::V1::ListRoutesResponse.
    def list_routes(action:, protocol:)
      action =
        case action
        when "read"
          :ACTION_READ
        when "write"
          :ACTION_WRITE
        else
          raise ArgumentError, "unrecognized action #{action.inspect}"
        end

      protocol =
        case protocol
        when "http"
          :PROTOCOL_HTTP
        when "git"
          :PROTOCOL_GIT
        when "ssh"
          :PROTOCOL_SSH
        when "svn"
          :PROTOCOL_SVN
        else
          raise ArgumentError, "unrecognized protocol #{protocol.inspect}"
        end

      request = {
        repository: repository,
        action: action,
        protocol: protocol,
      }

      process_response(client.gitauth.list_routes(request, @req_opts))
    end

    # Public: Generate push_state for use in Spokes Access API calls during a
    # push while objects are still quarantined.
    #
    # quarantine_id:
    #   (String, required) the quarantine id.
    # host_status:
    #   (Hash, required) the host_status data provided by babeld.
    #   See https://github.com/github/babeld/blob/8c6cd3c87fb8a582855519d7b874a56f49e20b45/src/gitauth.c#L795-L807
    #
    # Returns a binary string with the push state to add to future request
    # contexts.
    def set_up_push_state(quarantine_id:, host_status:)
      request = {
        repository: repository,
        quarantine_id: quarantine_id,
        hosts: [],
      }
      host_status.each do |k, v|
        host, path = k.split(":", 2)
        host_info = {
          host: host,
          path: path,
        }

        host_res = v.fetch("result")
        if host_res == "ok"
          host_info[:ok_result] = {}
        else
          host_info[:error_result] = { error_message: host_res }
        end

        request[:hosts] << host_info
      end

      resp = process_response(client.gitauth.set_up_push_state(request, @req_opts))
      resp.push_state
    end

    # Public: Commit a quarantine.
    #
    # push_state:
    #   (Binary string, required) the push state.
    #
    # Returns an updated push state.
    def commit_quarantine(push_state:, preserve_quarantine: false)
      request = {
        repository: repository,
        request_context: default_request_context.merge(push_state: push_state),
        preserve_quarantine: preserve_quarantine
      }
      # A failure here could mean that there's a split decision or that the
      # push only has deletions. In either case, a later phase of the push will
      # fail if a failure here is significant.
      resp = client.gitauth.commit_quarantine(request, @req_opts)
      if resp.data
        return resp.data.push_state
      end
      nil
    end

    # Public: Remove a quarantine.
    # Either push state or quarantine_id must be provided.
    #
    # push_state:
    #   (Binary string, optional) the push state.
    # quarantine_id:
    #   (String, optional) the quarantine id.
    #
    # Returns nothing.
    def remove_quarantine(push_state: nil, quarantine_id: nil)
      request_context = default_request_context
      request_context[:push_state] = push_state unless push_state.nil?

      request = { repository: repository, request_context: request_context }
      request[:quarantine_id] = quarantine_id unless quarantine_id.nil?

      # Note: This is a best-effort RPC, so don't call process_response which
      # would raise errors to the caller. This does mean that errors are
      # probably ignored, but we can monitor them in spokesd and other git
      # systems, so we don't need to make noise here. would raise errors to the
      # caller.
      client.gitauth.remove_quarantine(request, @req_opts)
    end

    # Public: Get ahead/behind counts for a list of tips relative to a common base.
    #
    # base:
    #   (String, required) a committish for the base comparison commit.
    # tips:
    #   (String array, required) an array of strings, each a committish for
    #   a tip to compare against the base.
    #
    # Returns a Hash mapping tip committish strings to tuples containing the
    # ahead/behind values.
    def ahead_behind(base:, tips:)
      request = {
        repository: repository,
        base_and_tips_selector: {
          base: { name: base },
          tips: tips.map { |tip| { name: tip } },
        },
        request_context: default_request_context,
      }

      resp = process_response(client.commits.ahead_behind(request, @req_opts))

      resp.ahead_behind_pairs.map { |pair| [pair.tip.name, [pair.ahead, pair.behind]] }
    end

    # Public: Get an array of tips which are contained in a given base
    # (but not how far behind those tips are).
    #
    # base:
    #   (String, required) a committish for the base comparison commit.
    # tips:
    #   (String array, required) an array of strings, each a committish for
    #   a tip to compare against the base.
    #
    # Returns an array of tips which are contained in the base.
    def ahead_behind_contains(base:, tips:)
      request = {
        repository: repository,
        base_and_tips_selector: {
          base: { name: base },
          tips: tips.map { |tip| { name: tip } },
        },
        request_context: default_request_context,
      }

      resp = process_response(client.commits.ahead_behind_contains(request, @req_opts))

      resp.tips.map { |tip| tip.name }
    end

    # Public: Get the cache key for a repository.
    #
    # Returns a String containing the cache key.
    def get_cache_key
      request = {
        repository: repository,
        use_primary: read_after_write?,
      }

      begin
        resp = process_response(client.legacygitrpc.get_cache_key(request, @req_opts))
        resp.cache_key
      rescue SpokesAPI::NotFound
        nil
      end
    end

    # Public: Get the cache keys for multiple repositories.
    #
    # Returns a Hash mapping each repository ID to its cache key.
    def get_cache_keys
      request = {
        repositories: repositories,
        use_primary: read_after_write?,
      }

      resp = process_response(client.legacygitrpc.get_cache_keys(request, @req_opts))
      resp.repositories_with_cache_keys

      result = {}
      resp.repositories_with_cache_keys.each do |repo_with_cache_key|
        result[repo_with_cache_key.repository.id] = repo_with_cache_key.cache_key
      end

      result
    end

    # Public: Get latest commit to change each path within a directory.
    #
    # commit_oid:
    #  (String, required) the commit OID to use as the start of the history walk.
    # path:
    #  (String, optional) the path to use as the base tree.
    # recursive:
    #  (Boolean, required) whether or not to recurse into subdirectories.
    #
    # Returns a hash mapping paths to commit OIDs.
    def blame_tree(commit_oid, path = nil, recursive = false)
      request_context = default_request_context
      request_path = nil

      if path != nil && path != ""
        request_path = { name: path }
      end

      request = {
        repository: repository,
        blame_tree_selector: {
          commit: { name: commit_oid },
          path: request_path,
          recursive: recursive,
        },
        request_context: request_context,
      }

      resp = process_response(client.commits.blame_tree(request, @req_opts))

      resp.pairs.map { |pair| [pair.path.name.b, pair.oid.id] }.to_h
    end

    def read_diff_summary(commit1_oid:, commit2_oid:, base_commit_oid:, commit1_repo: nil, commit2_repo: nil, base_commit_repo: nil, with_stats: true, ignore_whitespace: false)
      request_context = default_request_context
      request = {
        repository: repository,
        diff_algorithm: :DIFF_ALGORITHM_DEFAULT,
        ignore_whitespace: ignore_whitespace,
        include_stat: with_stats,
        request_context: request_context,
      }
      if commit1_repo && commit1_oid
        request[:repo_object_id1] = { base_repository: Types.new_repository(commit1_repo.id), oid: { id: commit1_oid } }
      elsif commit1_oid
        request[:object_id1] = { id: commit1_oid }
      else
        request[:root_selector1] = {}
      end
      if commit2_repo && commit2_oid
        request[:repo_object_id2] = { base_repository: Types.new_repository(commit2_repo.id), oid: { id: commit2_oid } }
      elsif commit2_oid
        request[:object_id2] = { id: commit2_oid }
      end
      if base_commit_repo && base_commit_oid
        request[:repo_base_object_id] = { base_repository: Types.new_repository(base_commit_repo.id), oid: { id: base_commit_oid } }
      elsif base_commit_oid
        request[:base_object_id] = { id: base_commit_oid }
      else
        request[:none_base] = {}
      end

      resp = process_response(client.diffs.read_diff_summary(request, @req_opts))

      # This format (minus the contains_status field) is designed to map
      # directly to the legacy GitRPC::Diff::Summary data for easy
      # transformation.
      {
        contains_status: with_stats,
        additions: resp.stat.additions,
        deletions: resp.stat.deletions,
        changed_files: resp.stat.changed_files,
        deltas: resp.deltas.map do |delta|
          d = delta.delta
          resp = {
            old_file: {
              oid: d.old_tree_node.object.oid.id,
              mode: "%06o" % d.old_tree_node.mode.mode,
              path: d.old_tree_node.path.name,
            },
            new_file: {
              oid: d.new_tree_node.object.oid.id,
              mode: "%06o" % d.new_tree_node.mode.mode,
              path: d.new_tree_node.path.name,
            },
            similarity: d.similarity,
            status: d.diff_status.to_s.delete_prefix("DIFF_STATUS_").upcase[0],
          }
          changes = if delta.text_changes
            { additions: delta.text_changes.additions, deletions: delta.text_changes.deletions }
          elsif delta.binary_changes
            { additions: nil, deletions: nil }
          else
            nil
          end
          resp.update(changes) if changes
          resp
        end
      }
    end

    def self.resolve_references_ref_limit
      # TODO: once we've upgraded to google-protobuf v3.18 or later, extract
      # this from the 'limit' field option of 'ResolveReferencesRequest.references'.
      10000
    end

    def resolve_references(refnames)
      return [] if refnames.empty?

      request = {
        repository: repository,
        references: refnames.map do |ref|
          # Request requires binary string encoding, force encoding to avoid
          # Encoding::UndefinedConversionError.
          ref = ref.b

          # Dedupe adjacent slashes if necessary
          #
          # This is a holdover from an older Rugged implementation of the GitRPC
          # endpoint 'read_qualified_refs'. Adjacent slashes were silently
          # ignored in the Rugged-based 'read_qualified_refs, but are not in
          # 'resolve_references'. We unfortunately seem to rely on this silent
          # cleanup, so perform the replacement here.
          { name: ref.include?("//") ? ref.gsub(%r{/{2,}}, "/") : ref }
        end,
        request_context: default_request_context,
      }

      resp = process_response(client.references.resolve_references(request, @req_opts))
      resp.items.each_with_index.map do |item, i|
        # Response order matches input order
        [refnames[i], item.oid&.id]
      end
    end

    private

    delegate :client, to: SpokesAPI::Connection

    def process_response(resp)
      raise Error.from_twirp_error(resp.error) unless resp.error.nil?
      resp.data
    end

    def default_request_context(qos: nil, read_after_write: :default, reduce_cost_for_spokes_api: true)
      # If read_after_write is not explicitly set, derive the value from the
      # ActiveRecord connection.
      read_after_write = self.read_after_write? if read_after_write == :default

      qos ||= SpokesAPI.quality_of_service ? SpokesAPI.quality_of_service : :QUALITY_OF_SERVICE_NO_DELAY

      {
        quality_of_service: qos,
        user_id: GitHub.context[:actor_id] ? GitHub.context[:actor_id] : 0,
        real_ip: GitHub.context[:actor_ip] ? GitHub.context[:actor_ip] : "",
        push_state: GitHub.context[:spokesapi_push_state],
        read_after_write: read_after_write,
        reduce_cost_for_spokes_api: reduce_cost_for_spokes_api,
      }
    end

    def read_after_write?
      SpokesAPI.read_after_write != nil ? SpokesAPI.read_after_write : ApplicationRecord::Spokes.connected_to?(role: :writing)
    end
  end
end
