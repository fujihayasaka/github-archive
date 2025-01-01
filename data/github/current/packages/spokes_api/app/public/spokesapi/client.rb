# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SpokesAPI
  class Client
    include Scientist

    # Public: returns a new Client for the given Repository.
    def self.for_repository(repository_id, network_id:)
      new(Types.new_repository(repository_id), headers: { "GitHub-Network-Id-Hint" => network_id.to_s })
    end

    # Public: returns a new Client for the given Gist.
    def self.for_gist(gist_id, gist_name:)
      new(Types.new_gist(gist_id), headers: { "GitHub-Gist-Name-Hint" => gist_name })
    end

    # Public: returns a new Client for the given Repository's wiki.
    def self.for_wiki(repository_id, network_id:)
      new(Types.new_wiki(repository_id), headers: { "GitHub-Network-Id-Hint" => network_id.to_s })
    end

    # Public: returns a new Client for multiple Repositories.
    def self.for_repositories(repository_ids)
      new(nil, repositories: repository_ids.map { |id| Types.new_repository(id) })
    end

    def initialize(repository, headers: nil, repositories: nil)
      request_headers = {}
      request_headers["Request-Timeout"] = SpokesAPI.timeout.to_s if SpokesAPI.timeout
      request_headers.update(headers) if headers

      @repository = repository
      @repositories = repositories
      @req_opts = { headers: request_headers }
    end

    # The repository stored here is the one from Spokes API, that is
    # types.Repository.
    attr_reader :repository
    attr_reader :repositories

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

      return nil if raw.error && raw.error.code == :not_found && raw.error.msg == "object not found"
      return nil if raw.error && raw.error.code == :unavailable
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
    # read_uncommited: (Bool, optional, default is false) Should only be set when data is read during _commit_refs
    #
    # Returns a list of blobs and the cursor to fetch the next page.
    def list_historical_reachable_blobs(reference_updates:, cursor:, read_uncommited: false)
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

      req[:request_context][:read_uncommitted] = read_uncommited
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
    # read_uncommited: (Bool, optional, default is false) Should only be set when data is read during _commit_refs
    #
    # Returns a list of blobs and the cursor to fetch the next page.
    def list_newly_reachable_blobs(reference_updates:, cursor:, base_repository_id:, read_uncommited: false)
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

      req[:request_context][:read_uncommitted] = read_uncommited
      req[:cursor] = cursor unless cursor.nil?

      process_response(client.blobs.list_reachable_blobs(req, @req_opts))
    end

    # Public: Return the list of commits based on a list of OIDs.
    #
    # oids (Array, required):
    # cursor: (String, required) The cursor to fetch
    # read_uncommited: (Bool, optional, default is false) Should only be set when data is read during _commit_refs
    #
    # Returns a list of reachable blobs and the cursor to fetch the next page.
    def list_commits_for_ids(oids:, cursor:, read_uncommited: false)
      req = {
        request_context: default_request_context,
        repository: repository,
        object_id_selector: {
          oids: oids.map { |oid| { id: oid } }
        }
      }

      req[:request_context][:read_uncommitted] = read_uncommited
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
    # read_uncommited: (Bool, optional, default is false) Should only be set when data is read during _commit_refs
    #
    # Returns a list of commits and the cursor to fetch the next page.
    def list_historical_commits(reference_updates:, cursor:, read_uncommited: false)
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

      req[:request_context][:read_uncommitted] = read_uncommited
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
    # read_uncommited: (Bool, optional, default is false) Should only be set when data is read during _commit_refs
    #
    # Returns a list of commits and the cursor to fetch the next page.
    def list_newly_reachable_commits(reference_updates:, cursor:, base_repository_id:, read_uncommited: false)
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

      req[:request_context][:read_uncommitted] = read_uncommited
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
    # Returns the name of the default branch.
    def get_default_branch
      request = {
        request_context: default_request_context,
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
    def commit_quarantine(push_state:)
      request = {
        repository: repository,
        request_context: default_request_context.merge(push_state: push_state),
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
    def ahead_behind_contains(base:, tips:, reduce_cost_for_spokes_api: false)
      request = {
        repository: repository,
        base_and_tips_selector: {
          base: { name: base },
          tips: tips.map { |tip| { name: tip } },
        },
        request_context: default_request_context(reduce_cost_for_spokes_api: reduce_cost_for_spokes_api),
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

    private

    delegate :client, to: SpokesAPI::Connection

    def process_response(resp)
      raise Error.from_twirp_error(resp.error) unless resp.error.nil?
      resp.data
    end

    def default_request_context(qos: nil, read_after_write: :default, reduce_cost_for_spokes_api: false)
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
