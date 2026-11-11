# typed: true
# frozen_string_literal: true

module SpokesAPI
  class Client
    RESOLVE_OBJECT_BATCH_SIZE = 1000
    FILE_MODE = 0100644 # Git regular non-executable file mode

    include Scientist

    # Public: returns a new Client for the given Repository.
    def self.for_repository(repository_id, network_id:, context:, timeout: nil)
      new(
        Types.new_repository(repository_id),
        headers: { "GitHub-Network-Id-Hint" => network_id.to_s },
        context: context,
        timeout: timeout
      )
    end

    # Public: returns a new Client for the given Gist.
    def self.for_gist(gist_id, gist_name:, context:, timeout: nil)
      new(
        Types.new_gist(gist_id),
        headers: { "GitHub-Gist-Name-Hint" => gist_name },
        context: context,
        timeout: timeout
      )
    end

    # Public: returns a new Client for the given Repository's wiki.
    def self.for_wiki(repository_id, network_id:, context:, timeout: nil)
      new(
        Types.new_wiki(repository_id),
        headers: { "GitHub-Network-Id-Hint" => network_id.to_s },
        context: context,
        timeout: timeout
      )
    end

    # Public: returns a new Client for the given Store.
    def self.for_store(store_id, context:, timeout: nil)
      new(
        Types.new_store(store_id),
        headers: {},
        context: context,
        timeout: timeout
      )
    end

    # Public: returns a new Client for multiple Repositories.
    def self.for_repositories(repository_ids, context:, timeout: nil)
      new(
        nil,
        repositories: repository_ids.map { |id| Types.new_repository(id) },
        context: context,
        timeout: timeout
      )
    end

    def initialize(repository, headers: nil, context:, repositories: nil, timeout: nil)
      request_headers = {}
      request_headers["Request-Timeout"] = SpokesAPI.timeout.to_s if SpokesAPI.timeout
      request_headers["Request-Timeout"] = timeout.to_s if timeout
      request_headers.update(headers) if headers

      @repository = repository
      @repositories = repositories
      @req_opts = { headers: request_headers }
      @context = context || SpokesAPI::Context.new
    end

    def clear_cache_key!
      @cache_key = nil
    end

    # The repository stored here is the one from Spokes API, that is
    # types.Repository.
    attr_reader :repository
    attr_reader :repositories
    attr_reader :context

    # Public: Fetch the repository metadata (including hash algorithm and ref
    # format) for the current repository.
    #
    # Returns a Hash with the following keys:
    #   :ref_format: either :files or :reftable
    #   :hash_algorithm: something implementing GitHub::HashAlgorithm::ClassMethods
    sig do
      returns(T::Hash[Symbol, T.any(GitHub::HashAlgorithm::ClassMethods, Symbol)])
    end
    def get_repository_metadata
      request_context = default_request_context(
        qos: if FeatureFlag.vexi.enabled?(:get_repository_metadata_no_delay, default: false)
               :QUALITY_OF_SERVICE_NO_DELAY
             else
               nil
             end
      )
      req = {
        request_context: request_context,
        repository: repository,
      }

      resp = process_response(client.repositories.get_repository_metadata(req, req_opts))
      {
        hash_algo: case resp.hash_algorithm
                   when :HASH_ALGORITHM_SHA1
                     GitHub::HashAlgorithm::SHA1
                   when :HASH_ALGORITHM_SHA256
                     GitHub::HashAlgorithm::SHA256
                   else
                     raise TypeError, "unknown hash algorithm"
                   end,
        ref_format: case resp.ref_format
                    when :REF_FORMAT_FILES
                      :files
                    when :REF_FORMAT_REFTABLE
                      :reftable
                    else
                      raise TypeError, "unknown ref format"
                    end,
      }
    end

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
        type = { type: SpokesAPI::Util.str_to_object_type(type) }
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
      resp = process_response(client.trees.read_tree_entry_oid(request, req_opts))
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
      return [] if GitRPC::Util.null_oid?(before) || GitRPC::Util.null_oid?(after)

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
        resp = process_response(client.trees.compare_trees(request, req_opts))
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
    # flatten_paths: (Bool, optional, default is false) Indicates that subtree entry paths should be
    #     the recursively-resolve path ending when the subtree no longer contains a single entry. No
    #     effect if 'recursive' is true.
    # pathspec: (GitHub::Spokes::Proto::Types::V1::Pathspec, optional) The pathspec to filter entries
    # cursor: (String, optional) The cursor to fetch
    #
    # Returns a list of GitHub::Spokes::Proto::Types::V1::TreeEntry and the cursor to fetch the next page.
    def list_tree_entries(tree_oid:, recursive: false, flatten_paths: false, pathspec: nil, cursor: nil)
      list_tree_entries_by({
          treeish_selector: { treeish: { oid: { id: tree_oid } } }
        },
        recursive: recursive,
        flatten_paths: flatten_paths,
        pathspec: pathspec,
        cursor: cursor)
    end

    # Public: Return the list of tree entries associated for a given selector.
    #
    # selector: (Hash, required) The selector to use to fetch the tree entries
    #     can be one of the following:
    #     treeish_selector: { treeish: <treeish> }
    #     treeish_and_path_selector: { treeish: <treeish> }, path: { name: } }
    # recursive: (Bool, optional, default is false) Indicates if the tree should be traversed recursively
    # flatten_paths: (Bool, optional, default is false) Indicates that subtree entry paths should be
    #     the recursively-resolve path ending when the subtree no longer contains a single entry. No
    #     effect if 'recursive' is true.
    # pathspec: (GitHub::Spokes::Proto::Types::V1::Pathspec, optional) The pathspec to filter entries
    # cursor: (String, optional) The cursor to fetch
    #
    # Returns a list of GitHub::Spokes::Proto::Types::V1::TreeEntry and the cursor to fetch the next page.
    def list_tree_entries_by(selector, recursive: false, flatten_paths: false, pathspec: nil, cursor: nil)
      req = {
        repository: repository,
        **selector,
        recursive:,
        flatten_paths:,
      }

      req[:pathspec] = pathspec unless pathspec.nil?
      req[:request_context] = default_request_context
      req[:cursor] = cursor unless cursor.nil?

      process_response(client.trees.list_trees(req, req_opts))
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
        resp = process_response(client.commits.list_contributors(request, req_opts))
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

      # Override qos to be "no-delay".
      #
      # ResolveObject is not computationally complex, and the callers are
      # spread throughout the app and probably assume that they can get a valid
      # response to this request. So we should prefer the small amount of extra
      # load so that we can get a result.
      req = {
        request_context: default_request_context(qos: :QUALITY_OF_SERVICE_NO_DELAY),
        repository: repository,
        object_name: {
          name: object_name.b,
        },
      }

      raw = client.objects.resolve_object(req, req_opts)

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
      process_response(client.objects.resolve_objects(req, req_opts))
    end

    # Public: returns the list of objects that have been requested.
    #
    # The result is a GitHub::Spokes::Proto::Objects::V1::ReadObjectsResponse that basically contains a list
    # of objects of type GitHub::Spokes::Proto::Objects::V1::Object
    #
    # Depending on the type of object, the object will have a different field set:
    # - GitHub::Spokes::Proto::Objects::V1::CommitObject
    # - GitHub::Spokes::Proto::Objects::V1::TreeObject
    # - GitHub::Spokes::Proto::Objects::V1::BlobObject
    # - GitHub::Spokes::Proto::Objects::V1::TagObject
    # - GitHub::Spokes::Proto::Objects::V1::ErrorObject
    #
    # oids:
    #  (String, required) A list of OIDs to resolve
    # types:
    #  (String, required) The types of every object in the list
    sig do
      params(
        oids: T::Array[String],
        types: T.nilable(T::Array[String]),
        qos: T.nilable(Symbol)
      ).returns(GitHub::Spokes::Proto::Objects::V1::ReadObjectsResponse)
    end
    def read_objects(oids:, types:, qos: nil)
      raise ArgumentError, "oids and types must have the same length" if types != nil && oids.length != types.length

      selectors = if types
        oids.zip(types).map do |oid, type|
          GitRPC::Util.ensure_valid_full_oid(oid)
          {
            by_id: { id: oid },
            object_type: { type: SpokesAPI::Util.str_to_object_type(type) }
          }
        end
      else
        oids.map do |oid|
          GitRPC::Util.ensure_valid_full_oid(oid)
          {
            by_id: { id: oid },
          }
        end
      end

      SpokesAPI.with_quality_of_service(qos) { read_objects_by(selectors) }
    end

    # Public: Return a list of objects for each selector.
    #
    # selectors:
    #  (Array<Hash>, required) A list of selectors to read.
    #   Each selector is a hash with one of the following keys:
    #    by_id { id: }: The OID to read
    #    by_name: { name: }: The ref to read
    #    by_treeish_and_path: { treeish: { reference: { name: }, oid: { id: } }, path: { name: } }: The treeish and path to read
    def read_objects_by(selectors)
      req = {
        repository: repository,
        request_context: default_request_context,
        selectors: selectors
      }

      process_response(client.objects.read_objects(req, req_opts))
    end

    # Public: Return a list of resolved objects for each selector
    #
    # selectors:
    #  (Array<Hash>, required) A list of selectors to resolve.
    #   Each selector is a hash with one of the following keys:
    #    by_id { id: }: The OID to resolve
    #    by_name: { name: }: The ref to resolve
    #    by_treeish_and_path: { treeish: { reference: { name: }, oid: { id: } }, path: { name: } }: The treeish and path to resolve
    #   An object_type key may be provided to validate the object type: {object_type: {type: }}
    # read_uncommitted: (Bool, optional, default is false) Should only be set when data is read during _commit_refs
    def resolve_objects_by(selectors, read_uncommitted: false)
      req = {
        request_context: default_request_context,
        repository: repository,
        selectors: selectors,
      }

      req[:request_context][:read_uncommitted] = read_uncommitted
      process_response(client.objects.resolve_objects(req, req_opts))
    end

    # Public: Create multiple objects from raw content.
    #
    # contents:
    #  (String, required) A list of strings containing the raw content of the object to create
    # types:
    #  (String, required) A list of strings containing the type of every object to create
    #
    # Returns a GitHub::Spokes::Proto::Objects::V1::CreateObjectsResponse containing:
    #   - oids: Array of created object IDs
    #   - transaction_context: Updated transaction state
    def create_objects(contents:, types:)
      raise ArgumentError, "at least one object must be provided" if contents.nil? || contents.empty?
      raise ArgumentError, "types must be provided" if types.nil? || types.empty?
      raise ArgumentError, "contents and types must have the same length" if contents.length != types.length

      creatable_objects = contents.zip(types).map do |content, type|
        {
        content: content&.b,
        type: { type: SpokesAPI::Util.str_to_object_type(type) }
        }
      end

      req = {
        repository: repository,
        request_context: default_request_context,
        objects: creatable_objects
      }

      process_response(client.objects.create_objects(req, req_opts))
    end

    # Public: Create and optionally sign a commit.
    #
    # Returns the OID of the newly created commit.
    sig do
      params(
        tree_oid: String,
        author: T::Hash[Symbol, T.untyped],
        committer: T::Hash[Symbol, T.untyped],
        sign: T::Boolean,
        cleanup_mode: Symbol,
        message: T.nilable(String),
        parents: T.nilable(T::Array[String]),
      ).returns(GitHub::Spokes::Proto::Commits::V1::CreateCommitResponse)
    end
    def create_commit(tree_oid:, author:, committer:, sign: false, cleanup_mode: :CLEANUP_MODE_WHITESPACE, message: nil, parents: nil)
      req = {
        repository: repository,
        request_context: default_request_context,
        tree: { id: tree_oid },
        author: map_attribution(author),
        committer: map_attribution(committer),
        sign: sign,
        cleanup_mode: cleanup_mode,
        message: message,
      }

      if parents
        req[:parents_selector] = { parents: parents.map { |oid| { id: oid } } }
      else
        req[:no_parents] = {}
      end

      process_response(client.commits.create_commit(req, req_opts))
    end

    # Public: Create a merge commit
    #
    # This method orchestrates the creation of a merge commit by:
    # 1. Writing conflict resolutions as blobs (if any)
    # 2. Creating a merge tree
    # 3. Creating and optionally signing a merge commit
    #
    # This method must be invoked inside a transaction to ensure atomicity of the merge commit creation.
    #
    # base_oid:
    #   (String, required) the OID of the treeish used for the left side of the merge
    # head_oid:
    #   (String, required) the OID of the treeish used for the right side of the merge
    # author:
    #   (Hash, required) the author of the commit, e.g. { name: "Monalisa Octocat", email: "monalisa@github.com", time: "2025-01-08T21:00:00Z" }
    # base_repo_id:
    #   (string, optional) the repository ID containing base_oid
    # head_repo_id:
    #   (string, optional) the repository ID containing head_oid
    # committer:
    #   (Hash, optional) the committer of the commit, e.g. { name: "Monalisa Octocat", email: "monalisa@github.com", time: "2025-01-08T21:00:00Z" }
    #   Uses author if not provided.
    # message:
    #   (String, optional) the message of the commit
    # sign:
    #   (Boolean, optional) whether to sign the commit
    # include_conflict_details:
    #   (Boolean, optional) whether to report conflict details during a merge conflict
    # resolutions:
    #   (Hash, optional) a map of file paths to their resolved content, e.g. { "path/to/file.txt" => "resolved content" }
    #
    # Returns a Returns a SpokesAPI::Types::CommitResult containing:
    #   status: the state of the commit operation (:STATUS_SUCCESS, :STATUS_MERGE_CONFLICT, or :STATUS_ALREADY_MERGED)
    #   oid: the OID of the newly created merge commit when status is :STATUS_SUCCESS
    #   conflicts: the map of merge conflicts when status is :STATUS_MERGE_CONFLICT and include_conflict_details is true
    sig do
      params(
        base_oid: String,
        head_oid: String,
        author: T::Hash[Symbol, T.untyped],
        base_repo_id: T.nilable(Integer),
        head_repo_id: T.nilable(Integer),
        committer: T.nilable(T::Hash[Symbol, T.untyped]),
        message: T.nilable(String),
        sign: T::Boolean,
        include_conflict_details: T::Boolean,
        resolutions: T.nilable(T::Hash[String, String])
      ).returns(Types::CommitResult)
    end
    def create_merge_commit(
      base_oid:,
      head_oid:,
      author:,
      base_repo_id: nil,
      head_repo_id: nil,
      committer: nil,
      message: nil,
      sign: false,
      include_conflict_details: false,
      resolutions: nil
    )
      GitRPC::Util.ensure_valid_full_oid(base_oid)
      GitRPC::Util.ensure_valid_full_oid(head_oid)

      # Create resolution blobs
      resolution_blobs = nil
      if resolutions&.any?
        paths = resolutions.keys
        contents = resolutions.values
        types = Array.new(contents.size, "blob")

        objects = create_objects(contents:, types:)
        resolution_blobs = paths.zip(objects.oids).map do |path, oid|
          {
            mode: { mode: FILE_MODE },
            oid:,
            path: { name: path }
          }
        end
      end

      # Create merge tree
      merge_tree = merge_trees(
        base_oid:,
        base_repo_id:,
        head_oid:,
        head_repo_id:,
        include_conflict_details:,
        resolutions: resolution_blobs
      )

      if merge_tree.merge_status == :STATUS_SUCCESS
        merge_tree_oid = T.must(merge_tree.oid).id
      else
        return Types::CommitResult.new(status: merge_tree.merge_status, conflicts: merge_tree.conflicts.to_h)
      end

      committer ||= author
      parents = [base_oid, head_oid]

      # Create merge commit
      merge_commit = create_commit(tree_oid: merge_tree_oid, author:, committer:, message:, sign:, parents:)

      Types::CommitResult.new(status: :STATUS_SUCCESS, oid: T.must(merge_commit.oid).id)
    end

    # Public: Reapply commit history on top of another commit
    #
    # head_oid:
    #   (String, required) The inclusive end of the commit range to rebase.
    # base_oid:
    #   (String, required) The exclusive start of the commit range to rebase.
    # committer:
    #   (Hash, required) The committer associated with every commit in the rebase.
    #     e.g. { name: "Monalisa Octocat", email: "monalisa@github.com", time: "2025-01-08T21:00:00Z" }
    # onto_oid:
    #   (String, optional) The commit to replay the commit range on top of. If unspecified, base_oid will be used.
    # mergeability_only:
    #   (Boolean, optional) If true, simulate a rebase without persisting objects to the repository.
    # committer_only:
    #   (Boolean, optional) If true, update only committer information when replaying commits.
    #
    # Returns a GitHub::Spokes::Proto::Merges::V1::RebaseResponse where:
    #   - :STATUS_SUCCESS returns the last rebased commit
    #   - :STATUS_ALREADY_MERGED returns the input head_oid (to match GitRPC behavior)
    #   - :STATUS_MERGE_CONFLICT returns nothing
    sig do
      params(
        head_oid: String,
        base_oid: String,
        committer: T::Hash[Symbol, T.untyped],
        onto_oid: T.nilable(String),
        mergeability_only: T::Boolean,
        committer_only: T::Boolean,
      ).returns(GitHub::Spokes::Proto::Merges::V1::RebaseResponse)
    end
    def rebase(
      head_oid:,
      base_oid:,
      committer:,
      onto_oid: nil,
      mergeability_only: false,
      committer_only: false
    )
      GitRPC::Util.ensure_valid_full_oid(head_oid)
      GitRPC::Util.ensure_valid_full_oid(base_oid)
      GitRPC::Util.ensure_valid_full_oid(onto_oid) unless onto_oid.nil?

      req = {
        request_context: default_request_context,
        repository: repository,
        head_oid: { id: head_oid },
        base_oid: { id: base_oid },
        committer: map_attribution(committer),
        diff_algorithm: :DIFF_ALGORITHM_DEFAULT,
        options: {
          mergeability_only: mergeability_only,
          committer_only: committer_only,
        },
      }
      req[:onto_oid] = { id: onto_oid } unless onto_oid.nil?

      process_response(client.merges.rebase(req, req_opts))
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

      process_response(client.blobs.list_reachable_blobs(req, req_opts))
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

      process_response(client.blobs.list_reachable_blobs(req, req_opts))
    end

    # Public: Count number of commits based on a list of OIDs, and optionally filters.
    sig do
      params(
        oids: T::Array[String],
        limit: T.nilable(Integer),
        filters: T.nilable(GitHub::Spokes::Proto::Commits::V1::RevListFilters),
        read_uncommitted: T::Boolean
      ).returns(Integer)
    end
    def count_commits_for_ids(oids:, limit: 0, filters: nil, read_uncommitted: false)
      req = {
        request_context: default_request_context,
        repository: repository,
        object_id_selector: {
          oids: oids.map { |oid| { id: oid } }
        }
      }
      req[:limit] = limit if limit
      req[:filters] = filters if filters

      process_response(client.commits.count_commits(req, req_opts)).count
    end

    # Public: Count the number of commits reachable only from the given ref
    sig { params(ref: String, exclude_oids: T::Array[String], limit: Integer).returns(Integer) }
    def count_distinct_commits(ref:, exclude_oids: [], limit: 0)
      # split ref@{oid} formatted ref syntax into ref and oid
      oid = nil
      match = ref.match(/\A(?<ref>.+)@\{(?<oid>[0-9A-Fa-f]+)\}\Z/)
      if match
        ref = match[:ref]
        oid = match[:oid]
      end

      req = {
        request_context: default_request_context,
        repository: repository,
        distinct_commits_selector: {
          reference: { name: T.must(ref).b },
          exclude_oids: exclude_oids.map { |oid| { id: oid } }
        }
      }

      req[:distinct_commits_selector][:oid] = { id: oid } unless oid.nil?

      req[:limit] = limit if limit > 0

      process_response(client.commits.count_commits(req, req_opts)).count
    end

    # Public: Return a `git describe`-style name for the given commitish.
    #
    # Equivalent to `git describe --long --tags --abbrev=<abbrev_length> --always -- <commitish>`.
    #
    # commitish:
    #   (String, required) Any revision string (ref name, oid, "HEAD", "v1.2^",
    #     etc.). Free-form input is sent as a `Revision` so leading dashes are preserved.
    # abbrev_length:
    #   (Integer, optional, default 40) Length of the abbreviated oid suffix.
    #
    # Translates Spokes API errors into the equivalent GitRPC errors so that
    # callers migrating from the corresponding GitRPC describe endpoint do not
    # need to update their rescue clauses:
    #   * SpokesAPI::NotFound, SpokesAPI::InvalidArgument -> GitRPC::ObjectMissing
    #   * SpokesAPI::TwirpServerError                     -> GitRPC::ObjectMissing
    #   * SpokesAPI::TimedOut                             -> GitRPC::Timeout
    #
    # The TwirpServerError mapping mirrors the GitRPC backend's tolerance for
    # cases where `git describe` fails (e.g. a tree-ish input): GitRPC treated
    # those as ObjectMissing, callers already handle that gracefully, and the
    # Spokes server surfaces them as a generic "git-describe: exit status N"
    # server error.
    #
    # Returns an ASCII-8BIT String result
    # Matches what GitRPC `describe` endpoint returns
    sig { params(commitish: String, abbrev_length: Integer).returns(String) }
    def describe(commitish:, abbrev_length: 40)
      req = {
        request_context: default_request_context,
        repository: repository,
        abbrev_length: abbrev_length,
        commitish_selector: {
          commitish: { revision: { name: commitish.b } },
        },
      }

      resp = process_response(client.commits.describe(req, req_opts))
      resp.commit_name.to_s.b
    rescue SpokesAPI::NotFound, SpokesAPI::InvalidArgument, SpokesAPI::TwirpServerError
      raise GitRPC::ObjectMissing
    rescue SpokesAPI::TimedOut => e
      raise GitRPC::Timeout, e.message
    end

    # Public: Return the list of commits based on a list of OIDs.
    #
    # oids (Array, required):
    # cursor: (String, required) The cursor to fetch
    # read_uncommitted: (Bool, optional, default is false) Should only be set when data is read during _commit_refs
    #
    # Returns a list of reachable blobs and the cursor to fetch the next page.
    sig { params(oids: T::Array[String], cursor: T.nilable(String), read_uncommitted: T::Boolean).returns(GitHub::Spokes::Proto::Commits::V1::ListCommitsResponse) }
    def list_commits_for_ids(oids:, cursor: nil, read_uncommitted: false)
      req = {
        request_context: default_request_context,
        repository: repository,
        object_id_selector: {
          oids: oids.map { |oid| { id: oid } }
        }
      }

      req[:request_context][:read_uncommitted] = read_uncommitted
      req[:cursor] = cursor unless cursor.nil?

      process_response(client.commits.list_commits(req, req_opts))
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

      process_response(client.commits.list_commits(req, req_opts))
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

      process_response(client.commits.list_commits(req, req_opts))
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

      process_response(client.commits.list_commits(req, req_opts))
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

      process_response(client.blobs.list_pushed_blobs(req, req_opts))
    end

    # Public: Return the list of commits in quarantine based on a push_state.
    #
    # push_state (String, required): The push state to use to look up the quarantine
    # cursor: (GitHub::Spokes::Proto::Types::V1::Cursor, required) The cursor to fetch
    #
    # Returns a list of commits and the cursor to fetch the next page.
    sig { params(push_state: String, cursor: T.nilable(GitHub::Spokes::Proto::Types::V1::Cursor)).returns(GitHub::Spokes::Proto::Commits::V1::ListCommitsResponse) }
    def list_quarantine_commits(push_state:, cursor: nil)
      req = {
        request_context: default_request_context.merge(transaction_state: push_state),
        repository: repository,
        quarantine_commits_selector: {},
      }
      req[:cursor] = cursor unless cursor.nil?

      process_response(client.commits.list_commits(req, req_opts))
    end

    # Public: List the commits reachable only from the given ref
    sig do
      params(
        ref: String,
        exclude_oids: T::Array[String],
        cursor: T.nilable(String)
      ).returns(GitHub::Spokes::Proto::Commits::V1::ListCommitsResponse)
    end
    def list_distinct_commits(ref:, exclude_oids: [], cursor: nil)
      # split ref@{oid} formatted ref syntax into ref and oid
      oid = nil
      match = ref.match(/\A(?<ref>.+)@\{(?<oid>[0-9A-Fa-f]+)\}\Z/)
      if match
        ref = match[:ref]
        oid = match[:oid]
      end

      req = {
        request_context: default_request_context,
        repository: repository,
        distinct_commits_selector: {
          reference: { name: T.must(ref).b },
          exclude_oids: exclude_oids.map { |oid| { id: oid } }
        },
      }
      req[:cursor] = cursor unless cursor.nil?

      req[:distinct_commits_selector][:oid] = { id: oid } unless oid.nil?

      process_response(client.commits.list_commits(req, req_opts))
    end

    sig do
      params(
        include_globs: T::Array[String],
        exclude_globs: T::Array[String],
        ignore_case: T::Boolean,
        cursor: T.nilable(GitHub::Spokes::Proto::Types::V1::Cursor),
        points_at: T::Array[String],
        contains: T::Array[String]
      )
      .returns(T.nilable(GitHub::Spokes::Proto::References::V1::ListReferencesWithDetailsResponse))
    end
    def list_references_with_details(include_globs: [], exclude_globs: [], ignore_case: true, cursor: nil, points_at: [], contains: [])
      request = {
        repository: repository,
        request_context: default_request_context,
        ref_list_options: {
          points_at: points_at.map { |oid| { id: oid } },
          contains: contains.map { |oid| { id: oid } }
        }
      }

      if include_globs.present? || exclude_globs.present?
        request[:ref_glob_selector] = {
          include: include_globs.map { |glob| { glob: glob } },
          exclude: exclude_globs.map { |glob| { glob: glob } },
          ignore_case:
        }
      else
        request[:universal_selector] = {}
      end

      request[:cursor] = cursor unless cursor.nil?

      process_response(client.references.list_references_with_details(request, req_opts))
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

      resp = process_response(client.references.get_default_branch(request, req_opts))
      resp.reference.name.dup.force_encoding("UTF-8")
    end

    # Public: Update the HEAD reference for a repository.
    def update_default_branch(name, priority: :PRIORITY_HIGH)
      request = {
        request_context: default_request_context(qos: :QUALITY_OF_SERVICE_NO_DELAY),
        repository: repository,
        priority: GitHub::Spokes::Proto::Types::V1::UpdateReferencesPriority.new(priority: priority),
        new_value: { name: name }
      }

      process_response(client.references.update_default_branch(request, req_opts))
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

      process_response(client.gitauth.list_routes(request, req_opts))
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

      resp = process_response(client.gitauth.set_up_push_state(request, req_opts))
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
        request_context: default_request_context.merge(transaction_state: push_state),
        preserve_quarantine: preserve_quarantine
      }
      # A failure here could mean that there's a split decision or that the
      # push only has deletions. In either case, a later phase of the push will
      # fail if a failure here is significant.
      resp = client.gitauth.commit_quarantine(request, req_opts)
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
      request_context[:transaction_state] = push_state unless push_state.nil?

      request = { repository: repository, request_context: request_context }
      request[:quarantine_id] = quarantine_id unless quarantine_id.nil?

      # Note: This is a best-effort RPC, so don't call process_response which
      # would raise errors to the caller. This does mean that errors are
      # probably ignored, but we can monitor them in spokesd and other git
      # systems, so we don't need to make noise here. would raise errors to the
      # caller.
      client.gitauth.remove_quarantine(request, req_opts)
    end

    # Public: Get the new OIDs for a quarantine. Either quarantine_id or push_state must be provided.
    #
    # push_state:
    #   (Binary string) the push state.
    # cursor: (GitHub::Spokes::Proto::Types::V1::Cursor) The cursor to continue from
    #
    # Returns a GitHub::Spokes::Proto::Gitauth::V1::GetNewOidsInPushResponse
    sig do
      params(
        push_state: String,
        cursor: T.nilable(GitHub::Spokes::Proto::Types::V1::Cursor),
      ).returns(GitHub::Spokes::Proto::Gitauth::V1::GetNewOidsInPushResponse)
    end
    def get_new_oids_in_push(push_state:, cursor: nil)
      request = {
        repository: repository,
        request_context: default_request_context.merge(transaction_state: push_state),
      }

      request[:cursor] = cursor unless cursor.nil?

      process_response(client.gitauth.get_new_oids_in_push(request, req_opts))
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

      resp = process_response(client.commits.ahead_behind(request, req_opts))

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

      resp = process_response(client.commits.ahead_behind_contains(request, req_opts))

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
        resp = process_response(client.legacygitrpc.get_cache_key(request, req_opts))
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

      resp = process_response(client.legacygitrpc.get_cache_keys(request, req_opts))
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

      resp = process_response(client.commits.blame_tree(request, req_opts))

      resp.pairs.map { |pair| [pair.path.name.b, pair.oid.id] }.to_h
    end

    # Public: Returns a list of attributes for the specified paths in a treeish
    #
    # tree_oid:
    #   (String, required) the OID of a treeish
    # paths:
    #   (Array<String>, required) the list of paths in a treeish
    # keys:
    #   (Array<String>, optional, default is nil) the list of attribute keys to
    #     read. If nil, all attributes will be read.
    #
    # Returns a Hash containing a path in a treeish and its attributes.
    sig do
      params(
        tree_oid: String,
        paths: T::Array[String],
        keys: T.nilable(T::Array[String])
      ).returns(T::Hash[String, T::Hash[String, T.untyped]])
    end
    def read_attributes(tree_oid:, paths:, keys: nil)
      GitRPC::Util.ensure_valid_full_oid(tree_oid)
      return {} if paths.empty?

      request = {
        repository: repository,
        request_context: default_request_context,
        treeish_selector: {
          treeish: { oid: { id: tree_oid } }
        },
        # Request requires binary string encoding, force encoding to avoid
        # Encoding::UndefinedConversionError.
        paths: paths.map { |path| { name: path.b } },
      }
      if keys
        request[:key_selector] = { keys: keys }
      else
        request[:universal_selector] = {}
      end

      resp = process_response(client.attributes.read_attributes(request, req_opts))

      resp.attribute_items.each_with_object({}) do |item, result|
        path = item.path.name.dup.force_encoding("UTF-8")
        result[path] = {}

        item.attributes.each do |attribute|
          key = attribute.key

          value = case attribute.value
          when :byte_value # attribute is assigned a value
            attribute.byte_value
          when :bool_value # attribute is set or unset
            attribute.bool_value
          else # attribute is unspecified
            nil
          end

          result[path][key] = value
        end
      end
    end

    def read_diff_summary(commit1_oid:, commit2_oid:, base_commit_oid: nil, commit1_repo: nil, commit2_repo: nil, base_commit_repo: nil, with_stats: true, ignore_whitespace: false)
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

      resp = process_response(client.diffs.read_diff_summary(request, req_opts))

      [resp, with_stats]
    end

    # Read the raw diff between two commits.
    # commit1 can be either:
    # - parent of commit 2 (commit1_parent: true)
    # - root of repository (commit1_root: true)
    # - a commit OID (commit1_oid:), and optionally, a repository ID of which repo this commit belongs to (commit1_repo_id:)
    sig do
      params(
        mode: Symbol, # :DIFF_MODE_DIFF or :DIFF_MODE_PATCH
        commit2_oid: String,
        commit1_oid: T.nilable(String),
        commit1_parent: T::Boolean,
        commit1_root: T::Boolean,
        commit1_repo_id: T.nilable(Integer),
        commit2_repo_id: T.nilable(Integer),
        full_index: T::Boolean,
        timeout: T.nilable(T.any(Integer, Float))
      ).returns(String)
    end
    def read_raw_diff(
      mode:, commit2_oid:, commit1_oid: nil,
      commit1_parent: false, commit1_root: false,
      commit1_repo_id: nil, commit2_repo_id: nil,
      full_index: false, timeout: nil
    )
      request = {
        repository: repository,
        request_context: default_request_context,
        full_index: full_index,
        mode: mode,
        diff_algorithm: :DIFF_ALGORITHM_DEFAULT,
      }

      if commit1_root
        request[:root_selector1] = {}
      elsif commit1_parent
        request[:parent_selector1] = {}
      elsif commit1_repo_id && commit1_oid
        request[:repo_object_id1] = { base_repository: Types.new_repository(commit1_repo_id), oid: { id: commit1_oid } }
      elsif commit1_oid
        request[:object_id1] = { id: commit1_oid }
      else
        raise TypeError, "commit 1 selector must be provided"
      end

      if commit2_repo_id && commit2_oid
        request[:repo_object_id2] = { base_repository: Types.new_repository(commit2_repo_id), oid: { id: commit2_oid } }
      elsif commit2_oid
        request[:object_id2] = { id: commit2_oid }
      end

      response = SpokesAPI::Connection.connection_for_streaming.post("/streaming/v1/diffs/raw") do |req|
        req.body = GitHub::Spokes::Proto::Streaming::V1::ReadRawDiffRequest.new(request).to_proto
        req.headers["Content-Type"] = "application/protobuf"
        req.headers["Request-Timeout"] = timeout.to_s if timeout
      end

      # The streaming api does not use twirp, it streams raw content which twirp does not support.
      # To make the response more easily consumable, especially for errors, we wrap the response in a Twirp::ClientResp.
      twirp_response = if response.success?
        Twirp::ClientResp.new(data: response.body)
      else

        # The streaming api returns errors either as a JSON object with twirp error fields or a string error message.
        error_msg = begin
          JSON.parse(response.body)["msg"]
        rescue JSON::ParserError
          response.body
        end

        Twirp::ClientResp.new(error: Twirp::Error.new(Twirp::ERROR_CODES_TO_HTTP_STATUS.key(response.status), error_msg))
      end

      process_response(twirp_response)
    end

    def self.resolve_references_ref_limit
      # TODO: once we've upgraded to google-protobuf v3.18 or later, extract
      # this from the 'limit' field option of 'ResolveReferencesRequest.references'.
      10000
    end

    sig do
      params(refnames: T::Array[String])
      .returns(T::Array[[String, T.nilable(String)]])
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

      resp = process_response(client.references.resolve_references(request, req_opts))
      resp.items.each_with_index.map do |item, i|
        # Response order matches input order
        [refnames[i], item.oid&.id]
      end
    end

    # Returns a blob response with the first 1 mb of blob content for the given selector.
    # The selector can be one of the following:
    #    by_id: { id: } The OID of the blob
    #    by_ref_path: { reference: { name: } path: { name: }} The ref and path of the blob
    #    by_object_id_path: { oid: { id: }, path: { name: }} The OID of a treeish and the path of the blob
    sig { params(selector: T::Hash[Symbol, T.untyped]).returns(GitHub::Spokes::Proto::Blobs::V1::GetBlobContentsResponse) }
    def get_blob_contents(selector)
      request = {
        repository: repository,
        request_context: default_request_context,
        **selector,
      }

      process_response(client.blobs.get_blob_contents(request, req_opts))
    end

    # Returns the full raw blob contents for given oid.
    sig { params(oid: String).returns(String) }
    def get_blob_contents_streaming(oid)
      response = SpokesAPI::Connection.connection_for_streaming.get("/streaming/v1/repositories/#{repository.id}/blobs/#{oid}")

      # The streaming api does not use twirp, it streams raw content which twirp does not support.
      # To make the response more easily consumable, especially for errors, we wrap the response in a Twirp::ClientResp.
      twirp_response = if response.success?
        Twirp::ClientResp.new(data: response.body)
      else

        # The streaming api returns errors either as a JSON object with twirp error fields or a string error message.
        error_msg = begin
          JSON.parse(response.body)["msg"]
        rescue JSON::ParserError
          response.body
        end

        Twirp::ClientResp.new(error: Twirp::Error.new(Twirp::ERROR_CODES_TO_HTTP_STATUS.key(response.status), error_msg))
      end

      process_response(twirp_response)
    end

    # Return the list of submodules for a given treeish and paths.
    #
    # treeish:
    #   A treeish selector, e.g. { oid: { id: "abc123" } }
    # paths:
    #   An array of string paths to submodules.
    def read_submodules(treeish:, paths:)
      request = {
        repository: repository,
        treeish_selector: {
          treeish: treeish,
        },
        paths: paths.map { |path| { name: path } },
      }

      request[:request_context] = default_request_context

      process_response(client.submodules.read_submodules(request, req_opts))
    end

    sig do
      params(
        include_prefixes: T::Array[String],
        exclude_prefixes: T::Array[String],
        cursor: T.nilable(GitHub::Spokes::Proto::Types::V1::Cursor),
        points_at: T::Array[String],
        contains: T::Array[String]
      )
      .returns(T.nilable(GitHub::Spokes::Proto::References::V1::ListReferencesResponse))
    end
    def list_references(include_prefixes: [], exclude_prefixes: [], cursor: nil, points_at: [], contains: [])
      request = {
        repository:,
        request_context: default_request_context,
        ref_list_options: {
          points_at: points_at.map { |oid| { id: oid } },
          contains: contains.map { |oid| { id: oid } }
        }
      }

      if include_prefixes.present? || exclude_prefixes.present?
        request[:prefix_selector] = {
          include: include_prefixes.map { |prefix| { prefix: } },
          exclude: exclude_prefixes.map { |prefix| { prefix: } }
        }
      else
        request[:universal_selector] = {}
      end

      request[:cursor] = cursor unless cursor.nil?

      process_response(client.references.list_references(request, req_opts))
    end

    def references_exist
      request = {
        repository: repository,
        request_context: default_request_context,
      }

      process_response(client.references.references_exist(request, req_opts))
    end

    def perform_backup(parent_repository_id)
      request = {
        repository: repository,
        request_context: default_request_context(qos: :QUALITY_OF_SERVICE_NO_DELAY),
      }

      request[:parent_repository] = Types.new_repository(parent_repository_id) unless parent_repository_id.nil?

      process_response(client.backups.perform_backup(request, @req_opts))
    end

    sig do
      params(
        nwo: String,
        default_branch: T.nilable(String),
        initial_commit: T.nilable(Hash),
        hash_algorithm: T.nilable(Symbol), # :sha1 or :sha256
        ref_format: T.nilable(Symbol)
      ).returns(GitHub::Spokes::Proto::Repositories::V1::CreateRepositoryResponse)
    end
    def create_repository(nwo:, default_branch: nil, initial_commit: nil, hash_algorithm: nil, ref_format: nil)
      request = {
        request_context: default_request_context,
        repository: repository,
        nwo: nwo.b,
      }
      if default_branch.present?
        if !default_branch.start_with?("refs/heads/")
          default_branch = "refs/heads/#{default_branch}"
        end
        request[:default_branch] = { name: default_branch.b }
      end

      request[:initial_commit] = initial_commit if initial_commit
      request[:hash_algorithm] = GitHub::HashAlgorithm.from_sym(hash_algorithm)&.spokes_enum if hash_algorithm
      request[:ref_format] = ref_format if ref_format

      process_response(client.repositories.create_repository(request, req_opts))
    end

    sig do
      params(
        fork_id: Integer, branch_mode: Symbol, nwo: String, token: T.nilable(GitHub::Spokes::Proto::Types::V1::Token), wait_milliseconds: Integer
      ).returns(GitHub::Spokes::Proto::Repositories::V1::CreateForkResponse)
    end
    def create_fork(fork_id:, branch_mode:, nwo:, token: nil, wait_milliseconds: 5000)
      request = {
        request_context: default_request_context,
        parent: {
          repository: repository,
        },
        fork: {
          id: fork_id,
          nwo: nwo.b,
        },
        branch_mode: branch_mode,
        token: token,
        wait_milliseconds: wait_milliseconds,
      }

      process_response(client.repositories.create_fork(request, req_opts))
    end

    def create_tag(name:, target:, message:, tagger:)
      request = {
        repository: repository,
        request_context: default_request_context,
        name: name&.b,
        target: { id: target },
        message: message&.b,
        tagger: map_attribution(tagger)
      }

      resp = process_response(client.tags.create_tag(request, req_opts))
      resp.oid.id
    end

    # Public: Determines the line number on the target oid for the given source oid and line numbers.
    #
    # Line numbers and valid paths required.
    sig do
      params(
        source_oid: String,
        target_oid: String,
        source_items: T::Array[{
          source_path: { name: String },
          line_numbers: T::Array[Integer]
        }],
      ).returns(T.any(String, T::Array[{
        source_path: { name: String },
        target_path: { name: String },
        state: { code: Symbol, description: String },
        line_numbers: T::Array[{
          source_line_number: Integer,
          target_line_number: Integer
        }]
      }]))
    end
    def get_diff_positions(source_oid:, target_oid:, source_items:)
      # GetDiffPositions supports only resolving the new file path when given 0 as the only line number. This allows an
      # empty collection to be passed in as arguments but be API complaint.
      request = {
        source_items: source_items.map { _1.merge(line_numbers: _1[:line_numbers].uniq.presence || [0]) },
        source_oid: { base_repository: repository, oid: { id: source_oid } },
        target_oid: { base_repository: repository, oid: { id: target_oid } },
        request_context: default_request_context,
        repository:,
      }

      resp = process_response(client.diffs.get_diff_positions(request, req_opts))

      resp.error.presence || resp.target_items.map do |payload|
        payload.to_h.merge(state: Types::DiffPositionState.safe_deserialize(payload.state.code))
      end
    end

    # Public: Checks whether a diff patch can be cleanly applied to a commit.
    #
    # commit_oid:
    #   (String, required) The commit SHA to check the patch against.
    # diff_patch:
    #   (String, required) The unified diff patch content to check for appliability.
    #
    # Returns a Hash with:
    #   :result - SpokesAPI::Types::DiffAppliableResult enum value
    #   :resolved_diff_patch - String (UTF-8) containing the resolved patch, or nil
    sig do
      params(
        commit_oid: String,
        diff_patch: String,
      ).returns({ result: SpokesAPI::Types::DiffAppliableResult, resolved_diff_patch: T.nilable(String) })
    end
    def get_diff_appliable(commit_oid:, diff_patch:)
      request = {
        repository:,
        request_context: default_request_context,
        commit_oid: { id: commit_oid },
        diff_patch: diff_patch.b,
      }

      resp = T.cast(
        process_response(client.diffs.get_diff_appliable(request, req_opts)),
        GitHub::Spokes::Proto::Diffs::V2::GetDiffAppliableResponse
      )

      result = Types::DiffAppliableResult.safe_deserialize(resp.result)
      resolved_diff_patch = resp.resolved_diff_patch.presence&.dup&.force_encoding("UTF-8")
      { result:, resolved_diff_patch: }
    end

    # Public: Computes the diffs between pairs of files.
    #
    # diff_deltas:
    #   (Array<Hash>, required) List of file deltas to compute diffs for.
    #   Each delta is a hash with:
    #     old_tree_node: (Hash, optional) The old tree entry { object: { oid: { id: }, type: :TYPE_BLOB }, path: { name: }, mode: { mode: } }
    #     new_tree_node: (Hash, optional) The new tree entry { object: { oid: { id: }, type: :TYPE_BLOB }, path: { name: }, mode: { mode: } }
    #     diff_status: (Symbol, optional) The diff status (e.g., :DIFF_STATUS_ADDITION, :DIFF_STATUS_MODIFICATION, :DIFF_STATUS_DELETION)
    #     similarity: (Integer, optional) Similarity score for renames
    # resolved_base_selector:
    #   (Hash, optional) The selector that triggers internal resolution of a merge base.
    #   Can contain:
    #     object_id1: { id: } or repo_object_id1: { base_repository: ..., oid: { id: } } or root_selector1: {}
    #     object_id2: { id: } or repo_object_id2: { base_repository: ..., oid: { id: } }
    #     base_object_id: { id: } or repo_base_object_id: { base_repository: ..., oid: { id: } } or none_base: {}
    # options:
    #   (Hash, optional) Options to customize the diff output:
    #     max_diff_size: (Integer, optional) Maximum size in bytes for a single diff output
    #     max_total_size: (Integer, optional) Maximum total size in bytes for all diff outputs combined
    #     max_diff_lines: (Integer, optional) Maximum number of lines for a single diff output
    #     max_total_lines: (Integer, optional) Maximum total number of lines for all diff outputs combined
    #     ignore_whitespace: (Boolean, optional) Whether to ignore whitespace
    # cursor:
    #   (String or Hash, optional) The cursor for pagination
    #
    # Returns a GitHub::Spokes::Proto::Diffs::V2::ReadDiffPairsResponse with:
    #   items: Array of DiffPairResult, each containing diff_content (bytes) and truncated (bool)
    #   next_cursor: Cursor for the next page, if any
    sig do
      params(
        diff_deltas: T::Array[T::Hash[Symbol, T.untyped]],
        resolved_base_selector: T.nilable(T::Hash[Symbol, T.untyped]),
        options: T.nilable(T::Hash[Symbol, T.untyped]),
        cursor: T.nilable(T.any(String, T::Hash[Symbol, T.untyped]))
      ).returns(GitHub::Spokes::Proto::Diffs::V2::ReadDiffPairsResponse)
    end
    def read_diff_pairs(diff_deltas:, resolved_base_selector: nil, options: nil, cursor: nil)
      request_context = default_request_context

      request = {
        repository: repository,
        request_context: request_context,
        diff_deltas: {
          diff_delta_list: diff_deltas
        }
      }

      request[:resolved_base_selector] = resolved_base_selector unless resolved_base_selector.nil?
      request[:options] = options unless options.nil?
      request[:cursor] = cursor unless cursor.nil?

      process_response(client.diffs.read_diff_pairs(request, req_opts))
    end

    # Public: Merges two trees and returns one of the following:
    #
    #   :STATUS_SUCCESS        - The merge was successful and the merged tree OID is returned.
    #   :STATUS_MERGE_CONFLICT - The merge failed due to a conflict. If `include_conflict_details` is true, then the
    #                            conflict details are returned. Else, return a `Google::Protobuf::Empty`.
    #   :STATUS_ALREADY_MERGED - The trees are already merged and a `Google::Protobuf::Empty` is returned.
    #
    # If the call site is only interested in the mergeability of the trees, then it is recommended to set
    # `mergeability_only` to true to prevent loose object creation in the repository.
    sig do
      params(
        base_oid: String,
        head_oid: String,
        base_repo_id: T.nilable(Integer),
        head_repo_id: T.nilable(Integer),
        merge_base_oid: T.nilable(String),
        merge_base_repo_id: T.nilable(Integer),
        mergeability_only: T::Boolean,
        include_conflict_details: T::Boolean,
        resolutions: T.nilable(T::Array[T::Hash[Symbol, T.untyped]]),
        qos: T.nilable(Symbol)
      ).returns(GitHub::Spokes::Proto::Merges::V1::MergeTreesResponse)
    end
    def merge_trees(
      base_oid:,
      head_oid:,
      base_repo_id: nil,
      head_repo_id: nil,
      merge_base_oid: nil,
      merge_base_repo_id: nil,
      mergeability_only: false,
      include_conflict_details: false,
      resolutions: nil,
      qos: nil
    )
      req = {
        request_context: default_request_context(qos: qos),
        repository: repository,
        base_selector: {
          by_oid: { id: base_oid }
        },
        head_selector: {
          by_oid: { id: head_oid }
        },
        options: {
          mergeability_only: mergeability_only,
          include_conflict_details: include_conflict_details
        }
      }
      req[:base_selector][:source_repository] = Types.new_repository(base_repo_id) unless base_repo_id.nil?
      req[:head_selector][:source_repository] = Types.new_repository(head_repo_id) unless head_repo_id.nil?

      if merge_base_oid.nil?
        req[:merge_base_none] = {}
      else
        req[:merge_base_selector] = { by_oid: { id: merge_base_oid } }
        req[:merge_base_selector][:source_repository] = Types.new_repository(merge_base_repo_id) unless merge_base_repo_id.nil?
      end

      req[:resolutions] = resolutions unless resolutions.nil?

      process_response(client.merges.merge_trees(req, req_opts))
    end

    def begin_transaction
      request = {
        repository: repository,
        request_context: default_request_context
      }

      process_response(client.transactions.begin_transaction(request, req_opts))
    end

    def commit_transaction
      request = {
        repository: repository,
        request_context: default_request_context
      }

      process_response(client.transactions.commit_transaction(request, req_opts))
    end

    def rollback_transaction
      request = {
        repository: repository,
        request_context: default_request_context
      }

      process_response(client.transactions.rollback_transaction(request, req_opts))
    end

    sig do
      type_parameters(:Result)
        .params(block: T.proc.returns(T.type_parameter(:Result)))
        .returns(T.type_parameter(:Result))
    end
    def with_transaction(&block)
      res = nil
      begin_transaction
      begin
        res = yield
      rescue
        rollback_transaction
        raise
      end
      commit_transaction
      res
    end

    def with_read_after_write(val)
      old, @context.read_after_write = @context.read_after_write, val
      begin
        yield
      ensure
        @context.read_after_write = old
      end
    end

    # Create an Enumerator that loads sequential responses for paginated Spokes
    # API endpoints.
    #
    # block - the method to call the Spokes API endpoint. Takes a 'cursor' as
    #         input, and must return an object with a 'next_cursor' field.
    #
    # Returns an Enumerator of responses.
    def self.paged_responses
      next_cursor = T.let(nil, T.untyped)
      Enumerator.new do |y|
        loop do
          result = yield next_cursor
          y << result
          next_cursor = result.next_cursor
          break if next_cursor.nil?
        end
      end
    end

    # Public: Returns the line count for a blob from the selectors
    #
    # selectors:
    #  (Array<Hash>, required) A list of selectors to count lines for.
    #   Each selector is a hash with one of the following keys:
    #    by_id: { id: } The OID of the blob
    #    by_name: { name: } The ref to read
    #    by_treeish_and_path: { treeish: { reference: { name: }, oid: { id: } }, path: { name: } } The treeish and path to read
    sig do
      params(
        selectors: T::Array[T::Hash[Symbol, T.untyped]],
      ).returns(GitHub::Spokes::Proto::Blobs::V1::CountLinesResponse)
    end
    def count_lines(selectors)
      request = {
        repository: repository,
        request_context: default_request_context,
        selectors: selectors
      }

      process_response(client.blobs.count_lines(request, req_opts))
    end

    # Public: Fetch maintenance status information for all replicas of the current repository.
    #
    # Returns a GitHub::Spokes::Proto::Maintenance::V1::MaintenanceInfoResponse
    # with a `.replicas` field containing per-replica maintenance status.
    sig { returns(GitHub::Spokes::Proto::Maintenance::V1::MaintenanceInfoResponse) }
    def maintenance_info
      request = {
        repository: repository,
        request_context: default_request_context,
      }

      process_response(client.maintenance.maintenance_info(request, req_opts))
    end

    private

    delegate :client, to: SpokesAPI::Connection

    def req_opts(headers: nil)
      if @cache_key && !@cache_key.empty?
        headers ||= {}
        headers["X-Spokes-Api-Cache-Key"] = @cache_key
      end

      if headers
        @req_opts.merge(headers: @req_opts[:headers].merge(headers))
      else
        @req_opts
      end
    end

    def process_response(resp)
      raise Error.from_twirp_error(resp.error) unless resp.error.nil?

      # Update the transaction state if the response contains a transaction_context
      resp_msg = resp.data
      if resp_msg.respond_to?(:transaction_context) && !resp_msg.transaction_context.nil?
        @context.transaction_state = resp_msg.transaction_context.transaction_state
      end

      # Capture cache key from the last Faraday response headers (set by middleware).
      val = SpokesAPI::Connection.response_headers&.[]("X-Spokes-Api-Cache-Key")
      @cache_key = val if val

      resp_msg
    end

    def default_request_context(qos: nil, reduce_cost_for_spokes_api: true)
      qos ||= SpokesAPI.quality_of_service ? SpokesAPI.quality_of_service : :QUALITY_OF_SERVICE_NO_DELAY

      {
        quality_of_service: qos,
        user_id: GitHub.context[:actor_id] ? GitHub.context[:actor_id] : 0,
        real_ip: GitHub.context[:actor_ip] ? GitHub.context[:actor_ip] : "",
        transaction_state: @context.transaction_state,
        read_after_write: self.read_after_write?,
        reduce_cost_for_spokes_api: reduce_cost_for_spokes_api,
      }
    end

    def read_after_write?
      # If read_after_write is not explicitly set, derive the value from the
      # ActiveRecord connection.
      @context.read_after_write != nil ? @context.read_after_write : ApplicationRecord::Spokes.connected_to?(role: :writing)
    end

    def map_attribution(attribution)
      time = attribution.fetch(:time)
      time = Time.iso8601(time) if time.instance_of? String

      {
        name: attribution.fetch(:name)&.b,
        email: attribution.fetch(:email)&.b,
        date: {
          timestamp: Google::Protobuf::Timestamp.new(seconds: time.to_i),
          offset: time.utc_offset
        }
      }
    end
  end
end
