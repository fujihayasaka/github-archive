# typed: true
# frozen_string_literal: true

class Api::Internal::Blackbird < Api::Internal
  include ReceiveSchemaWithOpenApi

  REPO_LIMIT = 1_000

  # We have observed the has_readme? method taking over 9 seconds to complete.
  # This causes problems fetching repository metadata because the overall request times out.
  # Instead, we will set a reasonable timeout on this request.
  HAS_README_TIMEOUT_SECS = 1

  before do
    deliver_error!(404) if GitHub.enterprise?
  end

  COPILOT_INDEXED_REPO_BATCH_LIMIT = 50

  # Updates the `last_requested_at` timestamp of the associated `copilot_indexed_repositories` record for the provided repository id.
  #
  # The required JSON body properties are:
  # - repository_id: The repository id to update.
  #
  # This endpoint returns the following http status responses:
  # - 204: The `last_requested_at` timestamp was successfully updated for the repository.
  # - 400: The JSON request body was missing `repository_id`.
  # - 503: Service unavailable due to database throttling. The caller should try again later.
  post "/internal/blackbird/copilot_indexed_repositories", operation_id: :internal, exempt_from_tenant_context_requirement: true do
    @route_owner = "@github/blackbird"

    repo_id = data["repository_id"]
    deliver_error!(400, message: "property 'repository_id' is required in request body") if repo_id.blank?

    CopilotIndexedRepositories.where(repository_id: repo_id).update_all(last_requested_at: Time.now.utc) unless GitHub.flipper[:blackbird_embeddings_dry_run_update].enabled?
    deliver_empty(status: 204)
  end

  # Destroys the specified copilot indexed repositories record for the provided repository id.
  #
  # The required JSON body properties are:
  # - repository_id (integer): The repository id to delete.
  # - check (boolean): When true requires the endpoint to check if the record is deletable based on the criteria outlined in https://github.com/github/blackbird/blob/main/docs/adr/0054-repo-embeddings-index-deletions.md.
  #
  # This endpoint returns the following http status responses:
  # - 204: The record was successfully destroyed.
  # - 400: The JSON request body was missing `repositories_id`, `check`, or `check` was not a boolean.
  # - 404: The copilot indexed repositories record was not found.
  # - 405: The record was not destroyed because the `check` property was set to true and the record was determined to not be deletable.
  # - 503: Service unavailable due to database throttling. The caller should try again later.
  delete "/internal/blackbird/copilot_indexed_repositories", operation_id: :internal, exempt_from_tenant_context_requirement: true do
    @route_owner = "@github/blackbird"

    repo_id = data["repository_id"]
    deliver_error!(400, message: "property 'repository_id' is required in request body") if repo_id.blank?

    check = data["check"]
    deliver_error!(400, message: "property 'check' is required in request body") if check.nil?
    deliver_error!(400, message: "property 'check' must be a boolean") unless [true, false].include?(check)

    cir = CopilotIndexedRepositories.find_by(repository_id: repo_id)
    deliver_error!(404, message: "copilot indexed repositories record not found") if cir.nil?

    if check
      deliver_error!(405, message: "not deletable, repo is engaged oss repo") if Copilot::EngagedOssRepository.find_by(repository_id: repo_id)
      owner = T.must(cir).organization
      # Note: If the owner no longer exists but the copilot indexed repositories record is still present, we should delete it.
      deliver_error!(405, message: "not deletable, owner has paid access") if owner && Copilot::User.new(owner).has_paid_access?
    end

    # NB: Calling `destroy` ensures any associated callbacks on the model are also called.
    T.must(cir).destroy unless GitHub.flipper[:blackbird_embeddings_dry_run_delete].enabled?

    deliver_empty(status: 204)
  end

  # Retrieves `copilot_indexed_repositories` records based on `last_requested_at`.
  #
  # The following query parameters are optional:
  # - inclusive_start_timestamp: The timestamp (UTC) to start retrieval from (inclusive). If not provided, retrieval starts from the oldest records based on `last_requested_at`.
  # - exclusive_start_repo_id: The repo id to start retrieval from (exclusive) in combination with `inclusive_start_timestamp`. This value breaks ties in cases where 2 or more records share the same `last_requested_at` timestamp. Required when `inclusive_start_timestamp` is specified.
  # - limit: The maximum number of records to retrieve. When provided, the minimum between the specified limit or COPILOT_INDEXED_REPO_BATCH_LIMIT is used.
  #
  # If successful, this endpoint returns the following JSON body:
  # - copilot_indexed_repositories: The list of retrieved copilot indexed repositories records including only the repository_id and last_requested_at column values.
  #
  # This endpoint returns the following http status responses:
  # - 200: A batch of records was successfully retrieved.
  # - 204: No records were found.
  get "/internal/blackbird/copilot_indexed_repositories", operation_id: :internal, exempt_from_tenant_context_requirement: true do
    @route_owner = "@github/blackbird"

    halt deliver_empty(status: 204) unless GitHub.flipper[:blackbird_embeddings_maintenance].enabled?

    inclusive_start_timestamp = if params["inclusive_start_timestamp"].present?
      Time.parse(params["inclusive_start_timestamp"]).utc
    else
      CopilotIndexedRepositories.minimum(:last_requested_at)&.utc
    end
    halt deliver_empty(status: 204) if inclusive_start_timestamp.nil?

    exclusive_start_repo_id = if params["exclusive_start_repo_id"].present?
      params["exclusive_start_repo_id"].to_i
    else
      deliver_error!(400, message: "query param 'exclusive_start_repo_id' is required when 'inclusive_start_timestamp' is specified") if params["inclusive_start_timestamp"].present?
      0 # Because no repositories have id 0, this ensures all records are retrievable when `exclusive_start_repo_id` is not provided.
    end

    limit = (params["limit"].presence || COPILOT_INDEXED_REPO_BATCH_LIMIT).to_i.clamp(1, COPILOT_INDEXED_REPO_BATCH_LIMIT)

    query = Arel.sql(<<-SQL.squish)
SELECT repository_id, last_requested_at
FROM copilot_indexed_repositories
WHERE last_requested_at >= #{ApplicationRecord::Domain::Copilot.connection.quote(inclusive_start_timestamp)}
AND repository_id > #{exclusive_start_repo_id}
ORDER BY last_requested_at, repository_id ASC
LIMIT #{limit}
SQL
    cirs = ApplicationRecord::Domain::Copilot.connection.select_rows(query)
    if cirs.empty?
      deliver_empty(status: 204)
    else
      deliver_raw({
        copilot_indexed_repositories: cirs.map { |cir| { repository_id: cir[0], last_requested_at: cir[1].utc } },
      })
    end
  end

  # Retrieves the set of authorized private resources for a Blackbird actor. This data is cached and used
  # by Blackbird's query handling for preparing queries and filtering query results.
  #
  # The required JSON body properties are:
  #  - actor_id: Identifies the actor and is either a User or Bot id.
  #  - key_prefix: The Redis cache key prefix used to read / write accessible resource cache entries for the actor.
  #  - session_id: The id of the session for which to retrieve authorized resources and is either the UserSession#id or the hashed secret token.
  #  - token: The secret token used for authentication.
  #  - token_kind: The kind of token being used for authentication and is either API or WEB.
  #  - request_user_ip: The ip address of the original actor request forwarded from Blackbird.
  #
  # This endpoint returns the following http status responses:
  # - 200: Auth succeeded and accessible resources were computed and returned in the JSON response body. The response body is the serialized JSON representation of the AccessibleResources proto message https://github.com/github/hydro-schemas/blob/main/proto/hydro/schemas/blackbird/v0/entities/accessible_resources.proto
  # - 202: Auth succeeded but accessible resources could not be computed within the request duration timeout. The handler enqueued a background job to compute the accessible resources asynchronously and returned an empty JSON response body. Callers may resend the request after a short delay, or poll Redis for the cache entry.
  # - 400: The JSON request body is missing one or more of the required properties listed above.
  # - 401: The request failed authentication indicating the secret token is no longer valid.
  post "/internal/blackbird/accessible_resources", operation_id: "blackbird/list-accessible-resources", exempt_from_tenant_context_requirement: true do
    @route_owner = "@github/blackbird"

    actor_id = data["actor_id"]
    deliver_error!(400, message: "property 'actor_id' is required in request body") if actor_id.blank?

    key_prefix = data["key_prefix"]
    deliver_error!(400, message: "property 'key_prefix' is required in request body") if key_prefix.blank?

    session_id = data["session_id"]
    deliver_error!(400, message: "property 'session_id' is required in request body") if session_id.blank?

    token = data["token"]
    deliver_error!(400, message: "property 'token' is required in request body") if token.blank?

    request_user_ip = data["request_user_ip"]
    deliver_error!(400, message: "property 'request_user_ip' is required in request body") if request_user_ip.blank?

    token_kind = if data["token_kind"]
      data["token_kind"]
    else
      Search::Blackbird::Client::ACCESS_TOKEN_KIND_WEB
    end

    auth_result = BlackbirdSearch::AuthenticationAttempt.new(
      request_user_ip: request_user_ip,
      request_id: request_id,
      token: token,
      token_kind: token_kind,
      user_agent: request.user_agent
    ).result

    deliver_error!(401, message: auth_result.error) unless auth_result.success?

    key = BlackbirdSearch::Redis.key(key_prefix: key_prefix, actor_id: actor_id, session_id: session_id, ip_address: request_user_ip)
    cache_entry_result = BlackbirdSearch::Redis.get(key: key)
    if !cache_entry_result.ok?
      GitHub.logger.error("error getting accessible resources cache entry", {
          "exception" => cache_entry_result.error,
          "code.function" => __method__,
          "code.namespace" => self.class.name,
          "gh.actor.id" => actor_id,
          "request_id" => request_id,
        })
      deliver_error!(500, message: "unexpected error when fetching accessible resources")
    end

    if cache_entry_result.value!
      ttl_result = BlackbirdSearch::Redis.pttl(key: key)
      if ttl_result.ok?
        remaining_ttl_ms = ttl_result.value!
        if remaining_ttl_ms <= 1.minute.to_i * 1000
          BlackbirdSearch::Redis.with_redis_retry do
            BlackbirdAccessibleResourcesJob.perform_later(
              actor: T.must(auth_result.actor),
              auth_id: T.must(auth_result.auth_id),
              auth_type: auth_result.auth_type,
              expires_at: auth_result.expires_at,
              has_lock: false,
              key_prefix: key_prefix,
              request_id: request_id,
              request_user_ip: request_user_ip,
              session_id: session_id,
              token_kind: token_kind,
            )
          end
        end
      end
      return deliver_raw(Hydro::Schemas::Blackbird::V0::Entities::AccessibleResources.decode(cache_entry_result.value!).to_h)
    end

    # If cache miss for actor's accessible resources:
    #   Attempt to acquire lock.
    #     If lock cannot be acquired, return 202 http status (another process is already refreshing the cache).
    #     If lock is acquired, attempt to build the actor within the specified timeout.
    #       If actor is built, cache the result, release lock, and return the result with 200 http status.
    #       If actor cannot be built (timeout condition) reached, enqueue a background job (has_lock: true) using hash locking, don't release the lock, and return 202 http status.
    mutex = BlackbirdSearch::Redis.mutex(key: key)
    begin
      mutex.lock
      blackbird_actor = T.must(auth_result.blackbird_actor)

      Timeout::timeout(8.seconds) do
        @accessible_resources = blackbird_actor.accessible_resources
      end

      BlackbirdSearch::Redis.set(
        key: key,
        value: @accessible_resources.to_proto,
        expire_sec: 10.minutes,
      )

      mutex.unlock
      deliver_raw(@accessible_resources.to_h)
    rescue GitHub::Redis::Mutex::LockError
      # If lock cannot be acquired another another process is already refreshing the cache, return accepted response.
      deliver_empty({ status: 202 })
    rescue Timeout::Error
      BlackbirdSearch::Redis.with_redis_retry do
        # If computing accessible resources times out, enqueue a background job without releasing the lock, and return accepted response.
        BlackbirdAccessibleResourcesJob.perform_later(
          actor: T.must(auth_result.actor),
          auth_id: T.must(auth_result.auth_id),
          auth_type: auth_result.auth_type,
          expires_at: auth_result.expires_at,
          has_lock: true,
          key_prefix: key_prefix,
          request_id: request_id,
          request_user_ip: request_user_ip,
          session_id: session_id,
          token_kind: token_kind,
        )
      end

      deliver_empty({ status: 202 })
    rescue => e
      mutex.unlock
      GitHub.logger.error("unexpected error when computing accessible resources", {
        "exception" => e,
        "code.function" => __method__,
        "code.namespace" => self.class.name,
        "gh.actor.id" => actor_id,
        "request_id" => request_id,
      })
      deliver_error!(500, message: "unexpected error when computing accessible resources")
    end
  end

  # Get a single repository by id or NWO (using API routing). The response is designed to allow blackbird to keep its
  # repository database in sync with github.
  get "/internal/blackbird/repositories/:repository_id", operation_id: :internal, resolve_tenant_context: :resolve_tenant_from_repo do
    @route_owner = "@github/blackbird"
    if repo = find_repo!
      ensure_repo_is_accessible
    end

    if repo.owner.nil?
      deliver_error!(missing_repository_status_code)
    end

    if params[:min_updated_at_ts].present?
      min_updated_at = Time.zone.at(params[:min_updated_at_ts].to_i)

      if repo.updated_at < min_updated_at
        GitHub.logger.info(
          "database replication behind min_updated_at_ts",
          "gh.repo.id" => repo.id,
          "gh.repo.min.updated_at" => min_updated_at,
          "gh.repo.updated_at" => repo.updated_at.to_i
        )
        headers["Retry-After"] = 0.5
        deliver_error!(503, message: "database replication not ready, retry later")
      end
    end

    has_readme = T.let(nil, T.nilable(T::Boolean))
    if GitHub.flipper[:blackbird_readme].enabled?
      start = Time.now
      begin
        GitHub::Timer.timeout(HAS_README_TIMEOUT_SECS) do
          has_readme = repo.has_readme?
          GitHub.dogstats.distribution("blackbird_api.get_repository.has_readme.duration", (Time.now - start) * 1000, tags: ["status:success"])
        end
      rescue GitRPC::Failure, GitRPC::Error, ::Timeout::Error => e
        # NOTE: Having a readme is used only for repository scoring. If the request fails for any reason, continue.
        GitHub.logger.error(
          "error fetching readme, ignoring",
          :exception => e,
          "gh.repo.id" => repo.id)
        GitHub.dogstats.distribution("blackbird_api.get_repository.has_readme.duration", (Time.now - start) * 1000, tags: ["status:error"])
      end
    end

    repo_hash = {
      id: repo.id,
      network_id: repo.network_id,
      owner_id: repo.owner.id,
      owner_login: repo.owner.login,
      owner_spammy: repo.owner.spammy?,
      name: repo.name,
      public: repo.public?,
      archived: repo.archived?,
      disk_usage: repo.disk_usage,
      pushed_at: Api::Serializer.time(repo.pushed_at),
      created_at: Api::Serializer.time(repo.created_at),
      license_name: repo.license&.name,
      num_watchers: repo.watchers_count,
      num_stars: repo.stargazer_count,
      has_readme: has_readme,
      public_fork_count: repo.public_fork_count,
      paying_customer: ::BlackbirdSearch::Helpers.repository_owner_is_paying_customer?(repo),
      fork: repo.fork?,
      experiments: Search::Blackbird.experiments(CopilotIndexedRepositories.find_by(repository_id: repo.id)),
      updated_at: Api::Serializer::time(repo.updated_at),
      seq_no: repo.blackbird_seq_no,
    }

    deliver_raw(repo_hash)
  end

  # Looks up the specified fields for every repository in the provided list of repository ids,
  # or uses a cursor to paginate through all repositories (only in proxima envs).
  # Requires a JSON body with a `cursor` (string) or `repository_ids` ([int])
  post "/internal/blackbird/repositories", operation_id: :internal, exempt_from_tenant_context_requirement: true do
    @route_owner = "@github/blackbird"

    ActiveRecord::Base.connected_to(role: :reading) do
      if data["cursor"]
        deliver_error!(400, message: "cursor query param is not supported in this environment") unless GitHub.multi_tenant_enterprise?
        limit = [data["limit"] || REPO_LIMIT, REPO_LIMIT].min

        # TODO: Use domain model to load.
        repos = Repository
          .active
          .order(:id)
          .where("repositories.id >= ?", data["cursor"])
          .limit(limit)
          .all
      else
        repo_ids = data["repository_ids"]
        deliver_error!(400, message: "repository_ids query param is required if cursor query param is not provided") if repo_ids.blank?
        deliver_error!(400, message: "repository_ids exceeds allowed limit (#{REPO_LIMIT})") if repo_ids.length > REPO_LIMIT

        repos = ::Repositories.domain.by_ids(repo_ids)
      end

      # NOTE: We load owners separately so we can load trade restrictions with them to prevent an n+1 query
      owners = Users.domain.by_ids(repos.map(&:owner_id))
      GitHub::PrefillAssociations.prefill_associations(owners, [:trade_controls_restriction])
      GitHub::PrefillAssociations.prefill_associations(repos, [:internal_repository, :repository_auth_version, :network])
      GitHub::PrefillAssociations.prefill_associations(repos, :owner, available_records: owners)
      if GitHub.flipper[:use_billing_locked_rather_than_disabled].enabled?
        GitHub::PrefillAssociations.prefill_batch_method(repos, :plan_customer_disabled?)
      end

      found_repo_ids = repos.map(&:id)

      # NOTE: There is no association between repositories and CopilotIndexedRepositories, so we cannot prefill assocations
      copilot_indexed_repos = CopilotIndexedRepositories
        .where(repository_id: found_repo_ids)
        .index_by(&:repository_id)

      result = {
        repositories: repos.filter_map { |repo| bulk_repo_hash(repo, copilot_indexed_repos) }
      }

      if data["cursor"]
        # If the number of repositories found (before filtering) is equal to the limit, then we return a next_cursor for the caller
        # to continue paging through the remaining repository records. Otherwise no next_cursor is returned, indicating
        # that the caller has reached the end of the repository records.
        if found_repo_ids.length == limit
          result[:next_cursor] = (T.must(found_repo_ids.last) + 1).to_s
        end
      end

      deliver_raw(result)
    end
  end

  # Get a single user by id or login (using API routing).
  get "/internal/blackbird/user/:user_id", operation_id: :internal, resolve_tenant_context: :resolve_tenant_from_user do
    @route_owner = "@github/blackbird"
    user = find_user!
    deliver(
      :user_hash,
      user,
      last_modified: calc_last_modified_for_object(user),
      exclude_email: true,
    )
  end

  def require_request_hmac?
    true
  end

  def externally_accessible?
    false
  end

  def check_allowlist_for_request_limiting
    GitHub::Limiters::Middleware.skip_limit_checks(env)
  end

  def resolve_tenant_from_repo
    repo = find_repo!
    Business.find_by(id: repo.tenant_id)
  end

  def resolve_tenant_from_user
    user = find_user!
    Business.find_by(id: user.business_id)
  end

  private

  def data
    return @data if defined? @data
    @data = receive_with_openapi
  end

  def deliver_error!(status, options = {})
    GitHub.logger.error(
      "Internal Blackbird Error",
      "gh.auth.token.error.message" => options[:message],
      "http.status_code" => status
    )
    super(status, options)
  end

  sig do
    params(repo: ::Repositories::IRepository, copilot_indexed_repos: T::Hash[Integer, CopilotIndexedRepositories]).
    returns(T.nilable(T::Hash[Symbol, T.untyped]))
  end
  def bulk_repo_hash(repo, copilot_indexed_repos)
    # Return nil for repositories that are not accessible with checks from ensure_repo_is_accessible.
    #
    # NOTE: Must downcast because IRepository doesn't have all the methods needed for these checks.
    repo = T.cast(repo, Repository) # rubocop:todo GitHub/AvoidCast
    begin
      return nil if repo.network_broken? # Broken network (raises NetworkMissingError if database is in an invalid state)
      return nil if repo.access.disabled? # DMCA takedowns, etc
      return nil if repo.disabled? # Trade restrictions
      return nil if repo.owner.nil? # Orphaned repo
    rescue Repository::NetworkDependency::NetworkMissingError => e
      Failbot.report e
      return nil
    end

    {
      id: repo.id,
      name: repo.name,
      owner_id: T.must(repo.owner).id,
      owner_login: T.must(repo.owner).login,
      public: repo.public?,
      archived: repo.archived?,
      updated_at: Api::Serializer::time(repo.updated_at),
      experiments: Search::Blackbird.experiments(copilot_indexed_repos[T.must(repo.id)]),
      seq_no: repo.repository_auth_version&.version || 1,
    }
  end
end
